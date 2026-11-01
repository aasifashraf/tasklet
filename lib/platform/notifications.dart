import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local OS notifications (Windows toast / macOS Notification Center) with click routing (SPEC §11.3).
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nextId = 1;

  static const _windowsGuid = '6f1c2b0e-3c1d-4d6b-9a52-7e0d3c9b1a41';

  /// Initializes the plugin. [onTap] receives the payload of a clicked notification — also when the click
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
        appUserModelId: 'Tasklet.Tasklet.Desktop',
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

  /// Whether the OS currently allows our notifications; null when the platform can't tell us (Windows).
  static Future<bool?> allowed() async {
    if (!_ready || !Platform.isMacOS) return null;
    final status = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return status?.isEnabled;
  }
}
