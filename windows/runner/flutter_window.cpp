#include "flutter_window.h"

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <thread>
#include <tlhelp32.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <shlobj.h>
#include <shobjidl.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kShowVersionMessage = WM_APP + 1;
constexpr UINT kCheckUpdateMessage = WM_APP + 2;
constexpr UINT kShowManualMessage = WM_APP + 3;
constexpr UINT_PTR kSurfaceWatchdogTimerId = 1;
constexpr UINT kSurfaceWatchdogIntervalMs = 15000;
HWND g_kiosk_window = nullptr;
std::atomic_bool g_kiosk_mode_active = false;
std::atomic_bool g_kiosk_lockdown_enabled = false;
std::atomic_bool g_block_windows_key = true;
std::atomic_bool g_block_alt_tab = true;
std::atomic_bool g_block_alt_escape = true;
std::atomic_bool g_block_alt_f4 = true;
std::atomic_bool g_block_alt_space = true;
std::atomic_bool g_block_ctrl_escape = true;
std::atomic_bool g_block_ctrl_shift_escape = true;
std::atomic_bool g_block_launch_app1 = true;
std::atomic_bool g_block_launch_app2 = true;
std::atomic_bool g_block_launch_mail = true;
std::atomic_bool g_block_browser_home = true;
std::atomic_bool g_block_browser_search = true;
std::atomic_bool g_block_browser_favorites = true;
std::atomic_bool g_prevent_screen_saver = false;
std::atomic_bool g_prevent_display_sleep = false;
std::atomic_uint64_t g_emergency_exit_sequence = 0;
std::atomic_uint64_t g_keyboard_emergency_exit_token = 0;
std::atomic_uint64_t g_touch_emergency_exit_token = 0;
HWND g_flutter_view_window = nullptr;
WNDPROC g_flutter_view_wndproc = nullptr;
std::unordered_map<UINT32, POINT> g_active_touch_points;

// System.EdgeGesture.DisableTouchWhenFullscreen
// https://learn.microsoft.com/windows/win32/properties/props-system-edgegesture-disabletouchwhenfullscreen
const PROPERTYKEY kEdgeGestureDisableTouchWhenFullscreen = {
    {0x32CE38B2, 0x2C9A, 0x41B1,
     {0x9B, 0xC5, 0xB3, 0x78, 0x43, 0x94, 0xAA, 0x44}},
    2};

void SetFullscreenEdgeGesturesDisabled(bool disabled) {
  if (g_kiosk_window == nullptr || !::IsWindow(g_kiosk_window)) return;

  IPropertyStore* property_store = nullptr;
  const HRESULT result = ::SHGetPropertyStoreForWindow(
      g_kiosk_window, IID_PPV_ARGS(&property_store));
  if (FAILED(result) || property_store == nullptr) return;

  PROPVARIANT value{};
  value.vt = VT_BOOL;
  value.boolVal = disabled ? VARIANT_TRUE : VARIANT_FALSE;
  property_store->SetValue(kEdgeGestureDisableTouchWhenFullscreen, value);
  property_store->Release();
}

void ApplyDisplayPowerPolicy() {
  EXECUTION_STATE state = ES_CONTINUOUS;
  if (g_kiosk_mode_active.load() && g_prevent_display_sleep.load()) {
    state |= ES_DISPLAY_REQUIRED;
  }
  ::SetThreadExecutionState(state);
}

void ArmEmergencyExit(std::atomic_uint64_t* active_token,
                      int hold_milliseconds) {
  const uint64_t token = g_emergency_exit_sequence.fetch_add(1) + 1;
  uint64_t expected = 0;
  if (!active_token->compare_exchange_strong(expected, token)) return;
  std::thread([active_token, token, hold_milliseconds]() {
    const int checks = hold_milliseconds / 100;
    for (int index = 0; index < checks; ++index) {
      ::Sleep(100);
      if (active_token->load() != token) return;
    }
    if (active_token->load() != token) return;
    g_kiosk_lockdown_enabled.store(false);
    ::OutputDebugStringW(
        L"[ysignage] Emergency exit shortcut terminated the application.\n");
    ::TerminateProcess(::GetCurrentProcess(), ERROR_PROCESS_ABORTED);
  }).detach();
}

