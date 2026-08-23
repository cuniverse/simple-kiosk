[CmdletBinding()]
param(
    # CI에서는 GitHub Release 태그에서 추출한 버전을 전달한다.
    # 생략하면 기존처럼 pubspec.yaml의 version을 사용한다.
    [string]$PackageVersion,
    [string]$SigningCertificatePath,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$BuildInstaller,
    [string]$InnoCompilerPath,
    [string]$WebView2BootstrapperPath,
    [string]$VisualCppRedistributablePath
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Set-Location $projectDir

if ([string]::IsNullOrWhiteSpace($PackageVersion)) {
    $versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$'
    if (-not $versionLine) {
        throw 'pubspec.yaml에서 version을 찾을 수 없습니다.'
    }
    $PackageVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
}

$PackageVersion = $PackageVersion.Trim() -replace '^v', ''
if ($PackageVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "패키지 버전 형식이 올바르지 않습니다: $PackageVersion"
}

# '+'는 ZIP 파일명에서 빌드 메타데이터 구분 대신 '-'로 표현한다.
$archiveVersion = $PackageVersion.Replace('+', '-')
$packageName = "simple-kiosk-windows-$archiveVersion"
$distDir = Join-Path $projectDir 'dist'
$archive = Join-Path $distDir "$packageName.zip"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$stage = Join-Path $stageRoot $packageName
$pubspecPath = Join-Path $projectDir 'pubspec.yaml'
$originalPubspec = Get-Content -Raw -Encoding UTF8 $pubspecPath
$webView2BootstrapperUrl = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$visualCppRedistributableUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'

function Find-VisualCppRuntimeDirectory {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:VCToolsRedistDir)) {
        [void]$candidates.Add((Join-Path $env:VCToolsRedistDir 'x64'))
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $installations = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        foreach ($installation in $installations) {
            $redistRoot = Join-Path $installation 'VC\Redist\MSVC'
            if (Test-Path -LiteralPath $redistRoot) {
                Get-ChildItem -LiteralPath $redistRoot -Directory |
                    Sort-Object Name -Descending |
                    ForEach-Object { [void]$candidates.Add((Join-Path $_.FullName 'x64')) }
            }
        }
    }

    $runtimes = @()
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $runtimes += Get-ChildItem -LiteralPath $candidate -Directory -Filter 'Microsoft.VC*.CRT' |
            ForEach-Object {
                $runtimeDll = Join-Path $_.FullName 'vcruntime140.dll'
                if (Test-Path -LiteralPath $runtimeDll) {
                    $versionInfo = (Get-Item -LiteralPath $runtimeDll).VersionInfo
                    [pscustomobject]@{
                        Directory = $_.FullName
                        Version = [version]::new(
                            $versionInfo.FileMajorPart,
                            $versionInfo.FileMinorPart,
                            $versionInfo.FileBuildPart,
                            $versionInfo.FilePrivatePart)
                    }
                }
            }
    }
    $runtime = $runtimes | Sort-Object Version -Descending | Select-Object -First 1
    if ($runtime) { return $runtime }
    throw 'Visual C++ x64 재배포 DLL 폴더를 찾을 수 없습니다.'
}

