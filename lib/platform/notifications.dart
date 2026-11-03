import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:win32/win32.dart' as win32;

/// Local OS notifications (Windows toast / macOS Notification Center) with click routing (SPEC §11.3).
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nextId = 1;

  static const _windowsGuid = '6f1c2b0e-3c1d-4d6b-9a52-7e0d3c9b1a41';
  static const _windowsAppId = 'Tasklet.Tasklet.Desktop';

  /// Initializes the plugin. [onTap] receives the payload of a clicked notification, also when the click
  /// launched the app.
  static Future<void> init(void Function(String? payload) onTap) async {
    if (_ready || !(Platform.isWindows || Platform.isMacOS)) return;
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'Tasklet',
        appUserModelId: _windowsAppId,
        guid: _windowsGuid,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      onTap(launch!.notificationResponse?.payload);
    }
  }

  /// Shows a notification; also triggers the OS's first-time permission prompt on macOS.
  static Future<void> show(
    String title,
    String? body, {
    String? payload,
  }) async {
    if (!_ready) return;
    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
    }
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// Whether the OS currently allows our notifications; null when it can't tell.
  static Future<bool?> allowed() async {
    if (!_ready) return null;
    if (Platform.isWindows) return _windowsAllowed();
    if (!Platform.isMacOS) return null;
    final status = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return status?.isEnabled;
  }

  /// Windows keeps the two switches of Settings > System > Notifications in the user's registry: all notifications
  /// (`ToastEnabled`) and Tasklet's own (`Enabled` under its app id). 0 means off; a missing value means the
  /// default, on. Do Not Disturb isn't readable this way, so the Settings window still mentions it.
  static bool _windowsAllowed() {
    const base = r'Software\Microsoft\Windows\CurrentVersion';
    final all = _userDword('$base\\PushNotifications', 'ToastEnabled');
    final app = _userDword(
      '$base\\Notifications\\Settings\\$_windowsAppId',
      'Enabled',
    );
    return all != 0 && app != 0;
  }

  /// A DWORD under HKEY_CURRENT_USER, or null when it doesn't exist.
  static int? _userDword(String key, String value) => using((arena) {
    final data = arena<Uint32>();
    final size = arena<Uint32>()..value = sizeOf<Uint32>();
    final result = win32.RegGetValue(
      win32.HKEY_CURRENT_USER,
      arena.pcwstr(key),
      arena.pcwstr(value),
      win32.RRF_RT_REG_DWORD,
      null,
      data.cast(),
      size,
    );
    return result == win32.ERROR_SUCCESS ? data.value : null;
  });
}
