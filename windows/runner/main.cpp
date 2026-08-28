#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <tlhelp32.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kInstanceMutexName[] =
    L"Local\\CUniverse.SimpleKiosk.AppInstance";
constexpr wchar_t kRestartEventName[] =
    L"Local\\CUniverse.SimpleKiosk.RestartExistingInstance";
constexpr wchar_t kInstanceStateName[] =
    L"Local\\CUniverse.SimpleKiosk.InstanceState";
constexpr DWORD kGracefulExitTimeoutMs = 5000;
constexpr DWORD kForcedExitTimeoutMs = 10000;
constexpr DWORD kInstanceStateWaitMs = 2000;
constexpr DWORD kLegacyGracefulExitTimeoutMs = 2000;

struct RestartListenerContext {
  HANDLE restart_event;
  HANDLE stop_event;
  HWND window;
};

struct CloseWindowsContext {
  DWORD process_id;
};

BOOL CALLBACK CloseProcessWindows(HWND window, LPARAM parameter) {
  auto* context = reinterpret_cast<CloseWindowsContext*>(parameter);
  DWORD window_process_id = 0;
  GetWindowThreadProcessId(window, &window_process_id);
  if (window_process_id == context->process_id) {
    PostMessageW(window, WM_CLOSE, 0, 0);
  }
  return TRUE;
}

DWORD WINAPI RestartListener(LPVOID parameter) {
  auto* context = static_cast<RestartListenerContext*>(parameter);
  HANDLE events[] = {context->stop_event, context->restart_event};

  while (true) {
    const DWORD result = WaitForMultipleObjects(2, events, FALSE, INFINITE);
    if (result == WAIT_OBJECT_0) {
      return 0;
    }
    if (result == WAIT_OBJECT_0 + 1) {
      PostMessage(context->window,
                  Win32Window::kRestartExistingInstanceMessage, 0, 0);
      continue;
    }
    return 1;
  }
}

DWORD ReadExistingProcessId() {
  const ULONGLONG deadline = GetTickCount64() + kInstanceStateWaitMs;
  HANDLE state = nullptr;
  while (state == nullptr && GetTickCount64() < deadline) {
    state = OpenFileMappingW(FILE_MAP_READ, FALSE, kInstanceStateName);
    if (state == nullptr) {
      Sleep(25);
    }
  }
  if (state == nullptr) {
    return 0;
  }

  const auto* process_id =
      static_cast<const DWORD*>(MapViewOfFile(state, FILE_MAP_READ, 0, 0,
                                              sizeof(DWORD)));
  const DWORD result = process_id == nullptr ? 0 : *process_id;
  if (process_id != nullptr) {
    UnmapViewOfFile(process_id);
  }
  CloseHandle(state);
  return result;
}

HANDLE CreateInstanceState() {
  HANDLE state = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr,
                                    PAGE_READWRITE, 0, sizeof(DWORD),
                                    kInstanceStateName);
  if (state == nullptr) {
    return nullptr;
  }
  auto* process_id = static_cast<DWORD*>(
      MapViewOfFile(state, FILE_MAP_WRITE, 0, 0, sizeof(DWORD)));
  if (process_id == nullptr) {
    CloseHandle(state);
    return nullptr;
  }
  *process_id = GetCurrentProcessId();
  UnmapViewOfFile(process_id);
  return state;
}

bool RestartExistingInstance(HANDLE mutex) {
  const DWORD existing_process_id = ReadExistingProcessId();
  HANDLE existing_process = nullptr;
  if (existing_process_id != 0 &&
      existing_process_id != GetCurrentProcessId()) {
    existing_process =
        OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE,
                    existing_process_id);
  }

  HANDLE restart_event =
      CreateEventW(nullptr, FALSE, FALSE, kRestartEventName);
  if (restart_event == nullptr) {
    return false;
  }

  const bool signaled = SetEvent(restart_event) != FALSE;
  CloseHandle(restart_event);
  if (!signaled) {
    return false;
  }

  DWORD wait_result = WaitForSingleObject(mutex, kGracefulExitTimeoutMs);
  if (wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED) {
    if (existing_process != nullptr) {
      CloseHandle(existing_process);
    }
    return true;
  }

  // The UI thread may be hung and unable to process the restart message. The
  // PID comes from the shared state owned by the mutex holder, so terminate
  // only that exact instance and wait until Windows has finished stopping it.
  if (existing_process == nullptr ||
      TerminateProcess(existing_process, EXIT_FAILURE) == FALSE ||
      WaitForSingleObject(existing_process, kForcedExitTimeoutMs) !=
          WAIT_OBJECT_0) {
    if (existing_process != nullptr) {
      CloseHandle(existing_process);
    }
    return false;
  }
  CloseHandle(existing_process);

  wait_result = WaitForSingleObject(mutex, kForcedExitTimeoutMs);
  return wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED;
}