function Find-EditBin {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio vswhere.exe를 찾을 수 없습니다.'
    }
    $installation = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $editBin = Get-ChildItem -LiteralPath (Join-Path $installation 'VC\Tools\MSVC') `
        -Filter editbin.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\Hostx64\\x64\\editbin\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $editBin) { throw 'x64 editbin.exe를 찾을 수 없습니다.' }
    return $editBin.FullName
}

function Assert-MicrosoftAuthenticodeSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Microsoft 서명 검증에 실패했습니다: $Path ($($signature.Status))"
    }
}

try {
    Write-Host "Package version: $PackageVersion"
    # 태그/인수 버전을 앱 런타임 버전에도 적용한다. 빌드 후 원본은 복원한다.
    $buildPubspec = $originalPubspec -replace '(?m)^version:\s*.+$', "version: $PackageVersion"
    [IO.File]::WriteAllText(
        $pubspecPath,
        $buildPubspec,
        [Text.UTF8Encoding]::new($false))
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 실패' }

    & (Join-Path $PSScriptRoot 'build-icons.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Windows 아이콘 생성 실패' }

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows 릴리스 빌드 실패' }

    $releaseCandidates = @(
        (Join-Path $projectDir 'build\windows\x64\runner\Release'),
        (Join-Path $projectDir 'build\windows\runner\Release')
    )
    $releaseDir = $releaseCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $releaseDir) {
        throw 'Windows Release 출력 폴더를 찾을 수 없습니다.'
    }

    # 관리자 권한이 없는 최초 PC와 포터블 실행을 위해 MSVC Runtime을 앱 로컬로 배포한다.
    $vcRuntime = Find-VisualCppRuntimeDirectory
    $vcRuntimeDir = $vcRuntime.Directory
    $vcRuntimeDlls = Get-ChildItem -LiteralPath $vcRuntimeDir -File -Filter '*.dll'
    if (-not $vcRuntimeDlls) {
        throw "Visual C++ Runtime DLL을 찾을 수 없습니다: $vcRuntimeDir"
    }
    $vcRuntimeDlls | Copy-Item -Destination $releaseDir -Force
    foreach ($requiredRuntime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $requiredRuntime))) {
            throw "필수 Visual C++ Runtime DLL 누락: $requiredRuntime"
        }
    }
    Write-Host "Bundled Visual C++ Runtime $($vcRuntime.Version): $vcRuntimeDir"

    # 업데이트 설치·재시작·롤백을 PowerShell 없이 처리하는 독립 실행 파일.
    $nativeUpdater = Join-Path $releaseDir 'ysignage_updater.exe'
    dart compile exe 'tool\windows_updater.dart' -o $nativeUpdater
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $nativeUpdater)) {
        throw '네이티브 Windows 업데이트 실행기 빌드 실패'
    }
    # Dart AOT EXE의 콘솔 창이 나타나지 않도록 PE 서브시스템을 GUI로 변경한다.
    $editBin = Find-EditBin
    & $editBin /SUBSYSTEM:WINDOWS $nativeUpdater
    if ($LASTEXITCODE -ne 0) { throw '네이티브 업데이트 실행기 GUI 변환 실패' }

    # 1.2.11 updater validates this legacy filename before extraction. Keep a
    # compatibility copy while the actual app and new launchers use ysignage.exe.
    $appExe = Join-Path $releaseDir 'ysignage.exe'
    if (-not (Test-Path -LiteralPath $appExe)) {
        throw 'ysignage.exe를 찾을 수 없습니다.'
    }
    Copy-Item -LiteralPath $appExe `
        -Destination (Join-Path $releaseDir 'simple_kiosk.exe') -Force

    if (-not [string]::IsNullOrWhiteSpace($SigningCertificatePath)) {
        if (-not (Test-Path -LiteralPath $SigningCertificatePath)) {
            throw "코드 서명 인증서를 찾을 수 없습니다: $SigningCertificatePath"
        }
        if ([string]::IsNullOrWhiteSpace($env:WINDOWS_SIGNING_CERT_PASSWORD)) {
            throw 'WINDOWS_SIGNING_CERT_PASSWORD 환경변수가 필요합니다.'
        }
        $signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
            -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if (-not $signTool) { throw 'signtool.exe를 찾을 수 없습니다.' }
        foreach ($targetName in @(
            'ysignage.exe',
            'simple_kiosk.exe',
            'ysignage_launcher.exe',
            'ysignage_updater.exe'
        )) {
            $targetExe = Join-Path $releaseDir $targetName
            if (-not (Test-Path -LiteralPath $targetExe)) {
                throw "코드 서명 대상이 없습니다: $targetName"
            }
            & $signTool.FullName sign /fd SHA256 /td SHA256 /tr $TimestampServer `
                /f $SigningCertificatePath /p $env:WINDOWS_SIGNING_CERT_PASSWORD $targetExe
            if ($LASTEXITCODE -ne 0) { throw "$targetName 코드 서명에 실패했습니다." }
            & $signTool.FullName verify /pa /v $targetExe
            if ($LASTEXITCODE -ne 0) { throw "$targetName 코드 서명 검증에 실패했습니다." }
        }
    }

    New-Item -ItemType Directory -Force -Path $stage, $distDir | Out-Null
    # 실행 테스트가 만든 WebView2 사용자 프로필(쿠키/캐시/세션)은 배포하지 않는다.
    Get-ChildItem -Path $releaseDir -File |
        Where-Object { $_.Name -ne 'ysignage_updater.exe' } |
        Copy-Item -Destination $stage -Force
    Copy-Item (Join-Path $releaseDir 'data') $stage -Recurse -Force
    Copy-Item 'release\guides\WINDOWS_INSTALL_GUIDE.md' (Join-Path $stage 'INSTALL_GUIDE.md')
    Copy-Item 'release\guides\MENU_CONFIGURATION_GUIDE.md' (Join-Path $stage 'MENU_CONFIG_GUIDE.md')
    dart run tool\build_user_manual.dart `
        docs\MANUAL.md (Join-Path $stage 'USER_MANUAL.html')
    if ($LASTEXITCODE -ne 0) { throw '사용자 매뉴얼 HTML 생성 실패' }
    Copy-Item 'RELEASE_NOTES.md' (Join-Path $stage 'RELEASE_NOTES.md')
    $updaterDir = Join-Path $stage 'updater'
    $updaterPayloadDir = Join-Path $updaterDir 'payload'
    New-Item -ItemType Directory -Force -Path $updaterDir, $updaterPayloadDir | Out-Null
    Copy-Item -LiteralPath $nativeUpdater `
        -Destination (Join-Path $updaterPayloadDir 'ysignage_updater.exe') -Force
    # 구버전(1.2.17 이하)이 이 릴리스를 한 번 설치할 수 있도록 전환용
    # 스크립트는 패키지에만 둔다. 네이티브 업데이트 성공 후 설치본에서 삭제된다.
    Copy-Item 'scripts\update.ps1' (Join-Path $updaterDir 'update.ps1')
    Copy-Item 'scripts\launcher.ps1' (Join-Path $updaterDir 'launcher.ps1')
    Copy-Item 'scripts\launcher.cmd' (Join-Path $updaterDir 'launcher.cmd')
    Copy-Item 'scripts\install-launcher.ps1' (Join-Path $updaterDir 'install-launcher.ps1')
    Copy-Item 'scripts\migrate-menu-config.ps1' (Join-Path $updaterDir 'migrate-menu-config.ps1')
    Copy-Item 'scripts\recover.ps1' (Join-Path $updaterDir 'recover.ps1')
    Copy-Item 'scripts\export-diagnostics.ps1' (Join-Path $updaterDir 'export-diagnostics.ps1')
    Copy-Item 'scripts\configure-installer.ps1' (Join-Path $updaterDir 'configure-installer.ps1')
    Copy-Item 'scripts\install-prerequisites.ps1' (Join-Path $updaterDir 'install-prerequisites.ps1')
    Copy-Item 'scripts\install-prerequisites.cmd' (Join-Path $stage 'InstallPrerequisites.cmd')

    $prerequisitesDir = Join-Path $stage 'prerequisites'
    New-Item -ItemType Directory -Force -Path $prerequisitesDir | Out-Null
    $webView2Bootstrapper = Join-Path $prerequisitesDir 'MicrosoftEdgeWebview2Setup.exe'
    if (-not [string]::IsNullOrWhiteSpace($WebView2BootstrapperPath)) {
        $resolvedBootstrapper = (Resolve-Path -LiteralPath $WebView2BootstrapperPath).Path
        Copy-Item -LiteralPath $resolvedBootstrapper -Destination $webView2Bootstrapper -Force
    } else {
        Write-Host 'Downloading Microsoft Edge WebView2 Evergreen Bootstrapper...'
        Invoke-WebRequest -UseBasicParsing -Uri $webView2BootstrapperUrl -OutFile $webView2Bootstrapper
    }
    Assert-MicrosoftAuthenticodeSignature $webView2Bootstrapper
    Write-Host 'Verified Microsoft signature: WebView2 Evergreen Bootstrapper'

    $packagedVcRedistributable = Join-Path $prerequisitesDir 'vc_redist.x64.exe'
    if (-not [string]::IsNullOrWhiteSpace($VisualCppRedistributablePath)) {
        $resolvedRedistributable = (Resolve-Path -LiteralPath $VisualCppRedistributablePath).Path
        Copy-Item -LiteralPath $resolvedRedistributable -Destination $packagedVcRedistributable -Force
    } else {
        Write-Host 'Downloading latest Microsoft Visual C++ Redistributable...'
        Invoke-WebRequest -UseBasicParsing -Uri $visualCppRedistributableUrl -OutFile $packagedVcRedistributable
    }
    Assert-MicrosoftAuthenticodeSignature $packagedVcRedistributable
    $vcRedistributableVersion = (Get-Item -LiteralPath $packagedVcRedistributable).VersionInfo.FileVersion
    Write-Host "Verified Microsoft signature: Visual C++ Redistributable $vcRedistributableVersion"

    $hashTargets = @(
        @{ Name = 'ysignage.exe'; Path = (Join-Path $stage 'ysignage.exe') },
        @{ Name = 'simple_kiosk.exe'; Path = (Join-Path $stage 'simple_kiosk.exe') },
        @{ Name = 'updater/payload/ysignage_updater.exe'; Path = (Join-Path $updaterPayloadDir 'ysignage_updater.exe') }
    )
    $hashLines = foreach ($target in $hashTargets) {
        $targetName = $target.Name
        $exe = $target.Path
        if (-not (Test-Path -LiteralPath $exe)) { throw "$targetName를 찾을 수 없습니다." }
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $targetName"
    }
    $hashLines | Set-Content -Encoding ascii (Join-Path $stage 'SHA256SUMS.txt')

    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal
    Write-Host "Created: $archive"

    if ($BuildInstaller) {
        if ([string]::IsNullOrWhiteSpace($InnoCompilerPath)) {
            $innoCandidates = @(
                (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
                (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
            )
            $InnoCompilerPath = $innoCandidates |
                Where-Object { Test-Path -LiteralPath $_ } |
                Select-Object -First 1
        }
        if ([string]::IsNullOrWhiteSpace($InnoCompilerPath) -or
            -not (Test-Path -LiteralPath $InnoCompilerPath)) {
            throw 'Inno Setup 6 ISCC.exe를 찾을 수 없습니다.'
        }
        & $InnoCompilerPath `
            "/DSourceDir=$stage" `
            "/DAppVersion=$PackageVersion" `
            "/DOutputDir=$distDir" `
            'scripts\simple-kiosk.iss'
        if ($LASTEXITCODE -ne 0) { throw 'Windows installer 생성 실패' }

        $installer = Join-Path $distDir "simple-kiosk-windows-setup-$archiveVersion.exe"
        if (-not (Test-Path -LiteralPath $installer)) {
            throw "생성된 installer를 찾을 수 없습니다: $installer"
        }
        if (-not [string]::IsNullOrWhiteSpace($SigningCertificatePath)) {
            & $signTool.FullName sign /fd SHA256 /td SHA256 /tr $TimestampServer `
                /f $SigningCertificatePath /p $env:WINDOWS_SIGNING_CERT_PASSWORD $installer
            if ($LASTEXITCODE -ne 0) { throw 'Windows installer 코드 서명 실패' }
            & $signTool.FullName verify /pa /v $installer
            if ($LASTEXITCODE -ne 0) { throw 'Windows installer 코드 서명 검증 실패' }
        }
        Write-Host "Created: $installer"
    }
}
finally {
    [IO.File]::WriteAllText(
        $pubspecPath,
        $originalPubspec,
        [Text.UTF8Encoding]::new($false))
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
}
