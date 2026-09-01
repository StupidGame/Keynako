#ifndef PackageRoot
  #error PackageRoot must point to the staged Keynako package.
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef BuildId
  #define BuildId "local"
#endif

#define ProductName "Keynako"
#define ProductVersion "1.0.0"
#define Publisher "Keynako contributors"
#define ImeClsid "F7959D5B-0818-43CC-9919-6AFA791730FC"

[Setup]
AppId={{{#ImeClsid}
AppName={#ProductName}
AppVersion={#ProductVersion}
AppPublisher={#Publisher}
DefaultDirName={autopf}\Keynako
DefaultGroupName={#ProductName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=KeynakoSetup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\apps\desktop\windows\runner\resources\app_icon.ico
UninstallDisplayName=Keynako Japanese IME
UninstallDisplayIcon={app}\Keynako.exe
UninstallFilesDir={app}\Uninstall
CloseApplications=force
CloseApplicationsFilter=Keynako.exe,keynako_zenzai.exe
RestartApplications=no

[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Excludes: "ime\KeynakoIME.dll,ime\zenzai\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageRoot}\ime\KeynakoIME.dll"; DestDir: "{app}\ime"; DestName: "KeynakoIME-{#BuildId}.dll"; Flags: ignoreversion uninsrestartdelete
Source: "{#PackageRoot}\ime\zenzai\*"; DestDir: "{app}\ime\zenzai"; Flags: ignoreversion onlyifdoesntexist recursesubdirs createallsubdirs
Source: "{#PackageRoot}\ime\bundled_shared_dictionary.tsv"; DestDir: "{commonappdata}\Keynako"; DestName: "shared_dictionary.tsv"; Flags: ignoreversion onlyifdoesntexist

[Dirs]
Name: "{commonappdata}\Keynako"; Permissions: users-modify

[Icons]
Name: "{group}\Keynako settings"; Filename: "{app}\Keynako.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall Keynako"; Filename: "{uninstallexe}"

[Run]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\ime\KeynakoIME-{#BuildId}.dll"""; Flags: runhidden waituntilterminated; StatusMsg: "Registering Keynako IME..."
Filename: "{app}\Keynako.exe"; Description: "Open Keynako settings"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s /u ""{app}\ime\KeynakoIME-{#BuildId}.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "UnregisterKeynakoIME"

[UninstallDelete]
Type: files; Name: "{commonappdata}\Keynako\shared_dictionary.tsv"
Type: dirifempty; Name: "{commonappdata}\Keynako"
Type: files; Name: "{localappdata}\Keynako\shared_dictionary.tsv"
Type: dirifempty; Name: "{localappdata}\Keynako"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := IsWin64;
  if not Result then
    MsgBox('Keynako IME requires 64-bit Windows.', mbError, MB_OK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if Exec(ExpandConstant('{sys}\taskkill.exe'),
          '/F /T /IM keynako_zenzai.exe', '', SW_HIDE,
          ewWaitUntilTerminated, ResultCode) then begin
    if ResultCode = 0 then
      Log('Stopped the running Keynako Zenzai helper before updating.')
    else
      Log('No running Keynako Zenzai helper needed to be stopped.');
  end else
    Log('Could not launch taskkill; Restart Manager will handle in-use files.');
  Sleep(250);
end;