enum class EmergencyTouchCorner { kNone, kLeft, kRight };

EmergencyTouchCorner GetEmergencyTouchCorner(const POINT& point) {
  if (g_kiosk_window == nullptr) return EmergencyTouchCorner::kNone;
  const HMONITOR monitor =
      ::MonitorFromWindow(g_kiosk_window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfoW(monitor, &info)) {
    return EmergencyTouchCorner::kNone;
  }
  const UINT dpi = ::GetDpiForWindow(g_kiosk_window);
  const int corner_size = ::MulDiv(96, dpi == 0 ? 96 : dpi, 96);
  const bool at_top = point.y >= info.rcMonitor.top &&
                      point.y < info.rcMonitor.top + corner_size;
  if (!at_top) return EmergencyTouchCorner::kNone;
  if (point.x >= info.rcMonitor.left &&
      point.x < info.rcMonitor.left + corner_size) {
    return EmergencyTouchCorner::kLeft;
  }
  if (point.x >= info.rcMonitor.right - corner_size &&
      point.x < info.rcMonitor.right) {
    return EmergencyTouchCorner::kRight;
  }
  return EmergencyTouchCorner::kNone;
}

void UpdateTouchEmergencyExit() {
  bool left = false;
  bool right = false;
  for (const auto& entry : g_active_touch_points) {
    switch (GetEmergencyTouchCorner(entry.second)) {
      case EmergencyTouchCorner::kLeft:
        left = true;
        break;
      case EmergencyTouchCorner::kRight:
        right = true;
        break;
      case EmergencyTouchCorner::kNone:
        break;
    }
  }
  if (left && right && g_kiosk_mode_active.load()) {
    ArmEmergencyExit(&g_touch_emergency_exit_token, 8000);
  } else {
    g_touch_emergency_exit_token.store(0);
  }
}

LRESULT CALLBACK FlutterViewTouchProc(HWND window, UINT message,
                                      WPARAM wparam, LPARAM lparam) {
  if (message == WM_POINTERDOWN || message == WM_POINTERUPDATE) {
    const UINT32 pointer_id = GET_POINTERID_WPARAM(wparam);
    POINTER_INFO info{};
    if (::GetPointerInfo(pointer_id, &info) && info.pointerType == PT_TOUCH) {
      if ((info.pointerFlags & POINTER_FLAG_INCONTACT) != 0) {
        // 일반 터치 장치는 대개 10점 이하이다. 누락된 UP 메시지로 ID가
        // 쌓이더라도 입력 처리 비용이 계속 증가하지 않도록 방어한다.
        if (g_active_touch_points.size() >= 32 &&
            g_active_touch_points.find(pointer_id) ==
                g_active_touch_points.end()) {
          g_active_touch_points.clear();
        }
        g_active_touch_points[pointer_id] = info.ptPixelLocation;
      } else {
        g_active_touch_points.erase(pointer_id);
      }
      UpdateTouchEmergencyExit();
    }
  } else if (message == WM_POINTERUP || message == WM_POINTERLEAVE) {
    g_active_touch_points.erase(GET_POINTERID_WPARAM(wparam));
    UpdateTouchEmergencyExit();
  } else if (message == WM_POINTERCAPTURECHANGED) {
    g_active_touch_points.clear();
    g_touch_emergency_exit_token.store(0);
  }
  return g_flutter_view_wndproc == nullptr
             ? ::DefWindowProcW(window, message, wparam, lparam)
             : ::CallWindowProcW(g_flutter_view_wndproc, window, message,
                                 wparam, lparam);
}

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

bool MethodBoolArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key, bool fallback = false) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) return fallback;
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) return fallback;
  const auto* value = std::get_if<bool>(&iterator->second);
  return value == nullptr ? fallback : *value;
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

