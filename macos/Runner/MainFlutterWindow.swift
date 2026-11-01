import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerNativeChannel(messenger: flutterViewController.engine.binaryMessenger)
    // Each extra window has its own engine; register plugins there too. The only extra window is Settings:
    // a fixed 520x440 window (SPEC §11).
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      DispatchQueue.main.async {
        guard let window = controller.view.window else { return }
        window.styleMask.remove(.resizable)
        window.styleMask.remove(.miniaturizable)
        window.setContentSize(NSSize(width: 520, height: 440))
        window.title = "Tasklet Settings"
        window.center()
      }
    }

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
