import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../core/colors.dart';
import '../core/models.dart';
import '../core/org_bundle.dart';
import '../core/organization.dart';
import '../data/workspace_store.dart';
import '../platform/windows.dart';
import '../state/prefs.dart';
import '../state/toast.dart';
import '../state/workspace.dart';
import 'glyphs.dart';
import 'icon_picker.dart';
import 'theme.dart';
import 'widgets.dart';

// Organizations (docs/DECISIONS.md D15): one data folder each, switched from the sidebar header or the
// Organization menu. These flows are shared by both and by onboarding.

/// Ctrl+Alt+1…9 (⌘⌥ on macOS) open the first nine organizations; Ctrl+1…7 already go to the nav pages.
SingleActivator? organizationShortcut(int index) {
  if (index > 8) return null;
  final key = LogicalKeyboardKey.findKeyByKeyId(
    LogicalKeyboardKey.digit1.keyId + index,
  )!;
  return SingleActivator(
    key,
    control: !Platform.isMacOS,
    meta: Platform.isMacOS,
    alt: true,
  );
}

/// The organization's glyph: its icon (default: a building) or the cube, in its color.
class OrgGlyph extends StatelessWidget {
  const OrgGlyph(this.info, {super.key, this.size = 14});
  final OrgInfo info;
  final double size;

  @override
  Widget build(BuildContext context) => TaskletIcon(
    icon: info.icon,
    color: Tokens.of(context).named(info.color),
    size: size,
    fallback: CubeIcon.new,
  );
}

/// Opens [folder]'s organization. A project or quick-filter page belongs to the old one, so it goes to the
/// Dashboard; other pages (Today, All Tasks…) stay.
Future<void> switchToOrganization(
  BuildContext context,
  WidgetRef ref,
  String folder,
) async {
  final router = GoRouter.of(context);
  final path = router.state.uri.path;
  await ref.read(workspaceProvider.notifier).switchOrganization(folder);
  if (path.startsWith('/projects/') || path.startsWith('/views/')) {
    router.go(NavItem.dashboard.route);
  }
}

/// New Organization…: asks for a name, icon and where to create its folder, then creates and opens it.
Future<void> newOrganization(BuildContext context, WidgetRef ref) async {
  final current = ref.read(workspaceDataProvider)?.folder;
  final created = await showNewOrganizationDialog(
    context,
    parent: current == null ? null : p.dirname(current),
  );
  if (created == null) return;
  await _add(ref, created.folder, created.info);
}

/// The New Organization dialog: creates the (empty) folder and returns it with the identity to give it; null if
/// cancelled. [parent] is the suggested location (next to the open organization's folder). [imported] prefills it
/// from an export and turns it into the Import Organization dialog.
Future<({String folder, OrgInfo info})?> showNewOrganizationDialog(
  BuildContext context, {
  String? parent,
  OrgBundle? imported,
}) => showDialog<({String folder, OrgInfo info})>(
  context: context,
  builder: (_) => _NewOrganizationDialog(parent: parent, imported: imported),
);

/// Open Existing Folder…: adds a folder (a Tasklet folder from another computer, or any folder) as an
/// organization and opens it.
Future<void> openExistingOrganization(WidgetRef ref) async {
  final folder = await FilePicker.getDirectoryPath(
    dialogTitle: 'Choose an organization folder',
  );
  if (folder != null) await _add(ref, folder, null);
}

Future<void> _add(WidgetRef ref, String folder, OrgInfo? identity) async {
  try {
    await ref
        .read(workspaceProvider.notifier)
        .addOrganization(folder, identity: identity);
  } on WorkspaceFolderMissing {
    ref.read(toastProvider.notifier).show("Can't find that folder.");
  } on FileSystemException catch (e) {
    ref
        .read(toastProvider.notifier)
        .show("Tasklet can't use that folder: ${e.message}");
  }
}

/// Edit Organization…: renames or re-icons [entry].
Future<void> editOrganization(
  BuildContext context,
  WidgetRef ref,
  OrgEntry entry,
) async {
  final info = await showEditOrganizationDialog(context, entry.info);
  if (info == null || info == entry.info) return;
  await ref
      .read(workspaceProvider.notifier)
      .updateOrganization(entry.folder, info);
}

