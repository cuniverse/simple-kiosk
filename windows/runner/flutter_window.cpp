#include "flutter_window.h"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include <shlobj.h>
#include <shobjidl.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kShowVersionMessage = WM_APP + 1;
constexpr UINT kCheckUpdateMessage = WM_APP + 2;
constexpr UINT kShowManualMessage = WM_APP + 3;
HWND g_kiosk_window = nullptr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = ::WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(length, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), length,
                        nullptr, nullptr);
  return result;
}

std::wstring MethodStringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) return {};
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) return {};
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? std::wstring() : Utf8ToWide(*value);
}

std::filesystem::path StartupFolder() {
  PWSTR raw_path = nullptr;
  const HRESULT result =
      ::SHGetKnownFolderPath(FOLDERID_Startup, KF_FLAG_CREATE, nullptr,
                             &raw_path);
  if (FAILED(result) || raw_path == nullptr) return {};
  const std::filesystem::path path(raw_path);
  ::CoTaskMemFree(raw_path);
  return path;
}

std::vector<std::filesystem::path> StartupShortcutPaths() {
  const auto folder = StartupFolder();
  if (folder.empty()) return {};
  return {
      folder / L"여의도성당Signage.lnk",
      folder / L"Simple Kiosk.lnk",
      folder / L"SimpleKiosk.lnk",
  };
}

bool LoadShortcut(const std::filesystem::path& path, std::wstring* target,
                  std::wstring* arguments) {
  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return false;
  }
  IPersistFile* persist = nullptr;
  HRESULT result = link->QueryInterface(IID_PPV_ARGS(&persist));
  if (SUCCEEDED(result)) result = persist->Load(path.c_str(), STGM_READ);
  if (SUCCEEDED(result)) {
    wchar_t target_buffer[32768]{};
    wchar_t argument_buffer[32768]{};
    result = link->GetPath(target_buffer, 32768, nullptr, SLGP_RAWPATH);
    if (SUCCEEDED(result)) {
      result = link->GetArguments(argument_buffer, 32768);
    }
    if (SUCCEEDED(result)) {
      *target = target_buffer;
      *arguments = argument_buffer;
    }
  }
  if (persist != nullptr) persist->Release();
  link->Release();
  return SUCCEEDED(result);
}

bool SamePath(const std::wstring& left, const std::wstring& right) {
  if (left.empty() || right.empty()) return false;
  const auto normalized_left =
      std::filesystem::absolute(left).lexically_normal().wstring();
  const auto normalized_right =
      std::filesystem::absolute(right).lexically_normal().wstring();
  return ::_wcsicmp(normalized_left.c_str(), normalized_right.c_str()) == 0;
}

flutter::EncodableMap StartupStatus(const std::wstring& expected_target) {
  flutter::EncodableMap status;
  status[flutter::EncodableValue("supported")] =
      flutter::EncodableValue(true);
  status[flutter::EncodableValue("registered")] =
      flutter::EncodableValue(false);
  status[flutter::EncodableValue("targetMatches")] =
      flutter::EncodableValue(false);
  status[flutter::EncodableValue("mode")] =
      flutter::EncodableValue("signage");
  for (const auto& path : StartupShortcutPaths()) {
    if (!std::filesystem::is_regular_file(path)) continue;
    std::wstring target;
    std::wstring arguments;
    if (!LoadShortcut(path, &target, &arguments)) continue;
    status[flutter::EncodableValue("registered")] =
        flutter::EncodableValue(true);
    status[flutter::EncodableValue("targetMatches")] =
        flutter::EncodableValue(SamePath(target, expected_target));
    status[flutter::EncodableValue("mode")] = flutter::EncodableValue(
        arguments.find(L"--startup-mode hidden") != std::wstring::npos
            ? "hidden"
            : "signage");
    status[flutter::EncodableValue("shortcutPath")] =
        flutter::EncodableValue(WideToUtf8(path.wstring()));
    status[flutter::EncodableValue("targetPath")] =
        flutter::EncodableValue(WideToUtf8(target));
    break;
  }
  return status;
}

