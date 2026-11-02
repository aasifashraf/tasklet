import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'windows.dart';

/// Keeps Tasklet running when its window is closed so daily reminders still fire (SPEC §11.3, §15):
/// closing hides the window; on Windows a tray icon brings it back or quits, on macOS the Dock icon does.
class AppLifecycle with WindowListener {
  AppLifecycle._();
  static final instance = AppLifecycle._();

  TrayIcon? _tray;

  Future<void> init() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    if (Platform.isWindows) _initTray();
  }

  void _initTray() {
    final tray = TrayIcon.create();
    if (tray == null) return;
    _tray = tray
      ..icon = ImageAsset.fromAsset('assets/tray_icon.ico')
      ..setTooltip('Tasklet');

    MenuItem? item(String label, void Function() onClick) {
      final m = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
      m?.addListener((e) {
        if (e is MenuItemClickedEvent) onClick();
      });
      return m;
    }

    final menu = Menu.create();
    if (menu != null) {
      menu
        ..addItem(item('Open Tasklet', bringMainWindowToFront))
        ..addSeparator()
        ..addItem(item('Quit Tasklet', quit));
      tray
        ..setContextMenu(menu)
        ..setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    }
    tray
      ..addListener((e) {
        if (e is TrayIconClickedEvent) bringMainWindowToFront();
      })
      ..setVisible(true);
  }

  /// Names the open organization in the window title and tray tooltip ("Acme Corp - Tasklet").
  Future<void> showOrganization(String? name) async {
    final title = name == null ? 'Tasklet' : '$name - Tasklet';
    _tray?.setTooltip(title);
    try {
      await windowManager.setTitle(title);
    } catch (_) {
      // No window manager (tests): the title is cosmetic.
    }
  }

  @override
  Future<void> onWindowClose() async {
    await windowManager.hide();
  }

  /// Run in order before exiting (flush the open task panel, then wait for saves). Bounded so Quit always works.
  final beforeQuit = <Future<void> Function()>[];

  /// Really exits (tray "Quit Tasklet", or File → Exit).
  Future<void> quit() async {
    try {
      await Future(() async {
        for (final hook in [...beforeQuit]) {
          await hook();
        }
      }).timeout(const Duration(seconds: 4));
    } catch (_) {
      // A stuck save (locked file, offline drive) must not block quitting; the atomic write keeps files intact.
    }
    await windowManager.setPreventClose(false);
    _tray?.setVisible(false);
    _tray?.dispose();
    await windowManager.destroy();
    exit(0);
  }
}
