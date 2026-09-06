#ifndef RUNNER_WINDOW_ACTIVATION_H_
#define RUNNER_WINDOW_ACTIVATION_H_

#include <windows.h>

// Called on the window's platform thread only for an explicit Show action.
inline bool ActivateSignageWindow(HWND window, HWND content) {
  if (!::IsWindow(window) ||
      ::GetWindowThreadProcessId(window, nullptr) != ::GetCurrentThreadId()) {
    return false;
  }
  ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
  ::SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  ::SetForegroundWindow(window);

  if (::GetForegroundWindow() != window) {
    // A remote admin request is not a local input event. Temporarily share
    // the foreground input queue to activate our window, then always detach.
    const HWND foreground = ::GetForegroundWindow();
    const DWORD foreground_thread =
        ::GetWindowThreadProcessId(foreground, nullptr);
    const DWORD current_thread = ::GetCurrentThreadId();
    if (foreground_thread != 0 && foreground_thread != current_thread &&
        ::AttachThreadInput(current_thread, foreground_thread, TRUE)) {
      ::BringWindowToTop(window);
      ::SetForegroundWindow(window);
      ::AttachThreadInput(current_thread, foreground_thread, FALSE);
    }
  }

  if (::GetForegroundWindow() != window) return false;
  ::SetActiveWindow(window);
  // Flutter owns the keyboard dispatch; focus its child HWND after restoring
  // the rendering surface and WebViews, which may otherwise steal focus back.
  const HWND focus = ::IsChild(window, content) ? content : window;
  ::SetFocus(focus);
  return ::GetForegroundWindow() == window && ::GetFocus() == focus;
}

#endif  // RUNNER_WINDOW_ACTIVATION_H_
