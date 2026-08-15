#ifndef SourceDir
  #error SourceDir must be provided with /DSourceDir=<path>
#endif
#ifndef AppVersion
  #error AppVersion must be provided with /DAppVersion=<version>
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "Simple Kiosk"
#define AppExeName "simple_kiosk.exe"

[Setup]
AppId={{6C95C054-1458-4B4C-9458-1420CA590CA6}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Simple Kiosk
DefaultDirName={code:GetInstallDir}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=simple-kiosk-windows-setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=no
UninstallDisplayIcon={app}\versions\{#AppVersion}\{#AppExeName}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}

[Dirs]
Name: "{app}\config"
Name: "{app}\media"
Name: "{app}\state"
Name: "{app}\logs"
Name: "{app}\downloads"
Name: "{app}\updater"
Name: "{app}\versions"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}\versions\{#AppVersion}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\updater\launcher.ps1"; DestDir: "{app}"; DestName: "launcher.ps1"; Flags: ignoreversion
Source: "{#SourceDir}\updater\launcher.cmd"; DestDir: "{app}"; DestName: "SimpleKiosk.cmd"; Flags: ignoreversion
Source: "{#SourceDir}\updater\*"; DestDir: "{app}\updater"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{userstartup}\Simple Kiosk.lnk"
Type: files; Name: "{userstartup}\SimpleKiosk.lnk"

[Icons]
Name: "{group}\Simple Kiosk"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\versions\{#AppVersion}\{#AppExeName}"
Name: "{group}\Simple Kiosk 제거"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Simple Kiosk"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\versions\{#AppVersion}\{#AppExeName}"; Tasks: desktopicon
Name: "{userstartup}\Simple Kiosk"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\versions\{#AppVersion}\{#AppExeName}"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면 바로가기 만들기"; GroupDescription: "추가 바로가기:"; Flags: unchecked

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\updater\configure-installer.ps1"" -InstallRoot ""{app}"" -Version ""{#AppVersion}"""; Flags: runhidden waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\launcher.ps1"""; WorkingDir: "{app}"; Description: "Simple Kiosk 실행"; Flags: nowait postinstall skipifsilent

[Code]
var
  DeleteUserData: Boolean;

function GetInstallDir(Param: String): String;
var
  PreviousDir: String;
  UninstallKey: String;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6C95C054-1458-4B4C-9458-1420CA590CA6}_is1';
  if RegQueryStringValue(HKCU, UninstallKey, 'InstallLocation', PreviousDir) and
     DirExists(PreviousDir) then
    Result := RemoveBackslashUnlessRoot(PreviousDir)
  else if RegQueryStringValue(HKLM, UninstallKey, 'InstallLocation', PreviousDir) and
          DirExists(PreviousDir) then
    Result := RemoveBackslashUnlessRoot(PreviousDir)
  else
    Result := ExpandConstant('{localappdata}\Programs\SimpleKiosk');
end;

function InitializeUninstall(): Boolean;
begin
  DeleteUserData :=
    SuppressibleMsgBox(
      'Simple Kiosk 설정과 사용자 파일도 함께 삭제하시겠습니까?' + #13#10 + #13#10 +
      '예: config, media, state, logs, diagnostics, backups 삭제' + #13#10 +
      '아니요(권장): 프로그램만 삭제하고 설정과 사용자 파일 보존',
      mbConfirmation,
      MB_YESNO or MB_DEFBUTTON2,
      IDNO) = IDYES;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  InstallRoot: String;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;

  InstallRoot := ExpandConstant('{app}');

  { 자동 업데이트로 추가된 실행 파일과 캐시는 항상 제거한다. }
  DelTree(AddBackslash(InstallRoot) + 'versions', True, True, True);
  DelTree(AddBackslash(InstallRoot) + 'updater', True, True, True);
  DelTree(AddBackslash(InstallRoot) + 'downloads', True, True, True);
  DeleteFile(AddBackslash(InstallRoot) + 'launcher.ps1');
  DeleteFile(AddBackslash(InstallRoot) + 'SimpleKiosk.cmd');
  DeleteFile(AddBackslash(InstallRoot) + 'current.json');

  if DeleteUserData then
  begin
    DelTree(AddBackslash(InstallRoot) + 'config', True, True, True);
    DelTree(AddBackslash(InstallRoot) + 'media', True, True, True);
    DelTree(AddBackslash(InstallRoot) + 'state', True, True, True);
    DelTree(AddBackslash(InstallRoot) + 'logs', True, True, True);
    DelTree(AddBackslash(InstallRoot) + 'diagnostics', True, True, True);
    DelTree(AddBackslash(InstallRoot) + 'backups', True, True, True);
  end;

  { 알 수 없는 파일이 있으면 설치 루트는 안전하게 남긴다. }
  RemoveDir(InstallRoot);
end;
