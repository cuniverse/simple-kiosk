#include <windows.h>
#include <shellapi.h>
#include <softpub.h>
#include <wincrypt.h>
#include <wintrust.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::string ReadTextFile(const fs::path& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) return {};
  return std::string(std::istreambuf_iterator<char>(stream),
                     std::istreambuf_iterator<char>());
}

std::wstring JsonString(const std::string& json, const std::string& key) {
  const std::regex expression("\\\"" + key +
                              "\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
  std::smatch match;
  if (!std::regex_search(json, match, expression) || match.size() < 2) {
    return {};
  }
  return Utf8ToWide(match[1].str());
}

bool IsSafeVersion(const std::wstring& version) {
  if (version.empty()) return false;
  for (const wchar_t value : version) {
    const bool allowed = (value >= L'0' && value <= L'9') ||
                         (value >= L'a' && value <= L'z') ||
                         (value >= L'A' && value <= L'Z') || value == L'.' ||
                         value == L'-' || value == L'+';
    if (!allowed) return false;
  }
  return version.find(L"..") == std::wstring::npos;
}

std::wstring Quote(const std::wstring& value) {
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
      continue;
    }
    if (character == L'\"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(L'\"');
      backslashes = 0;
      continue;
    }
    quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted.push_back(character);
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

std::wstring Timestamp() {
  SYSTEMTIME time{};
  GetSystemTime(&time);
  wchar_t buffer[40]{};
  swprintf_s(buffer, L"%04d-%02d-%02dT%02d:%02d:%02dZ", time.wYear,
             time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond);
  return buffer;
}

void AppendLog(const fs::path& root, const std::wstring& message) {
  std::error_code error;
  fs::create_directories(root / L"logs", error);
  std::ofstream stream(root / L"logs" / L"updater.log",
                       std::ios::app | std::ios::binary);
  if (stream) {
    stream << WideToUtf8(Timestamp() + L" [launcher] " + message + L"\n");
  }
}

void CopyIfPresent(const fs::path& source, const fs::path& destination) {
  std::error_code error;
  if (!fs::is_regular_file(source, error)) return;
  fs::copy_file(source, destination, fs::copy_options::overwrite_existing,
                error);
}

std::wstring NormalizeThumbprint(const std::wstring& value) {
  std::wstring normalized;
  for (const wchar_t character : value) {
    if (character >= L'0' && character <= L'9') {
      normalized.push_back(character);
    } else if (character >= L'a' && character <= L'f') {
      normalized.push_back(character - L'a' + L'A');
    } else if (character >= L'A' && character <= L'F') {
      normalized.push_back(character);
    }
  }
  return normalized;
}

bool VerifyEmbeddedSignature(const fs::path& file_path) {
  WINTRUST_FILE_INFO file_info{};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = file_path.c_str();

  WINTRUST_DATA trust_data{};
  trust_data.cbStruct = sizeof(trust_data);
  trust_data.dwUIChoice = WTD_UI_NONE;
  trust_data.fdwRevocationChecks = WTD_REVOKE_NONE;
  trust_data.dwUnionChoice = WTD_CHOICE_FILE;
  trust_data.pFile = &file_info;
  trust_data.dwStateAction = WTD_STATEACTION_VERIFY;
  trust_data.dwProvFlags = WTD_REVOCATION_CHECK_NONE;

  GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  const LONG status = WinVerifyTrust(nullptr, &policy, &trust_data);
  trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(nullptr, &policy, &trust_data);
  return status == ERROR_SUCCESS;
}

std::wstring EmbeddedSignerThumbprint(const fs::path& file_path) {
  HCERTSTORE certificate_store = nullptr;
  HCRYPTMSG crypt_message = nullptr;
  DWORD encoding = 0;
  DWORD content_type = 0;
  DWORD format_type = 0;
  if (!CryptQueryObject(
          CERT_QUERY_OBJECT_FILE, file_path.c_str(),
          CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
          CERT_QUERY_FORMAT_FLAG_BINARY, 0, &encoding, &content_type,
          &format_type, &certificate_store, &crypt_message, nullptr)) {
    return {};
  }

  std::wstring thumbprint;
  DWORD signer_size = 0;
  if (CryptMsgGetParam(crypt_message, CMSG_SIGNER_INFO_PARAM, 0, nullptr,
                       &signer_size) &&
      signer_size > 0) {
    std::vector<BYTE> signer_buffer(signer_size);
    if (CryptMsgGetParam(crypt_message, CMSG_SIGNER_INFO_PARAM, 0,
                         signer_buffer.data(), &signer_size)) {
      const auto* signer_info =
          reinterpret_cast<const CMSG_SIGNER_INFO*>(signer_buffer.data());
      CERT_INFO certificate_info{};
      certificate_info.Issuer = signer_info->Issuer;
      certificate_info.SerialNumber = signer_info->SerialNumber;
      PCCERT_CONTEXT certificate = CertFindCertificateInStore(
          certificate_store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
          CERT_FIND_SUBJECT_CERT, &certificate_info, nullptr);
      if (certificate != nullptr) {
        DWORD hash_size = 0;
        if (CertGetCertificateContextProperty(
                certificate, CERT_SHA1_HASH_PROP_ID, nullptr, &hash_size) &&
            hash_size > 0) {
          std::vector<BYTE> hash(hash_size);
          if (CertGetCertificateContextProperty(
                  certificate, CERT_SHA1_HASH_PROP_ID, hash.data(),
                  &hash_size)) {
            constexpr wchar_t hexadecimal[] = L"0123456789ABCDEF";
            thumbprint.reserve(hash_size * 2);
            for (DWORD index = 0; index < hash_size; ++index) {
              thumbprint.push_back(hexadecimal[(hash[index] >> 4) & 0x0F]);
              thumbprint.push_back(hexadecimal[hash[index] & 0x0F]);
            }
          }
        }
        CertFreeCertificateContext(certificate);
      }
    }
  }
  if (crypt_message != nullptr) CryptMsgClose(crypt_message);
  if (certificate_store != nullptr) CertCloseStore(certificate_store, 0);
  return thumbprint;
}

bool VerifySignatureAndSigner(const fs::path& file_path,
                              const std::wstring& expected_thumbprint) {
  if (!fs::is_regular_file(file_path) || !VerifyEmbeddedSignature(file_path)) {
    return false;
  }
  const std::wstring actual = EmbeddedSignerThumbprint(file_path);
  const std::wstring expected = NormalizeThumbprint(expected_thumbprint);
  return !actual.empty() && actual == expected;
}

void SynchronizeRuntimeFiles(const fs::path& root,
                             const std::wstring& version) {
  const fs::path version_root = root / L"versions" / version;
  const fs::path source_updater = version_root / L"updater";
  const fs::path target_updater = root / L"updater";
  std::error_code error;
  if (fs::is_directory(source_updater, error)) {
    const bool has_native_updater = fs::is_regular_file(
        source_updater / L"ysignage_updater.exe", error);
    fs::create_directories(target_updater, error);
    for (const auto& entry : fs::directory_iterator(source_updater, error)) {
      if (entry.is_regular_file(error)) {
        const std::wstring name = entry.path().filename().wstring();
        if (has_native_updater &&
            (name == L"update.ps1" || name == L"launcher.ps1" ||
             name == L"launcher.cmd")) {
          continue;
        }
        fs::copy_file(entry.path(), target_updater / entry.path().filename(),
                      fs::copy_options::overwrite_existing, error);
      }
    }
    if (has_native_updater) {
      fs::remove(root / L"launcher.ps1", error);
      fs::remove(root / L"SimpleKiosk.cmd", error);
      fs::remove(target_updater / L"update.ps1", error);
      fs::remove(target_updater / L"launcher.ps1", error);
      fs::remove(target_updater / L"launcher.cmd", error);
    }
  }

  for (const wchar_t* name : {L"USER_MANUAL.html", L"INSTALL_GUIDE.md",
                              L"MENU_CONFIG_GUIDE.md", L"RELEASE_NOTES.md"}) {
    CopyIfPresent(version_root / name, root / name);
  }
  fs::remove(root / L"USER_MANUAL.md", error);
}

int ShowFailure(const fs::path& root, const std::wstring& message) {
  AppendLog(root, message);
  MessageBoxW(nullptr, message.c_str(), L"여의도성당Signage 실행 오류",
              MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
  return 1;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  wchar_t module_path[MAX_PATH]{};
  const DWORD module_length = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (module_length == 0 || module_length == MAX_PATH) return 1;

  fs::path root = fs::path(module_path).parent_path();
  bool skip_sync = false;
  std::vector<std::wstring> forwarded_arguments;

  int argument_count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments != nullptr && argument_count == 4 &&
      std::wstring(arguments[1]) == L"--verify-signature") {
    const bool verified =
        VerifySignatureAndSigner(arguments[2], arguments[3]);
    LocalFree(arguments);
    return verified ? 0 : 3;
  }
  if (arguments != nullptr) {
    for (int index = 1; index < argument_count; ++index) {
      const std::wstring argument = arguments[index];
      if (argument == L"--data-root" && index + 1 < argument_count) {
        root = fs::absolute(arguments[++index]);
      } else if (argument == L"--skip-updater-sync") {
        skip_sync = true;
      } else {
        forwarded_arguments.push_back(argument);
      }
    }
    LocalFree(arguments);
  }

  const fs::path pointer_path = root / L"current.json";
  const std::string pointer = ReadTextFile(pointer_path);
  if (pointer.empty()) {
    return ShowFailure(root, L"현재 버전 정보가 없습니다: " +
                                pointer_path.wstring());
  }

  const std::vector<std::wstring> versions = {
      JsonString(pointer, "currentVersion"),
      JsonString(pointer, "previousVersion"),
  };
  for (const std::wstring& version : versions) {
    if (!IsSafeVersion(version)) continue;
    const fs::path version_root = root / L"versions" / version;
    fs::path executable = version_root / L"ysignage.exe";
    std::error_code error;
    if (!fs::is_regular_file(executable, error)) {
      executable = version_root / L"simple_kiosk.exe";
    }
    if (!fs::is_regular_file(executable, error)) {
      AppendLog(root, L"불완전한 버전: " + version);
      continue;
    }

    if (!skip_sync) SynchronizeRuntimeFiles(root, version);
    AppendLog(root, L"버전 " + version + L" 실행");
    SetEnvironmentVariableW(L"SIMPLE_KIOSK_DATA_DIR", root.c_str());

    std::wstring command_line = Quote(executable.wstring());
    for (const auto& argument : forwarded_arguments) {
      command_line += L" " + Quote(argument);
    }
    std::vector<wchar_t> mutable_command(command_line.begin(),
                                          command_line.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    const std::wstring working_directory = executable.parent_path().wstring();
    const BOOL started = CreateProcessW(
        executable.c_str(), mutable_command.data(), nullptr, nullptr, FALSE, 0,
        nullptr, working_directory.c_str(), &startup, &process);
    if (!started) {
      AppendLog(root, L"프로세스 시작 실패: " +
                          std::to_wstring(GetLastError()));
      continue;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
  }

  return ShowFailure(root, L"실행 가능한 현재 또는 이전 버전을 찾지 못했습니다.");
}
