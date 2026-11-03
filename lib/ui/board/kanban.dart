import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/sorting.dart';
import '../../state/ui_state.dart';
import '../glyphs.dart';
import '../task/pickers.dart';
import '../task/task_menu.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_tiles.dart';

/// Where a drop lands: a status column and an index in that column's list (excluding the dragged card).
typedef DropTarget = ({TaskStatus status, int index});

/// Drives card dragging on the board (SPEC §5.1 "drag interaction physics"):
/// lift with tilt/scale/shadow, exact pointer following, a gliding drop line, edge auto-scroll, a settle animation
/// on drop, Escape to fly back, and FLIP sliding of the other cards. Reduce-motion skips the animations.
class BoardDragController extends ChangeNotifier {
  BoardDragController({required this.vsync, required this.onDrop});

  final TickerProvider vsync;

  /// Applies the drop; returns once state has been updated.
  final Future<void> Function(ProjectTask entry, DropTarget target) onDrop;

  // Registries filled by the widgets below.
  final cardKeys = <String, GlobalKey>{};
  final columnKeys = <TaskStatus, GlobalKey>{};
  final columnScroll = <TaskStatus, ScrollController>{};
  final columnLists = <TaskStatus, List<ProjectTask>>{};
  final boardScroll = ScrollController();
  final boardKey = GlobalKey();

  /// Previous content offsets of cards, for FLIP.
  final flipOffsets = <String, double>{};

  ProjectTask? dragging;
  TaskStatus? origin;
  String? settlingId;
  DropTarget? target;
  bool reduceMotion = false;

  Offset _pointer = Offset.zero;
  Offset _grab = Offset.zero;
  Size _size = Size.zero;
  int? _pointerId;
  bool _inputAttached = false;
  OverlayEntry? _ghost;
  Widget? _ghostChild;
  Timer? _autoScroll;
  late final AnimationController _lift = AnimationController(
    vsync: vsync,
    duration: const Duration(milliseconds: 150),
  );
  AnimationController? _settle;
  Offset _settleFrom = Offset.zero;
  Offset _settleTo = Offset.zero;

  bool get isDragging => dragging != null;

  // ------------------------------------------------------------------ geometry

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? columnRect(TaskStatus s) =>
      columnKeys[s] == null ? null : _rectOf(columnKeys[s]!);
  Rect? cardRect(String id) =>
      cardKeys[id] == null ? null : _rectOf(cardKeys[id]!);

  List<ProjectTask> _listWithoutDragged(TaskStatus s) => [
    for (final e in columnLists[s] ?? const <ProjectTask>[])
      if (e.task.id != dragging?.task.id) e,
  ];

  DropTarget? _computeTarget() {
    TaskStatus? status;
    for (final s in TaskStatus.values) {
      final r = columnRect(s);
      if (r != null && r.left <= _pointer.dx && _pointer.dx < r.right) {
        status = s;
      }
    }
    if (status == null) return null;
    final list = _listWithoutDragged(status);
    int? lastVisible;
    for (final (i, e) in list.indexed) {
      final r = cardRect(e.task.id);
      if (r == null) continue;
      if (_pointer.dy < r.center.dy) return (status: status, index: i);
      lastVisible = i;
    }
    return (
      status: status,
      index: lastVisible == null
          ? (list.isEmpty ? 0 : list.length)
          : lastVisible + 1,
    );
  }

  /// Y of the drop line relative to the column body, or null if it can't be placed.
  double? dropLineY(TaskStatus s) {
    final t = target;
    if (t == null || t.status != s) return null;
    final col = columnRect(s);
    if (col == null) return null;
    final list = _listWithoutDragged(s);
    if (list.isEmpty) return 4;
    if (t.index < list.length) {
      final r = cardRect(list[t.index].task.id);
      if (r != null) return r.top - col.top - 5;
    }
    if (t.index > 0) {
      final r = cardRect(list[t.index - 1].task.id);
      if (r != null) return r.bottom - col.top + 3;
    }
    return null;
  }

  // ------------------------------------------------------------------ lifecycle