bool RegisterStartupShortcut(const std::wstring& target,
                             const std::wstring& working_directory,
                             const std::wstring& mode) {
  const auto paths = StartupShortcutPaths();
  if (paths.empty() || target.empty()) return false;
  std::error_code error;
  for (const auto& path : paths) std::filesystem::remove(path, error);

  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return false;
  }
  HRESULT result = link->SetPath(target.c_str());
  if (SUCCEEDED(result)) {
    result = link->SetWorkingDirectory(working_directory.c_str());
  }
  if (SUCCEEDED(result)) {
    const std::wstring arguments =
        std::wstring(L"--startup-mode ") +
        (mode == L"hidden" ? L"hidden" : L"signage");
    result = link->SetArguments(arguments.c_str());
  }
  if (SUCCEEDED(result)) {
    result = link->SetDescription(L"여의도성당Signage");
  }
  if (SUCCEEDED(result)) result = link->SetIconLocation(target.c_str(), 0);
  IPersistFile* persist = nullptr;
  if (SUCCEEDED(result)) result = link->QueryInterface(IID_PPV_ARGS(&persist));
  if (SUCCEEDED(result)) result = persist->Save(paths.front().c_str(), TRUE);
  if (persist != nullptr) persist->Release();
  link->Release();
  return SUCCEEDED(result);
}

bool UnregisterStartupShortcuts() {
  bool removed = false;
  std::error_code error;
  for (const auto& path : StartupShortcutPaths()) {
    removed = std::filesystem::remove(path, error) || removed;
  }
  return removed;
}

bool LaunchKeyboardExecutable(const std::filesystem::path& executable) {
  if (!std::filesystem::is_regular_file(executable)) return false;
  const auto result = reinterpret_cast<INT_PTR>(::ShellExecuteW(
      nullptr, L"open", executable.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  return result > 32;
}

HWND FindWindowsKeyboardWindow() {
  for (const wchar_t* class_name : {L"OSKMainClass", L"IPTip_Main_Window"}) {
    const HWND keyboard = ::FindWindowW(class_name, nullptr);
    if (keyboard != nullptr && ::IsWindowVisible(keyboard)) return keyboard;
  }
  return nullptr;
}

bool IsWindowsKeyboardVisible() {
  return FindWindowsKeyboardWindow() != nullptr;
}

bool ShowWindowsKeyboard() {
  const HWND existing = FindWindowsKeyboardWindow();
  if (existing != nullptr) {
    ::ShowWindow(existing, SW_RESTORE);
    return true;
  }

  // TabTip은 백그라운드 프로세스가 남으면 두 번째 실행부터 창을 다시
  // 표시하지 않는 경우가 있다. 명시적으로 열고 닫을 수 있는 Windows 화상
  // 키보드(osk.exe)를 사용해 반복 호출을 보장한다.
  wchar_t system_directory[MAX_PATH]{};
  const UINT system_length =
      ::GetSystemDirectoryW(system_directory, MAX_PATH);
  if (system_length > 0 && system_length < MAX_PATH) {
    return LaunchKeyboardExecutable(
        std::filesystem::path(system_directory) / L"osk.exe");
  }
  return false;
}

bool HideWindowsKeyboard() {
  bool requested = false;
  for (const wchar_t* class_name : {L"IPTip_Main_Window", L"OSKMainClass"}) {
    const HWND keyboard = ::FindWindowW(class_name, nullptr);
    if (keyboard != nullptr) {
      ::PostMessageW(keyboard, WM_CLOSE, 0, 0);
      ::ShowWindow(keyboard, SW_HIDE);
      requested = true;
    }
  }
  return requested;
}

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
  system_keyboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_kiosk/system_keyboard",
          &flutter::StandardMethodCodec::GetInstance());
  system_keyboard_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "show") {
          result->Success(flutter::EncodableValue(ShowWindowsKeyboard()));
        } else if (call.method_name() == "hide") {
          result->Success(flutter::EncodableValue(HideWindowsKeyboard()));
        } else if (call.method_name() == "isVisible") {
          result->Success(flutter::EncodableValue(IsWindowsKeyboardVisible()));
        } else {
          result->NotImplemented();
        }
      });
  windows_startup_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_kiosk/windows_startup",
          &flutter::StandardMethodCodec::GetInstance());
  windows_startup_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const HRESULT com_result =
            ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(com_result) && com_result != RPC_E_CHANGED_MODE) {
          result->Error("com-init", "Windows COM initialization failed");
          return;
        }
        if (call.method_name() == "getStatus") {
          result->Success(flutter::EncodableValue(StartupStatus(
              MethodStringArgument(call, "targetPath"))));
        } else if (call.method_name() == "register") {
          result->Success(flutter::EncodableValue(RegisterStartupShortcut(
              MethodStringArgument(call, "targetPath"),
              MethodStringArgument(call, "workingDirectory"),
              MethodStringArgument(call, "mode"))));
        } else if (call.method_name() == "unregister") {
          result->Success(
              flutter::EncodableValue(UnregisterStartupShortcuts()));
        } else {
          result->NotImplemented();
        }
        if (SUCCEEDED(com_result)) ::CoUninitialize();
      });
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
  system_keyboard_channel_.reset();
  windows_startup_channel_.reset();
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