std::unordered_set<DWORD> ApplicationProcessTree() {
  const DWORD root_process_id = ::GetCurrentProcessId();
  std::unordered_set<DWORD> process_ids{root_process_id};
  std::vector<std::pair<DWORD, DWORD>> relationships;
  const HANDLE snapshot =
      ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return process_ids;

  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (::Process32FirstW(snapshot, &entry)) {
    do {
      relationships.emplace_back(entry.th32ProcessID,
                                 entry.th32ParentProcessID);
    } while (::Process32NextW(snapshot, &entry));
  }
  ::CloseHandle(snapshot);

  bool added = true;
  while (added) {
    added = false;
    for (const auto& relationship : relationships) {
      if (process_ids.find(relationship.second) != process_ids.end() &&
          process_ids.find(relationship.first) == process_ids.end()) {
        process_ids.insert(relationship.first);
        added = true;
      }
    }
  }
  return process_ids;
}

BOOL CALLBACK HideApplicationWindow(HWND window, LPARAM parameter) {
  const auto* process_ids =
      reinterpret_cast<const std::unordered_set<DWORD>*>(parameter);
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_ids->find(process_id) != process_ids->end() &&
      ::IsWindowVisible(window)) {
    ::ShowWindow(window, SW_HIDE);
  }
  return TRUE;
}

void HideApplicationProcessWindows() {
  const auto process_ids = ApplicationProcessTree();
  ::EnumWindows(HideApplicationWindow,
                reinterpret_cast<LPARAM>(&process_ids));
}

