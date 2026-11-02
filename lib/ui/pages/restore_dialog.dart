import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_format.dart';
import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../data/backups.dart';
import '../../state/clock.dart';
import '../../state/toast.dart';
import '../../state/workspace.dart';
import '../theme.dart';

final _time = DateFormat('HH:mm');

/// "Restore Previous Version…" for a project (docs/DECISIONS.md D12): pick one of the local backups and replace
/// the project with it. The current version is backed up first, so a restore can be undone the same way.
Future<void> showRestoreProjectDialog(
  BuildContext context,
  WidgetRef ref,
  Project project,
) => showDialog<void>(
  context: context,
  builder: (_) => _RestoreDialog(project: project),
);

class _RestoreDialog extends ConsumerStatefulWidget {
  const _RestoreDialog({required this.project});
  final Project project;

  @override
  ConsumerState<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<_RestoreDialog> {
  late final Future<List<Backup>> _backups = ref
      .read(workspaceProvider.notifier)
      .projectBackups(widget.project.id);
  Backup? _selected;
  bool _restoring = false;

  String _label(Backup b) {
    final local = b.takenAt.toLocal();
    final day = relativeDate(
      LocalDate.fromDateTime(local),
      ref.read(todayProvider),
    );
    return '$day, ${_time.format(local)}';
  }

  Future<void> _restore() async {
    final backup = _selected;
    if (backup == null) return;
    setState(() => _restoring = true);
    final leftOut = await ref
        .read(workspaceProvider.notifier)
        .restoreProjectBackup(widget.project.id, backup);
    if (!mounted) return;
    Navigator.pop(context);
    final moved = switch (leftOut) {
      null || 0 => '',
      1 => ' 1 task that has since moved to another project stayed there.',
      final n =>
        ' $n tasks that have since moved to other projects stayed there.',
    };
    ref
        .read(toastProvider.notifier)
        .show(
          leftOut == null
              ? "Couldn't restore that version: the backup can't be read."
              : 'Restored ${widget.project.name} to ${_label(backup)}.$moved',
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      content: SizedBox(
        width: 380,
        child: FutureBuilder<List<Backup>>(
          future: _backups,
          builder: (context, snapshot) {
            final backups = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restore ${widget.project.name}',
                  style: TextStyles.section(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick an earlier version. Your current version is kept as a backup, so you can switch back.',
                  style: TextStyles.bodySecondary(context),
                ),
                const SizedBox(height: 12),
                if (backups == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (backups.isEmpty)
                  Text(
                    'No earlier versions yet. Tasklet keeps one before you change a project, at most every 10 '
                    'minutes, on this computer.',
                    style: TextStyles.body(context),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: backups.length,
                      itemBuilder: (context, i) {
                        final b = backups[i];
                        final selected = identical(b, _selected);
                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(() => _selected = b),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: selected ? t.selected : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 14,
                                  color: selected ? t.accent : t.tertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _label(b),
                                    style: TextStyles.body(context),
                                  ),
                                ),
                                Text(
                                  _size(b.bytes),
                                  style: TextStyles.meta(context),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null || _restoring ? null : _restore,
          child: Text(_restoring ? 'Restoring…' : 'Restore'),
        ),
      ],
    );
  }
}

String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