/// "Move to Organization ▸" for a project's menus: every other organization on this computer; null when there is
/// none. Moving goes to the Dashboard if the project's own page is open.
Widget? moveToOrganizationMenu(
  BuildContext context,
  WidgetRef ref,
  Project project,
) {
  final ws = ref.read(workspaceDataProvider);
  final others = [
    for (final o in ref.read(prefsProvider).organizations)
      if (ws != null && !sameFolder(o.folder, ws.folder)) o,
  ];
  if (others.isEmpty) return null;
  return SubmenuButton(
    menuChildren: [
      for (final o in others)
        menuItem(
          o.info.name,
          leading: OrgGlyph(o.info, size: 13),
          onPressed: () async {
            final router = GoRouter.of(context);
            final onPage = router.state.uri.path == '/projects/${project.id}';
            final error = await ref
                .read(workspaceProvider.notifier)
                .moveProjectToOrganization(project.id, o.folder);
            if (error != null) {
              ref
                  .read(toastProvider.notifier)
                  .show(error, duration: const Duration(seconds: 8));
              return;
            }
            if (onPage) router.go(NavItem.dashboard.route);
            ref
                .read(toastProvider.notifier)
                .show('Moved "${project.name}" to ${o.info.name}.');
          },
        ),
    ],
    child: const Text('Move to Organization', style: TextStyle(fontSize: 12)),
  );
}

/// Asks for a new name, icon and color for [initial]; null if cancelled.
Future<OrgInfo?> showEditOrganizationDialog(
  BuildContext context,
  OrgInfo initial,
) => showDialog<OrgInfo>(
  context: context,
  builder: (_) => _OrganizationDialog(
    title: 'Edit Organization',
    action: 'Save',
    initial: initial,
  ),
);

