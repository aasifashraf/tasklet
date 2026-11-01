#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Closing Tasklet only hides it to the tray (so reminders keep firing), which makes "start it again" common. Keep a
// single instance: a second launch brings the running window back instead of adding another copy, tray icon and set
// of reminders. Skipped in debug builds so a development copy never blocks an installed one.
bool ActivateRunningInstance() {
#ifdef _DEBUG
  return false;
#else
  ::CreateMutexW(nullptr, TRUE, L"Local\\Tasklet.SingleInstance");
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Tasklet");
  if (existing) {
    ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(existing);
  }
  return true;
#endif
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (ActivateRunningInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 820);
  if (!window.Create(L"Tasklet", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
