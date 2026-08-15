#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kShowVersionMessage = WM_APP + 1;
constexpr UINT kCheckUpdateMessage = WM_APP + 2;
constexpr UINT kShowManualMessage = WM_APP + 3;
HWND g_kiosk_window = nullptr;

LRESULT CALLBACK KioskKeyboardHook(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION &&
      (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN) &&
      g_kiosk_window != nullptr) {
    const auto* event = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    const HWND foreground = ::GetAncestor(::GetForegroundWindow(), GA_ROOT);
    if (foreground == g_kiosk_window) {
      if (event->vkCode == VK_F1) {
        ::PostMessage(g_kiosk_window, kShowManualMessage, 0, 0);
        return 1;
      }
      if (event->vkCode == VK_F12) {
        ::PostMessage(g_kiosk_window, kShowVersionMessage, 0, 0);
        return 1;
      }
      if (event->vkCode == VK_F9) {
        ::PostMessage(g_kiosk_window, kCheckUpdateMessage, 0, 0);
        return 1;
      }
    }
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
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
  shortcut_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_kiosk/shortcuts",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  g_kiosk_window = GetHandle();
  keyboard_hook_ = ::SetWindowsHookEx(WH_KEYBOARD_LL, KioskKeyboardHook,
                                      ::GetModuleHandle(nullptr), 0);

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
  if (keyboard_hook_ != nullptr) {
    ::UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  g_kiosk_window = nullptr;
  shortcut_channel_.reset();
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
    case kShowManualMessage:
      if (shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "showManual",
            std::make_unique<flutter::EncodableValue>());
      }
      return 0;
    case kShowVersionMessage:
      if (shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "showVersion",
            std::make_unique<flutter::EncodableValue>());
      }
      return 0;
    case kCheckUpdateMessage:
      if (shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "checkUpdate",
            std::make_unique<flutter::EncodableValue>());
      }
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
