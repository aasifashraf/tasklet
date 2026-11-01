import 'package:flutter_driver/driver_extension.dart';
import 'package:tasklet/main.dart' as app;

/// Entry point with the flutter_driver extension enabled, for automated UI checks (tasklet-run skill).
///
/// Text entry emulation stays off so the real keyboard keeps working while someone uses the app; turn it on with
/// the driver's `set_text_entry_emulation` command before using `enter_text`.
Future<void> main(List<String> args) async {
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  await app.main(args);
}
