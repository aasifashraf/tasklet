import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keep running after the main window closes so daily reminders still fire (SPEC §11.3).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Clicking the Dock icon brings the main window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
