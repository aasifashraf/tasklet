#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

// Tasklet's only secondary window is Settings: a fixed 520x440 window (SPEC §11).
void ConfigureSettingsWindow(flutter::FlutterViewController* controller) {
  HWND root = ::GetAncestor(controller->view()->GetNativeWindow(), GA_ROOT);
  if (!root) return;
  LONG style = ::GetWindowLong(root, GWL_STYLE);
  style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX);
  ::SetWindowLong(root, GWL_STYLE, style);
  const UINT dpi = ::GetDpiForWindow(root);
  RECT rect{0, 0, ::MulDiv(520, dpi, 96), ::MulDiv(440, dpi, 96)};
  ::AdjustWindowRectExForDpi(&rect, style, FALSE,
                             ::GetWindowLong(root, GWL_EXSTYLE), dpi);
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  MONITORINFO info{sizeof(MONITORINFO)};
  ::GetMonitorInfo(::MonitorFromWindow(root, MONITOR_DEFAULTTONEAREST), &info);
  const int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
  const int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2;
  ::SetWindowPos(root, nullptr, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ::SetWindowText(root, L"Tasklet Settings");
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Each extra window has its own engine; register plugins there too.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
    ConfigureSettingsWindow(view_controller);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
