import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Opens a file manager window with [path] selected (Explorer / Finder).
Future<void> revealInFileManager(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', p.normalize(path)]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    await launchUrl(Uri.file(p.dirname(path)));
  }
}

/// Opens [folder] itself in the file manager.
Future<void> openInFileManager(String folder) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [p.normalize(folder)]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [folder]);
  } else {
    await launchUrl(Uri.file(folder));
  }
}

/// Opens the OS notification settings for this app (SPEC §11.3).
Future<void> openNotificationSettings() async {
  if (Platform.isWindows) {
    await launchUrl(Uri.parse('ms-settings:notifications'));
  } else if (Platform.isMacOS) {
    await launchUrl(
      Uri.parse('x-apple.systempreferences:com.apple.preference.notifications'),
    );
  }
}

/// A short name for the cloud-sync provider whose folder contains [path], if any (Settings → Data "(Synced)").
String? cloudProviderFor(String path) {
  final lower = p.normalize(path).toLowerCase();
  final oneDrive =
      Platform.environment['OneDrive'] ??
      Platform.environment['OneDriveConsumer'];
  if (oneDrive != null &&
      lower.startsWith(p.normalize(oneDrive).toLowerCase())) {
    return 'OneDrive';
  }
  const markers = {
    'onedrive': 'OneDrive',
    'dropbox': 'Dropbox',
    'google drive': 'Google Drive',
    'googledrive': 'Google Drive',
    'my drive': 'Google Drive',
    'mobile documents': 'iCloud Drive',
    'icloud': 'iCloud Drive',
    'syncthing': 'Syncthing',
    'box sync': 'Box',
    'pcloud': 'pCloud',
  };
  for (final MapEntry(:key, :value) in markers.entries) {
    if (lower.contains(key)) return value;
  }
  return null;
}

/// The OS first day of week as an ISO weekday (1 = Monday … 7 = Sunday), or null when unknown.
int? osFirstDayOfWeek() {
  if (Platform.isWindows) {
    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKCU\Control Panel\International',
        '/v',
        'iFirstDayOfWeek',
      ]);
      final match = RegExp(r'iFirstDayOfWeek\s+REG_SZ\s+(\d)')
          .firstMatch('${result.stdout}');
      if (match != null) {
        return int.parse(match[1]!) + 1; // 0 = Monday … 6 = Sunday
      }
    } on ProcessException {
      return null;
    }
  }
  if (Platform.isMacOS) {
    try {
      final result = Process.runSync('defaults', [
        'read',
        '-g',
        'AppleFirstWeekday',
      ]);
      final match = RegExp(r'gregorian\s*=\s*(\d)')
          .firstMatch('${result.stdout}');
      if (match != null) {
        final appleDay = int.parse(match[1]!); // 1 = Sunday … 7 = Saturday
        return appleDay == 1 ? 7 : appleDay - 1;
      }
    } on ProcessException {
      return null;
    }
  }
  return null;
}
