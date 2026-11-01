import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/whats_new_notes.dart';
import '../router.dart';
import '../state/prefs.dart';
import 'theme.dart';

/// Shows the What's New sheet (SPEC §13). Any dismissal marks the current notes as read on this machine.
Future<void> showWhatsNew(BuildContext context, WidgetRef ref) => _show(
  context,
  () => ref
      .read(prefsProvider.notifier)
      .set(PrefKeys.whatsNewSeen, currentRelease.id),
);

/// Same, from code without a widget context (Settings window, Help menu).
Future<void> showWhatsNewFromAnywhere(ProviderContainer container) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  await _show(
    context,
    () => container
        .read(prefsProvider.notifier)
        .set(PrefKeys.whatsNewSeen, currentRelease.id),
  );
}

bool _open = false;

Future<void> _show(
  BuildContext context,
  Future<void> Function() markRead,
) async {
  if (_open) return;
  _open = true;
  // Nothing should scroll into view when focus returns after closing (keeps the sidebar still, SPEC §13).
  FocusManager.instance.primaryFocus?.unfocus();
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => const _WhatsNewDialog(),
    );
  } finally {
    _open = false;
    await markRead();
  }
}

class _WhatsNewDialog extends StatefulWidget {
  const _WhatsNewDialog();

  @override
  State<_WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<_WhatsNewDialog> {
  final _scroll = ScrollController();
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!_scroll.hasClients) return;
    final atEnd =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 4;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _more() {
    final target = (_scroll.offset + _scroll.position.viewportDimension * 0.75)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const notes = currentRelease;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, size: 16, color: t.secondary),
                tooltip: 'Close',
              ),
            ),
            Flexible(
              child: ShaderMask(
                // Soft fade at the bottom while there is more to read.
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    _atEnd ? Colors.white : Colors.transparent,
                  ],
                  stops: const [0, 0.85, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "What's New in Tasklet",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notes.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyles.bodySecondary(context)
                            .copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 26),
                      for (final f in notes.features)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 28,
                                child: Icon(f.icon, size: 20, color: t.accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: t.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      f.description,
                                      style: TextStyles.bodySecondary(context)
                                          .copyWith(height: 1.45),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (notes.fixes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Fixes and polish',
                          style: TextStyles.sectionLabel(context),
                        ),
                        const SizedBox(height: 6),
                        for (final fix in notes.fixes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check, size: 13, color: t.tertiary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    fix,
                                    style: TextStyles.meta(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Space for "More" is always reserved so the button never jumps.
            SizedBox(
              height: 28,
              child: _atEnd
                  ? null
                  : TextButton(onPressed: _more, child: const Text('More ↓')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 4, 40, 24),
              child: SizedBox(
                width: double.infinity,
                height: 34,
                child: FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