/// The sidebar header: the open organization, and a menu to switch, add or edit organizations.
class OrganizationSwitcher extends ConsumerWidget {
  const OrganizationSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final ws = ref.watch(workspaceDataProvider);
    final orgs = ref.watch(prefsProvider.select((p) => p.organizations));
    final open = ws == null
        ? null
        : orgs.where((o) => sameFolder(o.folder, ws.folder)).firstOrNull;
    final info = ws?.organization ?? open?.info;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final (i, o) in orgs.indexed)
          MenuItemButton(
            leadingIcon: SizedBox(width: 16, child: OrgGlyph(o.info, size: 13)),
            trailingIcon: SizedBox(
              width: 16,
              child: open != null && sameFolder(o.folder, open.folder)
                  ? Icon(Icons.check, size: 14, color: t.primary)
                  : null,
            ),
            shortcut: organizationShortcut(i),
            onPressed: () => switchToOrganization(context, ref, o.folder),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                o.info.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        const Divider(),
        menuItem(
          'New Organization…',
          onPressed: () => newOrganization(context, ref),
        ),
        menuItem(
          'Open Existing Folder…',
          onPressed: () => openExistingOrganization(ref),
        ),
        if (open != null && ws != null)
          menuItem(
            'Edit Organization…',
            onPressed: ws.readOnly
                ? null
                : () => editOrganization(context, ref, (
                    folder: open.folder,
                    info: ws.organization,
                  )),
          ),
        const Divider(),
        menuItem(
          'Export Organization…',
          onPressed: ws == null ? null : () => exportOrganization(ref),
        ),
        menuItem(
          'Import Organization…',
          onPressed: () => importOrganization(context, ref),
        ),
        menuItem('Manage Organizations…', onPressed: openSettingsWindow),
      ],
      builder: (context, controller, _) => Hoverable(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: hovered || controller.isOpen ? t.hover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                if (info != null) ...[
                  OrgGlyph(info, size: 15),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    info?.name ?? 'Tasklet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.section(context),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 15, color: t.tertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Name, icon and color of an organization.
class _OrganizationDialog extends StatefulWidget {
  const _OrganizationDialog({
    required this.title,
    required this.action,
    required this.initial,
  });
  final String title;
  final String action;
  final OrgInfo initial;

  @override
  State<_OrganizationDialog> createState() => _OrganizationDialogState();
}

class _OrganizationDialogState extends State<_OrganizationDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late String? _icon = widget.initial.icon;
  late TaskletColor _color = widget.initial.color;

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, OrgInfo(name: name, icon: _icon, color: _color));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, style: TextStyles.section(context)),
    content: SizedBox(
      width: 360,
      child: _NameRow(
        name: _name,
        icon: _icon,
        color: _color,
        onPick: (icon, color) => setState(() {
          _icon = icon;
          _color = color;
        }),
        onSubmitted: _submit,
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// New Organization: identity plus where its folder goes. The folder is named after the organization and must
/// not exist yet (an existing folder is added with Open Existing Folder… instead).
class _NewOrganizationDialog extends StatefulWidget {
  const _NewOrganizationDialog({required this.parent, this.imported});
  final String? parent;
  final OrgBundle? imported;

  @override
  State<_NewOrganizationDialog> createState() => _NewOrganizationDialogState();
}

class _NewOrganizationDialogState extends State<_NewOrganizationDialog> {
  late final _name = TextEditingController(
    text: widget.imported?.organization.name,
  );
  late String? _icon = widget.imported == null
      ? OrgInfo.defaultIcon
      : widget.imported!.organization.icon;
  late TaskletColor _color =
      widget.imported?.organization.color ??
      TaskletColor.rotation[Random().nextInt(TaskletColor.rotation.length)];
  late String? _parent = widget.parent;
  String? _error;
  bool _creating = false;

  static final _invalid = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  String get _folderName => _name.text.trim();

  Future<void> _chooseParent() async {
    final parent = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where to create the organization folder',
    );
    if (parent != null) setState(() => _parent = parent);
  }

  Future<void> _submit() async {
    final name = _folderName;
    final parent = _parent;
    if (name.isEmpty) {
      setState(() => _error = 'Give the organization a name.');
      return;
    }
    if (_invalid.hasMatch(name) || name.endsWith('.')) {
      setState(() => _error = 'Use a name without < > : " / \\ | ? *');
      return;
    }
    if (parent == null) {
      setState(() => _error = 'Choose where to create its folder.');
      return;
    }
    final folder = p.join(parent, name);
    if (FileSystemEntity.typeSync(folder) != FileSystemEntityType.notFound) {
      setState(
        () => _error =
            'A folder named "$name" already exists there. To use it, choose Open Existing Folder… instead.',
      );
      return;
    }
    setState(() => _creating = true);
    try {
      await Directory(folder).create();
    } on FileSystemException catch (e) {
      setState(() {
        _creating = false;
        _error = "Couldn't create the folder: ${e.message}";
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, (
      folder: folder,
      info: OrgInfo(name: name, icon: _icon, color: _color),
    ));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final parent = _parent;
    final imported = widget.imported;
    return AlertDialog(
      title: Text(
        imported == null ? 'New Organization' : 'Import Organization',
        style: TextStyles.section(context),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              imported == null
                  ? 'Each organization keeps its own projects, labels and quick filters in its own folder. Put it '
                        'in the cloud folder you use for that work (OneDrive, Dropbox, Google Drive or iCloud '
                        'Drive) to sync it.'
                  : 'The export has ${_count(imported.projects.length, 'project')} with '
                        '${_count(imported.taskCount, 'task')}. They go into a new folder, with its labels and '
                        'quick filters.',
              style: TextStyles.bodySecondary(context),
            ),
            const SizedBox(height: 14),
            _NameRow(
              name: _name,
              icon: _icon,
              color: _color,
              hint: 'Acme Corp, Freelance, Open Source',
              onPick: (icon, color) => setState(() {
                _icon = icon;
                _color = color;
              }),
              onChanged: () => setState(() => _error = null),
              onSubmitted: _submit,
            ),
            const SizedBox(height: 14),
            Text('Folder', style: TextStyles.meta(context)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    parent == null
                        ? 'Not chosen'
                        : p.join(
                            parent,
                            _folderName.isEmpty ? '…' : _folderName,
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body(context)
                        .copyWith(color: parent == null ? t.tertiary : null),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _creating ? null : _chooseParent,
                  child: const Text('Choose…'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyles.body(context).copyWith(color: t.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : _submit,
          child: Text(
            _creating
                ? (imported == null ? 'Creating…' : 'Importing…')
                : (imported == null ? 'Create' : 'Import'),
          ),
        ),
      ],
    );
  }
}

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// Export Organization…: saves the open organization as one file (docs/DECISIONS.md D15).
Future<void> exportOrganization(WidgetRef ref) async {
  final toast = ref.read(toastProvider.notifier);
  final OrgBundle bundle;
  try {
    bundle = await ref.read(workspaceProvider.notifier).exportOrganization();
  } on UnsafeWriteException catch (e) {
    toast.show(e.message, duration: const Duration(seconds: 8));
    return;
  }
  final json = bundle.toJson();
  final bytes = await Isolate.run(
    () => utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
  );
  final name = bundle.organization.name.replaceAll(_unsafeFileChars, '-');
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Export organization',
    fileName: '$name${OrgBundle.fileExtension}',
    bytes: bytes,
  );
  if (uri == null) return;
  toast.show(
    'Exported ${bundle.organization.name}: ${_count(bundle.projects.length, 'project')}, '
    '${_count(bundle.taskCount, 'task')}.',
  );
}

final _unsafeFileChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Imports are read whole; larger files are refused rather than exhausting memory.
const _maxImportBytes = 512 * 1024 * 1024;

/// Import Organization…: makes a new organization from an export, in a new folder.
Future<void> importOrganization(BuildContext context, WidgetRef ref) async {
  final toast = ref.read(toastProvider.notifier);
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Import organization',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  final path = picked.singleOrNull?.path;
  if (path == null) return;
  final OrgBundle bundle;
  try {
    if (await File(path).length() > _maxImportBytes) {
      throw const FormatException('This file is too large to import.');
    }
    bundle = await Isolate.run(() async {
      final Object? json;
      try {
        json = jsonDecode(await File(path).readAsString());
      } on FormatException {
        throw const FormatException("This file isn't a Tasklet export.");
      }
      return OrgBundle.fromJson(json, isSafeId: WorkspaceStore.isSafeProjectId);
    });
  } on FormatException catch (e) {
    toast.show(e.message, duration: const Duration(seconds: 8));
    return;
  } on FileSystemException catch (e) {
    toast.show("Couldn't read that file: ${e.message}");
    return;
  }
  if (!context.mounted) return;
  final current = ref.read(workspaceDataProvider)?.folder;
  final created = await showNewOrganizationDialog(
    context,
    parent: current == null ? null : p.dirname(current),
    imported: bundle,
  );
  if (created == null) return;
  try {
    await WorkspaceStore.importBundle(created.folder, bundle, created.info);
  } on Exception catch (e) {
    toast.show(
      e is UnsafeWriteException
          ? e.message
          : e is FileSystemException
          ? "Couldn't write the organization: ${e.message}"
          : "Couldn't import: $e",
      duration: const Duration(seconds: 8),
    );
    try {
      await Directory(created.folder)
          .delete(); // still empty: created for this import
    } on FileSystemException {
      // Leave it; it's empty either way.
    }
    return;
  }
  await _add(ref, created.folder, null);
  toast.show(
    'Imported ${created.info.name}: ${_count(bundle.projects.length, 'project')}, '
    '${_count(bundle.taskCount, 'task')}.',
  );
}

/// The icon (opens the icon picker) next to the name field.
class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.name,
    required this.icon,
    required this.color,
    required this.onPick,
    required this.onSubmitted,
    this.onChanged,
    this.hint,
  });
  final TextEditingController name;
  final String? icon;
  final TaskletColor color;
  final void Function(String? icon, TaskletColor color) onPick;
  final VoidCallback onSubmitted;
  final VoidCallback? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconPickerButton(
        icon: icon,
        color: color,
        kind: GlyphKind.project,
        size: 18,
        onPick: onPick,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: TextField(
          controller: name,
          autofocus: true,
          maxLength: OrgInfo.maxNameLength,
          style: TextStyles.body(context),
          onChanged: (_) => onChanged?.call(),
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
      ),
    ],
  );
}