LRESULT CALLBACK KioskKeyboardHook(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_kiosk_window != nullptr) {
    const auto* event = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    const bool key_down =
        wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
    const bool key_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
    const HWND foreground = ::GetAncestor(::GetForegroundWindow(), GA_ROOT);
    if (key_down && foreground == g_kiosk_window) {
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
    const bool alt = (event->flags & LLKHF_ALTDOWN) != 0 ||
                     (::GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
    const bool control = (::GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool shift = (::GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
    const DWORD key = event->vkCode;
    if (g_kiosk_mode_active.load()) {
      if (key_down && key == VK_F4 && control && alt && shift) {
        ArmEmergencyExit(&g_keyboard_emergency_exit_token, 3000);
        return 1;
      }
      if (key_up && (key == VK_F4 || key == VK_CONTROL ||
                     key == VK_LCONTROL || key == VK_RCONTROL ||
                     key == VK_MENU || key == VK_LMENU || key == VK_RMENU ||
                     key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT)) {
        g_keyboard_emergency_exit_token.store(0);
      }
    }

    if (g_kiosk_lockdown_enabled.load()) {
      // Windows 셸, 작업 전환, 실행 창, 바탕화면 및 작업 관리자로 빠져나가는
      // 일반 단축키를 각각의 관리 설정에 따라 차단한다.
      const bool block_key =
          ((key == VK_LWIN || key == VK_RWIN) &&
           g_block_windows_key.load()) ||
          (alt && key == VK_TAB && g_block_alt_tab.load()) ||
          (alt && key == VK_ESCAPE && g_block_alt_escape.load()) ||
          (alt && key == VK_F4 && g_block_alt_f4.load()) ||
          (alt && key == VK_SPACE && g_block_alt_space.load()) ||
          (control && !shift && key == VK_ESCAPE &&
           g_block_ctrl_escape.load()) ||
          (control && shift && key == VK_ESCAPE &&
           g_block_ctrl_shift_escape.load()) ||
          (key == VK_LAUNCH_APP1 && g_block_launch_app1.load()) ||
          (key == VK_LAUNCH_APP2 && g_block_launch_app2.load()) ||
          (key == VK_LAUNCH_MAIL && g_block_launch_mail.load()) ||
          (key == VK_BROWSER_HOME && g_block_browser_home.load()) ||
          (key == VK_BROWSER_SEARCH && g_block_browser_search.load()) ||
          (key == VK_BROWSER_FAVORITES &&
           g_block_browser_favorites.load());
      if (block_key) {
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
  kiosk_mode_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_kiosk/windows_kiosk_mode",
          &flutter::StandardMethodCodec::GetInstance());
  kiosk_mode_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setEnabled") {
          const bool legacy_enabled = MethodBoolArgument(call, "enabled");
          const bool active =
              MethodBoolArgument(call, "active", legacy_enabled);
          const bool shortcut_lockdown = MethodBoolArgument(
              call, "shortcutLockdownEnabled", legacy_enabled);
          const bool disable_edge_swipe =
              MethodBoolArgument(call, "disableEdgeSwipe", true);
          g_kiosk_mode_active.store(active);
          g_kiosk_lockdown_enabled.store(active && shortcut_lockdown);
          g_block_windows_key.store(
              MethodBoolArgument(call, "blockWindowsKey", true));
          g_block_alt_tab.store(
              MethodBoolArgument(call, "blockAltTab", true));
          g_block_alt_escape.store(
              MethodBoolArgument(call, "blockAltEscape", true));
          g_block_alt_f4.store(
              MethodBoolArgument(call, "blockAltF4", true));
          g_block_alt_space.store(
              MethodBoolArgument(call, "blockAltSpace", true));
          g_block_ctrl_escape.store(
              MethodBoolArgument(call, "blockCtrlEscape", true));
          g_block_ctrl_shift_escape.store(
              MethodBoolArgument(call, "blockCtrlShiftEscape", true));
          g_block_launch_app1.store(
              MethodBoolArgument(call, "blockLaunchApp1", true));
          g_block_launch_app2.store(
              MethodBoolArgument(call, "blockLaunchApp2", true));
          g_block_launch_mail.store(
              MethodBoolArgument(call, "blockLaunchMail", true));
          g_block_browser_home.store(
              MethodBoolArgument(call, "blockBrowserHome", true));
          g_block_browser_search.store(
              MethodBoolArgument(call, "blockBrowserSearch", true));
          g_block_browser_favorites.store(
              MethodBoolArgument(call, "blockBrowserFavorites", true));
          g_prevent_screen_saver.store(
              active && MethodBoolArgument(call, "preventScreenSaver"));
          g_prevent_display_sleep.store(
              active && MethodBoolArgument(call, "preventDisplaySleep"));
          // Flutter/WebView의 드래그 처리가 시작되기 전에 Windows 셸이 화면
          // 가장자리 스와이프를 가로채 작업 표시줄을 띄우지 않게 한다.
          // 시스템 전역 정책이 아니라 이 전체화면 창에만 적용된다.
          SetFullscreenEdgeGesturesDisabled(active && disable_edge_swipe);
          ApplyDisplayPowerPolicy();
          if (active && keyboard_hook_ == nullptr) {
            keyboard_hook_ = ::SetWindowsHookEx(
                WH_KEYBOARD_LL, KioskKeyboardHook,
                ::GetModuleHandle(nullptr), 0);
          } else if (!active && keyboard_hook_ != nullptr) {
            ::UnhookWindowsHookEx(keyboard_hook_);
            keyboard_hook_ = nullptr;
          }
          if (!active) {
            g_active_touch_points.clear();
            g_keyboard_emergency_exit_token.store(0);
            g_touch_emergency_exit_token.store(0);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "recoverSurface") {
          RecoverRenderingSurface(true);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "hideProcessWindows") {
          HideApplicationProcessWindows();
          result->Success(flutter::EncodableValue(true));
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
  g_flutter_view_window = flutter_controller_->view()->GetNativeWindow();
  g_flutter_view_wndproc = reinterpret_cast<WNDPROC>(::SetWindowLongPtrW(
      g_flutter_view_window, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(FlutterViewTouchProc)));
  ::SetTimer(g_kiosk_window, kSurfaceWatchdogTimerId,
             kSurfaceWatchdogIntervalMs, nullptr);
  // 창 표시와 전체화면 전환은 첫 Flutter 프레임 뒤 Dart에서 한 경로로만
  // 수행한다. 네이티브에서도 창을 표시하면 첫 프레임/전체화면 resize가
  // 경쟁해 렌더 표면이 검게 멈출 수 있다.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RecoverRenderingSurface(bool force_resize) {
  if (!flutter_controller_ || !flutter_controller_->view() ||
      g_kiosk_window == nullptr) {
    return;
  }
  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  if (flutter_view == nullptr) return;

  RECT client{};
  RECT child{};
  ::GetClientRect(g_kiosk_window, &client);
  ::GetWindowRect(flutter_view, &child);
  const LONG width = client.right - client.left;
  const LONG height = client.bottom - client.top;
  if (force_resize && width > 1 && height > 1) {
    // ForceRedraw만으로는 손상된 Flutter Windows swapchain 크기가 복구되지
    // 않는다. 자식 HWND를 1px 줄였다가 복원해 실제 WM_SIZE/표면 재생성
    // 사이클을 발생시킨다. 창을 표시하기 전에도 안전하게 호출할 수 있다.
    ::SetWindowPos(flutter_view, nullptr, 0, 0, width - 1, height,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    ::SetWindowPos(flutter_view, nullptr, 0, 0, width, height,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else if (!::IsWindowVisible(flutter_view) ||
             child.right - child.left != width ||
             child.bottom - child.top != height) {
    ::SetWindowPos(flutter_view, nullptr, 0, 0, width, height,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }

  ::RedrawWindow(flutter_view, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
  ::RedrawWindow(g_kiosk_window, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
  flutter_controller_->ForceRedraw();
}

void FlutterWindow::OnDestroy() {
  SetFullscreenEdgeGesturesDisabled(false);
  g_kiosk_mode_active.store(false);
  g_kiosk_lockdown_enabled.store(false);
  g_prevent_screen_saver.store(false);
  g_prevent_display_sleep.store(false);
  ApplyDisplayPowerPolicy();
  g_keyboard_emergency_exit_token.store(0);
  g_touch_emergency_exit_token.store(0);
  if (g_kiosk_window != nullptr) {
    ::KillTimer(g_kiosk_window, kSurfaceWatchdogTimerId);
  }
  if (keyboard_hook_ != nullptr) {
    ::UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  if (g_flutter_view_window != nullptr &&
      g_flutter_view_wndproc != nullptr &&
      ::IsWindow(g_flutter_view_window)) {
    ::SetWindowLongPtrW(g_flutter_view_window, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(g_flutter_view_wndproc));
  }
  g_flutter_view_window = nullptr;
  g_flutter_view_wndproc = nullptr;
  g_active_touch_points.clear();
  g_kiosk_window = nullptr;
  shortcut_channel_.reset();
  system_keyboard_channel_.reset();
  kiosk_mode_channel_.reset();
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
  if (message == kRestartExistingInstanceMessage) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  if (message == WM_SYSCOMMAND &&
      (wparam & 0xFFF0) == SC_SCREENSAVE &&
      g_kiosk_mode_active.load() && g_prevent_screen_saver.load()) {
    return 0;
  }

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
    case WM_TIMER:
      if (wparam == kSurfaceWatchdogTimerId &&
          g_kiosk_mode_active.load() && ::IsWindowVisible(hwnd)) {
        // 주기 감시는 WebView 자식창을 강제 갱신해 깜빡임을 만들지 않고
        // Flutter 합성 프레임만 요청한다. 전체 복구는 DWM/화면 이벤트에서 수행한다.
        if (flutter_controller_) flutter_controller_->ForceRedraw();
        return 0;
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_DWMCOMPOSITIONCHANGED:
      RecoverRenderingSurface(true);
      break;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND) {
        RecoverRenderingSurface(true);
      }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE &&
          g_kiosk_mode_active.load()) {
        RecoverRenderingSurface();
      }
      break;
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
