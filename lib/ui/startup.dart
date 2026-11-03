import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/native.dart';
import '../state/workspace.dart';
import 'workspaces.dart';
import 'theme.dart';

/// Native folder picker for an existing folder. Returns null if cancelled.
Future<String?> pickExistingFolder() => FilePicker.getDirectoryPath(
  dialogTitle: 'Choose a folder for your Tasklet data',
);

/// First launch / no folder chosen (SPEC §10).
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  String? _busy; // 'open' | 'create'
  String? _error;

  Future<void> _run(String kind, Future<String?> Function() pick) async {
    setState(() {
      _busy = kind;
      _error = null;
    });
    try {
      final folder = await pick();
      if (folder != null) {
        await ref.read(workspaceProvider.notifier).chooseFolder(folder);
      }
    } on FileSystemException catch (e) {
      // E.g. no permission to create a folder there, or the name already exists as a file.
      if (mounted) {
        setState(() => _error = "Couldn't use that folder: ${e.message}.");
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't use that folder: $e");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/branding/tasklet-icon-256.png',
                width: 64,
                height: 64,
              ),
              const SizedBox(height: 20),
              Text('Welcome to Tasklet', style: TextStyles.display(context)),
              const SizedBox(height: 10),
              Text(
                'Tasklet keeps your tasks as plain files in a folder you choose. No account, no server. '
                'Pick a folder inside OneDrive, Dropbox, Google Drive or iCloud Drive and your tasks will sync '
                'across your computers. Each folder is a workspace; add more later (work, freelance, '
                'open source) and switch between them at the top of the sidebar.',
                textAlign: TextAlign.center,
                style: TextStyles.bodyLarge(context)
                    .copyWith(color: t.secondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 240,
                child: FilledButton(
                  onPressed: _busy == null
                      ? () => _run('open', pickExistingFolder)
                      : null,
                  child: Text(
                    _busy == 'open' ? 'Opening…' : 'Choose Existing Folder…',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 240,
                child: OutlinedButton(
                  onPressed: _busy == null
                      ? () => _run('create', () async {
                          final created = await showNewWorkspaceDialog(context);
                          if (created != null) {
                            await ref
                                .read(workspaceProvider.notifier)
                                .addWorkspace(
                                  created.folder,
                                  identity: created.info,
                                );
                          }
                          return null; // already opened
                        })
                      : null,
                  child: Text(
                    _busy == 'create' ? 'Creating…' : 'Create Workspace…',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyles.body(context).copyWith(color: t.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the folder is read; the spinner appears only after 300ms to avoid a flash (SPEC §8.7).
class LoadingView extends StatefulWidget {
  const LoadingView({super.key, required this.folder});
  final String folder;

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> {
  bool _visible = false;
  late final Timer _timer = Timer(
    const Duration(milliseconds: 300),
    () => setState(() => _visible = true),
  );

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = cloudProviderFor(widget.folder);
    return Scaffold(
      body: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Opening your workspace…',
                style: TextStyles.section(context),
              ),
              const SizedBox(height: 6),
              Text(
                cloud == null
                    ? 'Reading your projects.'
                    : 'Reading your projects from $cloud. This can take a moment while files download.',
                style: TextStyles.bodySecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A load error (missing folder, permission denied…) with a way out (SPEC §2.5, §8.7).
class LoadErrorView extends ConsumerWidget {
  const LoadErrorView({super.key, required this.state});
  final FailedState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 32, color: t.tertiary),
              const SizedBox(height: 14),
              Text(
                state.message,
                style: TextStyles.section(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                state.missing
                    ? 'Tasklet was using ${state.folder}, but it isn\'t there anymore. It may have been moved, '
                          'renamed, or be on a drive or cloud folder that isn\'t available right now. '
                          'Nothing has been deleted.'
                    : state.folder,
                style: TextStyles.bodySecondary(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(workspaceProvider.notifier).retry(),
                    child: const Text('Try Again'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final folder = await pickExistingFolder();
                      if (folder != null) {
                        await ref
                            .read(workspaceProvider.notifier)
                            .chooseFolder(folder);
                      }
                    },
                    child: const Text('Choose Folder…'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