std::wstring CurrentExecutableName() {
  std::vector<wchar_t> path(MAX_PATH);
  DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                    static_cast<DWORD>(path.size()));
  while (length == path.size()) {
    path.resize(path.size() * 2);
    length = GetModuleFileNameW(nullptr, path.data(),
                                static_cast<DWORD>(path.size()));
  }
  if (length == 0) {
    return L"";
  }
  const std::wstring full_path(path.data(), length);
  const size_t separator = full_path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? full_path
                                         : full_path.substr(separator + 1);
}

bool StopLegacyInstances() {
  const std::wstring executable_name = CurrentExecutableName();
  if (executable_name.empty()) {
    return false;
  }

  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return false;
  }

  std::vector<DWORD> process_ids;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID != GetCurrentProcessId() &&
          _wcsicmp(entry.szExeFile, executable_name.c_str()) == 0) {
        process_ids.push_back(entry.th32ProcessID);
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);

  for (const DWORD process_id : process_ids) {
    HANDLE process =
        OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE, process_id);
    if (process == nullptr) {
      return false;
    }

    CloseWindowsContext close_context{process_id};
    EnumWindows(CloseProcessWindows,
                reinterpret_cast<LPARAM>(&close_context));
    DWORD wait_result =
        WaitForSingleObject(process, kLegacyGracefulExitTimeoutMs);
    if (wait_result != WAIT_OBJECT_0) {
      if (TerminateProcess(process, EXIT_FAILURE) == FALSE) {
        CloseHandle(process);
        return false;
      }
      wait_result = WaitForSingleObject(process, kForcedExitTimeoutMs);
    }
    CloseHandle(process);
    if (wait_result != WAIT_OBJECT_0) {
      return false;
    }
  }
  return true;
}

void ReleaseInstanceMutex(HANDLE mutex) {
  if (mutex != nullptr) {
    ReleaseMutex(mutex);
    CloseHandle(mutex);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  HANDLE instance_mutex = CreateMutexW(nullptr, TRUE, kInstanceMutexName);
  const bool instance_already_exists = GetLastError() == ERROR_ALREADY_EXISTS;
  if (instance_mutex == nullptr ||
      (instance_already_exists && !RestartExistingInstance(instance_mutex))) {
    if (instance_mutex != nullptr) {
      CloseHandle(instance_mutex);
    }
    MessageBoxW(nullptr,
                L"기존 앱을 종료하지 못해 새 인스턴스를 시작하지 않았습니다.",
                L"여의도성당 Signage", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  HANDLE instance_state = CreateInstanceState();
  if (instance_state == nullptr) {
    ReleaseInstanceMutex(instance_mutex);
    MessageBoxW(nullptr, L"중복 실행 상태를 초기화하지 못했습니다.",
                L"여의도성당 Signage", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  if (!instance_already_exists && !StopLegacyInstances()) {
    CloseHandle(instance_state);
    ReleaseInstanceMutex(instance_mutex);
    MessageBoxW(nullptr, L"기존 앱 프로세스를 종료하지 못했습니다.",
                L"여의도성당 Signage", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
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
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"여의도성당 Signage", origin, size)) {
    CloseHandle(instance_state);
    ReleaseInstanceMutex(instance_mutex);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  HANDLE restart_event =
      CreateEventW(nullptr, FALSE, FALSE, kRestartEventName);
  HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  RestartListenerContext listener_context{
      restart_event,
      stop_event,
      window.GetHandle(),
  };
  HANDLE listener_thread = nullptr;
  if (restart_event != nullptr && stop_event != nullptr) {
    listener_thread =
        CreateThread(nullptr, 0, RestartListener, &listener_context, 0, nullptr);
  }

  if (listener_thread == nullptr) {
    if (restart_event != nullptr) {
      CloseHandle(restart_event);
    }
    if (stop_event != nullptr) {
      CloseHandle(stop_event);
    }
    window.Destroy();
    CloseHandle(instance_state);
    ReleaseInstanceMutex(instance_mutex);
    ::CoUninitialize();
    MessageBoxW(nullptr, L"중복 실행 감시를 시작하지 못했습니다.",
                L"여의도성당 Signage", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  SetEvent(stop_event);
  WaitForSingleObject(listener_thread, INFINITE);
  CloseHandle(listener_thread);
  CloseHandle(stop_event);
  CloseHandle(restart_event);
  CloseHandle(instance_state);
  ReleaseInstanceMutex(instance_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
