# Windows 개발 환경 셋업 가이드

`flutter run -d windows` 를 처음 실행할 때 만나는 시행착오를 한 번에 해결하기 위한 체크리스트입니다.

자동화 스크립트: [scripts/setup-windows-dev.ps1](../scripts/setup-windows-dev.ps1) (관리자 권한 PowerShell에서 실행)

---

## 사전 요구사항

| 항목 | 비고 |
| --- | --- |
| Windows 10/11 (64-bit) | |
| Visual Studio 2019/2022 + "Desktop development with C++" 워크로드 | MSBuild + Windows 10 SDK 포함 |
| Flutter SDK (stable) | `flutter doctor` 로 확인 |
| Git | |

`flutter doctor -v` 가 모두 ✓ 인지 먼저 확인하세요.

---

## 1. Windows 개발자 모드 활성화 (심볼릭 링크 지원)

처음 빌드 시 다음 오류가 발생합니다:

```
Error: Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

Flutter는 플러그인 디렉터리를 `.plugin_symlinks` 로 연결하기 위해 심볼릭 링크를 사용합니다.
Windows는 기본적으로 관리자만 심볼릭 링크를 만들 수 있어, 일반 사용자가 빌드하려면 **개발자 모드**가 켜져 있어야 합니다.

설정 방법:

```powershell
start ms-settings:developers
```

→ "개발자 모드" 토글을 **켜기** → 확인 대화상자에서 **예**.

활성화 후 PowerShell 또는 VS Code 터미널을 **새로 여세요**.

---

## 2. NuGet CLI 설치 (`flutter_inappwebview_windows` 의존성)

이 프로젝트는 `flutter_inappwebview` 를 사용합니다. Windows 빌드 시 플러그인이 다음 패키지를
NuGet으로 자동 다운로드하기 때문에 `nuget.exe` 가 PATH에 있어야 합니다:

- `Microsoft.Windows.ImplementationLibrary`
- `Microsoft.Web.WebView2`
- `nlohmann.json`

`nuget.exe` 가 없으면 다음과 같은 빌드 실패가 발생합니다:

```
Nuget is not installed!
The flutter_inappwebview_windows plugin requires it.
... error MSB3073: NUGET-NOTFOUND install Microsoft.Web.WebView2 ...
```

### 설치 (택 1)

**A. winget (권장)**

```powershell
winget install --id Microsoft.NuGet -e --accept-source-agreements --accept-package-agreements
```

설치 위치 (예시):

```
C:\Users\<USER>\AppData\Local\Microsoft\WinGet\Packages\Microsoft.NuGet_Microsoft.Winget.Source_8wekyb3d8bbwe\nuget.exe
```

> winget이 PATH를 자동으로 갱신하지 않을 수 있습니다. 아래 [3. PATH 등록](#3-path-등록) 단계가 필요합니다.

**B. 수동 설치**

1. https://www.nuget.org/downloads 에서 `nuget.exe` (최신 권장 버전) 다운로드
2. 예: `C:\Tools\nuget\nuget.exe` 에 저장
3. 시스템 환경 변수 `Path` 에 `C:\Tools\nuget` 추가

**C. Chocolatey**

```powershell
choco install nuget.commandline
```

---

## 3. PATH 등록

winget으로 설치한 경우 사용자 `Path` 에 nuget 디렉터리를 영구 추가해야 합니다.

```powershell
$nugetDir = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter nuget.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1).Directory.FullName
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$nugetDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$nugetDir", 'User')
}
$env:Path = "$nugetDir;$env:Path"   # 현재 세션에도 즉시 반영
nuget help | Select-Object -First 2
```

> **중요**: PATH는 새 프로세스가 시작될 때만 읽힙니다. PATH 변경 후에는 **VS Code를 재시작**하거나 **새 터미널**을 열어야 `flutter` 가 새 PATH를 인식합니다.

---

## 4. WebView2 Runtime

Windows 11은 기본 포함되어 있지만, 일부 Windows 10 환경에서는 누락되어 있을 수 있습니다.
`flutter_inappwebview` Windows 구현은 WebView2 위에서 동작합니다.

```powershell
winget install --id Microsoft.EdgeWebView2Runtime -e
```

또는 Microsoft 공식 페이지에서 "Microsoft Edge WebView2 Runtime" 을 다운로드해 설치합니다.

---

## 5. 빌드 및 실행

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

첫 빌드는 NuGet 패키지 다운로드 + C++ 컴파일로 약 2~5분 소요됩니다 (네트워크/머신 사양에 따라).

성공 시 출력 예:

```
√ Built build\windows\x64\runner\Debug\ysignage.exe
```

---

## 6. 흔한 빌드 경고 (무시해도 되는 것)

- `CMake Warning ... CMP0175 is not set` — 플러그인의 CMakeLists 정책 경고. 빌드에 영향 없음.
- `warning C4819` (코드 페이지 949 관련) — `flutter_inappwebview_windows/utils/base64.cpp` 의 한국어 환경에서 발생. 빌드에 영향 없음.
- `warning C4244 / C4458` — WebView2 헤더 내 경고. 빌드에 영향 없음.

---

## 7. 문제 해결

### "Nuget is not installed" 가 또 뜬다

- nuget.exe 가 PATH 에 있는지 확인:
  ```powershell
  where.exe nuget
  ```
- 비어있다면 [2. NuGet CLI 설치](#2-nuget-cli-설치-flutter_inappwebview_windows-의존성) 부터 다시.
- 있는데도 실패하면 **VS Code 를 완전히 종료**한 뒤 다시 열어 (Code 프로세스 자체가 오래된 PATH 를 쓰는 경우).

### "Building with plugins requires symlink support"

- [1. 개발자 모드 활성화](#1-windows-개발자-모드-활성화-심볼릭-링크-지원) 미적용. 켠 후 새 터미널.

### "Unable to load asset: assets/idle/slide1.jpg"

- 런타임 경고. [assets/idle/](../assets/idle/) 폴더에 슬라이드 이미지가 없을 때 발생.
- 대기화면 이미지를 추가하거나, idle 설정을 비활성화하세요. 자세한 내용은 [docs/MANUAL.md](MANUAL.md#7-대기화면idle-screen) 참고.

### MSBuild 가 v180 (VS 2022/2026) 인데 빌드가 깨진다

- VS 의 "C++ 데스크톱 개발" 워크로드 + "Windows 10/11 SDK" 가 설치되어 있는지 확인:
  ```powershell
  flutter doctor -v
  ```

### 캐시가 꼬여서 이상한 동작을 한다

```powershell
flutter clean
Remove-Item -Recurse -Force build, .dart_tool -ErrorAction SilentlyContinue
flutter pub get
flutter run -d windows
```

---

## 참고 링크

- Flutter Windows 셋업: https://docs.flutter.dev/platform-integration/windows/install
- WebView2 런타임: https://developer.microsoft.com/microsoft-edge/webview2/
- flutter_inappwebview Windows 셋업: https://inappwebview.dev/docs/intro#setup-windows
- NuGet CLI: https://www.nuget.org/downloads
