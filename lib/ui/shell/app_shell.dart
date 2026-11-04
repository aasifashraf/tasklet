import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../platform/lifecycle.dart';
import '../../platform/native.dart';
import '../../state/clock.dart';
import '../../state/prefs.dart';
import '../../state/toast.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../startup.dart';
import '../board/bulk_bar.dart';
import '../task/detail_panel.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../platform/whats_new_notes.dart';
import '../whats_new.dart';
import 'app_menu.dart';
import 'sidebar.dart';

/// Chooses between onboarding, loading, error, and the main shell based on the workspace state.
class WorkspaceGate extends ConsumerWidget {
  const WorkspaceGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(workspaceProvider)) {
        NoFolderState() => const OnboardingPage(),
        LoadingState(:final folder) => LoadingView(folder: folder),
        final FailedState failed => LoadErrorView(state: failed),
        ReadyState() => AppShell(child: child),
      };
}

/// Two-pane layout: resizable sidebar + current page, with the detail panel and toast on top (SPEC §3.2).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WindowListener {
  double? _dragWidth;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    ref.listenManual(
      workspaceDataProvider.select((w) => w?.info.name),
      (_, name) => AppLifecycle.instance.showWorkspace(name),
      fireImmediately: true,
    );
    // Show release notes once after an update brings new ones (fresh installs just get the sidebar entry).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seen = ref.read(prefsProvider).whatsNewSeen;
      if (mounted && seen != null && seen != currentRelease.id) {
        showWhatsNew(context, ref);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Regaining focus: re-check the clock and re-read the folder (SPEC §9).
  @override
  void onWindowFocus() {
    ref.read(nowProvider.notifier).tick();
    ref.read(workspaceProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = ref.watch(prefsProvider);
    final width = _dragWidth ?? prefs.sidebarWidth;
    final openTask = ref.watch(openTaskProvider);
    // Settings → General → Show Release Notes (another window) asks for the sheet through this signal.
    ref.listen(
      releaseNotesRequestProvider,
      (_, _) => showWhatsNew(context, ref),
    );
    return AppMenu(
      child: Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                SizedBox(width: width, child: const Sidebar()),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => setState(
                      () => _dragWidth = ((_dragWidth ?? width) + d.delta.dx)
                          .clamp(190.0, 300.0),
                    ),
                    onHorizontalDragEnd: (_) {
                      ref
                          .read(prefsProvider.notifier)
                          .set(PrefKeys.sidebarWidth, _dragWidth);
                      setState(() => _dragWidth = null);
                    },
                    child: Container(
                      width: 5,
                      color: t.sidebar,
                      child: VerticalDivider(color: t.border, width: 5),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const _Notices(),
                      Expanded(child: widget.child),
                    ],
                  ),
                ),
              ],
            ),
            if (openTask != null) DetailPanelOverlay(taskRef: openTask),
            const BulkBar(),
            const ToastHost(),
          ],
        ),
      ),
    );
  }
}

/// Non-blocking workspace notices: sync conflicts, read-only folder, hidden entries, repairs (SPEC §2.5,
/// DECISIONS D1–D3, D12).
class _Notices extends ConsumerWidget {
  const _Notices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    final dismissed = ref.watch(dismissedNoticesProvider);
    if (ws == null) return const SizedBox.shrink();
    void dismiss(String key) =>
        ref.read(dismissedNoticesProvider.notifier).dismiss(key);
    return Column(
      children: [
        if (ws.readOnly)
          const NoticeBanner(
            icon: Icons.lock_outline,
            message:
                'This folder was saved by a newer version of Tasklet (or is still syncing), so it is read-only. '
                'Update Tasklet to make changes.',
          ),
        if (ws.hiddenEntryCount > 0 && !dismissed.contains('hidden'))
          NoticeBanner(
            icon: Icons.info_outline,
            message:
                '${ws.hiddenEntryCount} ${ws.hiddenEntryCount == 1 ? 'item was' : 'items were'} created by a newer '
                'version of Tasklet or edited by hand and can\'t be shown. They are kept safely in your files.',
            onDismiss: () => dismiss('hidden'),
          ),
        for (final c in ws.conflicts)
          if (!dismissed.contains('conflict:${c.file}'))
            NoticeBanner(
              icon: Icons.sync_problem_outlined,
              message: c.mainFileMissing
                  ? '"${c.projectName}" was found only as a sync copy. That copy is shown; your next change saves '
                        'a new main file and the copy is left at ${c.file}.'
                  : '"${c.projectName}" has a second copy from syncing. The main version is shown; the extra copy '
                        'was left at ${c.file}. Open the folder to compare.',
              actions: [
                TextButton(
                  onPressed: () => revealInFileManager(c.file),
                  child: const Text('Show in Folder'),
                ),
              ],
              onDismiss: () => dismiss('conflict:${c.file}'),
            ),
        for (final note in ref.watch(repairNotesProvider))
          NoticeBanner(
            icon: Icons.auto_fix_high_outlined,
            message:
                '$note Repaired after syncing; the previous version is in Restore Previous Version.',
            onDismiss: () =>
                ref.read(repairNotesProvider.notifier).dismiss(note),
          ),
      ],
    );
  }
}

/// Bottom-center toast with an optional Undo action (SPEC §7.3–7.4). Only one at a time.
class ToastHost extends ConsumerWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final t = Tokens.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: AnimatedSwitcher(
          duration: Motion.fast,
          child: toast == null
              ? const SizedBox.shrink()
              : Material(
                  key: ValueKey(toast.id),
                  color: t.primary,
                  elevation: 6,
                  shadowColor: t.shadow,
                  borderRadius: BorderRadius.circular(Radii.medium),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            toast.message,
                            style: TextStyles.body(context)
                                .copyWith(color: t.background),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (toast.onUndo != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: t.background,
                            ),
                            onPressed: () =>
                                ref.read(toastProvider.notifier).undo(),
                            child: const Text(
                              'Undo',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 14,
                          color: t.background,
                          tooltip: 'Dismiss',
                          onPressed: () =>
                              ref.read(toastProvider.notifier).dismiss(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
