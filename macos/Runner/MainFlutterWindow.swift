import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerNativeChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Native helpers used by lib/platform/ (channel "tasklet/native").
  private func registerNativeChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tasklet/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "trashItem":
        // Returns true when moved to the Trash, false when this volume has no Trash (e.g. network shares).
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "Expected a path", details: nil))
          return
        }
        do {
          try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
          result(true)
        } catch {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