  void start(
    ProjectTask entry,
    PointerEvent event,
    Rect cardRect,
    Widget ghost,
    BuildContext context,
  ) {
    if (isDragging) return;
    dragging = entry;
    origin = entry.task.status;
    _pointerId = event.pointer;
    _pointer = event.position;
    _grab = event.position - cardRect.topLeft;
    _size = cardRect.size;
    _ghostChild = ghost;
    target = (status: entry.task.status, index: 0);
    target = _computeTarget();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _inputAttached = true;
    _ghost = OverlayEntry(builder: _buildGhost);
    Overlay.of(context, rootOverlay: true).insert(_ghost!);
    if (reduceMotion) {
      _lift.value = 1;
    } else {
      _lift.forward(from: 0);
    }
    _lift.addListener(_markGhost);
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickAutoScroll(),
    );
    notifyListeners();
  }

  void _markGhost() => _ghost?.markNeedsBuild();

  void _onPointer(PointerEvent event) {
    if (event.pointer != _pointerId) return;
    if (event is PointerMoveEvent) {
      _pointer = event.position;
      _ghost?.markNeedsBuild();
      _updateTarget();
    } else if (event is PointerUpEvent) {
      _drop();
    } else if (event is PointerCancelEvent) {
      _cancel();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        isDragging) {
      _cancel();
      return true;
    }
    return false;
  }

  void _updateTarget() {
    final next = _computeTarget();
    if (next != target) {
      target = next;
      notifyListeners();
    }
  }

  void _tickAutoScroll() {
    const edge = 56.0;
    double speed(double distance) =>
        distance >= edge ? 0 : 20 * (1 - (distance / edge).clamp(0, 1));
    var moved = false;
    final status = target?.status;
    if (status != null) {
      final r = columnRect(status);
      final c = columnScroll[status];
      if (r != null && c != null && c.hasClients) {
        final up = speed(_pointer.dy - r.top),
            down = speed(r.bottom - _pointer.dy);
        final delta = down - up;
        if (delta != 0) {
          final next = (c.offset + delta).clamp(
            0.0,
            c.position.maxScrollExtent,
          );
          if (next != c.offset) {
            c.jumpTo(next);
            moved = true;
          }
        }
      }
    }
    final board = _rectOf(boardKey);
    if (board != null && boardScroll.hasClients) {
      final delta =
          speed(board.right - _pointer.dx) - speed(_pointer.dx - board.left);
      if (delta != 0) {
        final next = (boardScroll.offset + delta).clamp(
          0.0,
          boardScroll.position.maxScrollExtent,
        );
        if (next != boardScroll.offset) {
          boardScroll.jumpTo(next);
          moved = true;
        }
      }
    }
    if (moved) _updateTarget();
  }

  void _detachInput() {
    if (_inputAttached) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      HardwareKeyboard.instance.removeHandler(_onKey);
      _inputAttached = false;
    }
    _autoScroll?.cancel();
    _pointerId = null;
  }

  Future<void> _drop() async {
    final entry = dragging;
    final dropTarget = target;
    _detachInput();
    if (entry == null) return;
    final ghostAt = _pointer - _grab;
    final sameColumnNonManual =
        dropTarget != null &&
        dropTarget.status == origin &&
        !isManuallyOrdered(order, dropTarget.status);
    if (dropTarget == null || sameColumnNonManual) {
      await _flyTo(ghostAt, () => cardRect(entry.task.id)?.topLeft);
      return;
    }
    settlingId = entry.task.id;
    await onDrop(entry, dropTarget);
    dragging = null;
    target = null;
    notifyListeners();
    await _flyTo(ghostAt, () => cardRect(entry.task.id)?.topLeft);
  }

  void _cancel() {
    final entry = dragging;
    _detachInput();
    if (entry == null) return;
    unawaited(_flyTo(_pointer - _grab, () => cardRect(entry.task.id)?.topLeft));
  }

  /// Animates the ghost from [from] to wherever [to] resolves after the next frame, then ends the drag.
  Future<void> _flyTo(Offset from, Offset? Function() to) async {
    target = null;
    notifyListeners();
    await WidgetsBinding.instance.endOfFrame;
    final dest = to();
    if (reduceMotion || dest == null) {
      _end();
      return;
    }
    _settleFrom = from;
    _settleTo = dest;
    final settle = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 240),
    );
    _settle = settle;
    settle.addListener(_markGhost);
    _lift.reverse();
    await settle.animateTo(1, curve: Curves.easeOutCubic);
    settle.dispose();
    _settle = null;
    _end();
  }

  void _end() {
    _lift.removeListener(_markGhost);
    _lift.value = 0;
    _ghost?.remove();
    _ghost = null;
    _ghostChild = null;
    dragging = null;
    origin = null;
    settlingId = null;
    target = null;
    notifyListeners();
  }

  /// The board's sort order (decides whether drops reposition).
  SortOrder order = SortOrder.manual;

  Widget _buildGhost(BuildContext context) {
    final settle = _settle;
    final position = settle == null
        ? _pointer - _grab
        : Offset.lerp(
            _settleFrom,
            _settleTo,
            Curves.easeOutCubic.transform(settle.value),
          )!;
    final lift = Curves.easeOutCubic.transform(_lift.value);
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: _size.width,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: lift * 1.5 * math.pi / 180,
          child: Transform.scale(scale: 1 + 0.03 * lift, child: _ghostChild),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detachInput();
    _ghost?.remove();
    _lift.dispose();
    _settle?.dispose();
    boardScroll.dispose();
    for (final c in columnScroll.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The 4-column kanban board (SPEC §5.1).
class KanbanBoard extends ConsumerStatefulWidget {
  const KanbanBoard({
    super.key,
    required this.groups,
    required this.display,
    required this.crossProject,
    required this.onDrop,
    required this.onAdd,
    this.readOnly = false,
  });

  final Map<TaskStatus, List<ProjectTask>> groups;
  final ViewDisplay display;
  final bool crossProject;
  final Future<void> Function(ProjectTask entry, DropTarget target) onDrop;
  final ValueChanged<TaskStatus> onAdd;
  final bool readOnly;

  @override
  ConsumerState<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends ConsumerState<KanbanBoard>
    with TickerProviderStateMixin {
  late final BoardDragController _drag = BoardDragController(
    vsync: this,
    onDrop: (e, t) => widget.onDrop(e, t),
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _drag
      ..reduceMotion = MediaQuery.disableAnimationsOf(context)
      ..order = widget.display.order;
    for (final s in TaskStatus.values) {
      _drag.columnLists[s] = widget.groups[s] ?? const [];
      _drag.columnScroll.putIfAbsent(s, ScrollController.new);
      _drag.columnKeys.putIfAbsent(s, GlobalKey.new);
    }
    final statuses = [
      for (final s in TaskStatus.values)
        if (!widget.display.hideEmptySections ||
            (widget.groups[s]?.isNotEmpty ?? false))
          s,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const minWidth = 260.0, gap = 12.0, pad = 16.0;
        final available =
            constraints.maxWidth - pad * 2 - gap * (statuses.length - 1);
        final width = math.max(
          minWidth,
          available / math.max(1, statuses.length),
        );
        return Scrollbar(
          controller: _drag.boardScroll,
          child: SingleChildScrollView(
            key: _drag.boardKey,
            controller: _drag.boardScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(pad, 12, pad, 0),
            child: SizedBox(
              height: constraints.maxHeight - 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, s) in statuses.indexed) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: width,
                      child: _Column(status: s, board: widget, drag: _drag),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.status,
    required this.board,
    required this.drag,
  });
  final TaskStatus status;
  final KanbanBoard board;
  final BoardDragController drag;

  String get _orderLabel => switch (board.display.order) {
    SortOrder.manual => 'Sorted by most recent',
    SortOrder.priority => 'Ordered by priority',
    SortOrder.dueDate => 'Ordered by due date',
    SortOrder.updated => 'Ordered by last updated',
    SortOrder.newest => 'Ordered by newest',
  };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final tasks = board.groups[status] ?? const [];
    final manualHere = isManuallyOrdered(board.display.order, status);
    return Hoverable(
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 4),
                StatusIcon(status),
                const SizedBox(width: 8),
                // Narrow columns (900 px window, large text) shorten the label and the hint instead of overflowing.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          status.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.section(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      CountText(tasks.length),
                      if (status == TaskStatus.done &&
                          board.display.order == SortOrder.manual) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Recent first',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.meta(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!board.readOnly)
                  IconBtn(
                    icon: Icons.add,
                    tooltip: 'New ${status.label} task',
                    onPressed: () => board.onAdd(status),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: drag,
              builder: (context, _) {
                final dragging = drag.isDragging;
                final over = drag.target?.status == status;
                final showOverlay = dragging && !manualHere;
                final lineY = dragging && manualHere
                    ? drag.dropLineY(status)
                    : null;
                return Container(
                  key: drag.columnKeys[status],
                  decoration: BoxDecoration(
                    color: over && dragging ? t.hover : t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: over && dragging
                          ? t.accent.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: Stack(
                    children: [
                      _cards(context, tasks, hovered),
                      if (lineY != null)
                        AnimatedPositioned(
                          duration: drag.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          left: 8,
                          right: 8,
                          top: lineY.clamp(0, double.infinity),
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      if (showOverlay)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: t.background.withValues(
                                  alpha: over ? 0.55 : 0.35,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                over && drag.origin != status
                                    ? 'Move to ${status.label}'
                                    : _orderLabel,
                                style: TextStyles.sectionLabel(context)
                                    .copyWith(
                                      color: over ? t.primary : t.secondary,
                                    ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(BuildContext context, List<ProjectTask> tasks, bool hovered) {
    final showAdd =
        !board.readOnly && (tasks.isEmpty || hovered) && !drag.isDragging;
    return ListView.builder(
      controller: drag.columnScroll[status],
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
      itemCount: tasks.length + 1,
      itemBuilder: (context, i) {
        if (i == tasks.length) {
          return Opacity(
            opacity: showAdd ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TextButton.icon(
                onPressed: showAdd ? () => board.onAdd(status) : null,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('New Task'),
              ),
            ),
          );
        }
        final e = tasks[i];
        return Padding(
          key: ValueKey(e.task.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: _DraggableCard(entry: e, board: board, drag: drag),
        );
      },
    );
  }
}

class _DraggableCard extends ConsumerStatefulWidget {
  const _DraggableCard({
    required this.entry,
    required this.board,
    required this.drag,
  });
  final ProjectTask entry;
  final KanbanBoard board;
  final BoardDragController drag;

  @override
  ConsumerState<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends ConsumerState<_DraggableCard>
    with SingleTickerProviderStateMixin {
  final _key = GlobalKey();
  Offset? _down;
  int? _pointer;
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _flipFrom = 0;

  String get _id => widget.entry.task.id;

  @override
  void initState() {
    super.initState();
    widget.drag.cardKeys[_id] = _key;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _recordOffset(animate: false),
    );
  }

  @override
  void didUpdateWidget(_DraggableCard old) {
    super.didUpdateWidget(old);
    widget.drag.cardKeys[_id] = _key;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _recordOffset(animate: true),
    );
  }

  @override
  void dispose() {
    if (widget.drag.cardKeys[_id] == _key) widget.drag.cardKeys.remove(_id);
    _flip.dispose();
    super.dispose();
  }

  /// FLIP: compare this card's position in its column's scroll content with last time and slide from the old spot.
  void _recordOffset({required bool animate}) {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final offset = viewport.getOffsetToReveal(box, 0).offset;
    final previous = widget.drag.flipOffsets[_id];
    widget.drag.flipOffsets[_id] = offset;
    if (!animate ||
        previous == null ||
        widget.drag.reduceMotion ||
        widget.drag.isDragging) {
      return;
    }
    final delta = previous - offset;
    if (delta.abs() < 1) return;
    _flipFrom = delta;
    _flip.forward(from: 0);
  }

  void _open() => ref
      .read(openTaskProvider.notifier)
      .open(TaskRef(widget.entry.project.id, widget.entry.task.id));

  @override
  Widget build(BuildContext context) {
    final drag = widget.drag;
    final card = TaskCard(
      entry: widget.entry,
      display: widget.board.display,
      crossProject: widget.board.crossProject,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([drag, _flip]),
      builder: (context, child) {
        final isOrigin = drag.dragging?.task.id == _id;
        final settling = drag.settlingId == _id;
        final dy = _flip.isAnimating
            ? _flipFrom * (1 - Curves.easeOutCubic.transform(_flip.value))
            : 0.0;
        Widget content = child!;
        if (isOrigin) {
          content = _Placeholder(child: Opacity(opacity: 0, child: content));
        }
        if (settling && !isOrigin) {
          content = Opacity(opacity: 0, child: content);
        }
        return Transform.translate(offset: Offset(0, dy), child: content);
      },
      child: ContextMenuRegion(
        menuChildren: () => taskMenuChildren(context, ref, widget.entry),
        child: TaskFocus(
          taskRef: TaskRef(widget.entry.project.id, _id),
          builder: (focused) => Listener(
            onPointerDown: (e) {
              if (e.buttons != kPrimaryButton ||
                  DragGate.isClaimed(e.pointer)) {
                return;
              }
              _down = e.position;
              _pointer = e.pointer;
            },
            onPointerMove: (e) {
              if (_down == null ||
                  e.pointer != _pointer ||
                  drag.isDragging ||
                  widget.board.readOnly) {
                return;
              }
              if ((e.position - _down!).distance < 5) return;
              final box = _key.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;
              final rect = box.localToGlobal(Offset.zero) & box.size;
              _down = null;
              drag.start(
                widget.entry,
                e,
                rect,
                UncontrolledProviderScope(
                  container: ProviderScope.containerOf(context),
                  child: Theme(
                    data: Theme.of(context),
                    child: Material(
                      type: MaterialType.transparency,
                      child: TaskCard(
                        entry: widget.entry,
                        display: widget.board.display,
                        crossProject: widget.board.crossProject,
                        lifted: true,
                      ),
                    ),
                  ),
                ),
                context,
              );
            },
            onPointerUp: (e) {
              if (_down != null &&
                  e.pointer == _pointer &&
                  !DragGate.isClaimed(e.pointer)) {
                _open();
              }
              _down = null;
            },
            onPointerCancel: (_) => _down = null,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                key: _key,
                decoration: focused
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Tokens.of(context).accent
                              .withValues(alpha: 0.6),
                        ),
                      )
                    : null,
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed outline left where a dragged card came from (SPEC §8.6).
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedRRect(Tokens.of(context).tertiary),
    child: child,
  );
}

class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}
