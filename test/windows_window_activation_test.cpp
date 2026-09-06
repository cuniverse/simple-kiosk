// Native smoke test: compile with MSVC and link user32.lib.
// Creates only its own temporary windows; no installed signage is required.
#include "../windows/runner/window_activation.h"

#include <iostream>

int main() {
  const HINSTANCE instance = ::GetModuleHandleW(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = ::DefWindowProcW;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"SignageActivationTest";
  if (!::RegisterClassW(&window_class)) return 1;
  const HWND target = ::CreateWindowExW(
      0, window_class.lpszClassName, L"Signage activation test", WS_OVERLAPPEDWINDOW,
      100, 100, 300, 200, nullptr, nullptr, instance, nullptr);
  const HWND content = ::CreateWindowExW(
      0, L"STATIC", L"Content", WS_CHILD | WS_VISIBLE,
      0, 0, 200, 100, target, nullptr, instance, nullptr);
  const HWND covering = ::CreateWindowExW(
      0, window_class.lpszClassName, L"Covering test window", WS_OVERLAPPEDWINDOW,
      100, 100, 300, 200, nullptr, nullptr, instance, nullptr);
  bool passed = target && content && covering;
  if (passed) {
    for (const int state : {SW_HIDE, SW_MINIMIZE, SW_SHOW}) {
      for (const bool topmost : {false, true}) {
        ::SetWindowPos(target, topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        ::ShowWindow(target, state);
        ::ShowWindow(covering, SW_SHOW);
        ::SetForegroundWindow(covering);
        const bool activated = ActivateSignageWindow(target, content);
        const bool keeps_topmost =
            ((::GetWindowLongPtrW(target, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0) ==
            topmost;
        const bool valid = activated && ::IsWindowVisible(target) &&
            !::IsIconic(target) && ::GetForegroundWindow() == target &&
            ::GetFocus() == content && keeps_topmost;
        std::cout << "state=" << state << " topmost=" << topmost
                  << " passed=" << valid << '\n';
        passed = passed && valid;
      }
    }
    passed = passed && !ActivateSignageWindow(nullptr, content);
  }
  if (covering) ::DestroyWindow(covering);
  if (target) ::DestroyWindow(target);
  ::UnregisterClassW(window_class.lpszClassName, instance);
  return passed ? 0 : 1;
}
