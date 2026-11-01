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

  @override
  Future<void> onWindowClose() async {
    await windowManager.hide();
  }

  /// Really exits (tray "Quit Tasklet", or File → Exit).
  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    _tray?.setVisible(false);
    _tray?.dispose();
    await windowManager.destroy();
    exit(0);
  }
}
