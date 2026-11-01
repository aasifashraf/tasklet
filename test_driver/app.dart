import 'package:flutter_driver/driver_extension.dart';
import 'package:tasklet/main.dart' as app;

/// Entry point with the flutter_driver extension enabled, for automated UI checks (tasklet-run skill).
Future<void> main(List<String> args) async {
  enableFlutterDriverExtension();
  await app.main(args);
}
