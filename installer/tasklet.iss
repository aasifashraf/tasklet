; Inno Setup script for the Tasklet Windows installer.
; Build: flutter build windows --release, package into dist\Tasklet (see tasklet-release skill), then
;   ISCC.exe /DAppVersion=1.0.1 installer\tasklet.iss

#ifndef AppVersion
  #define AppVersion "1.0.1"
#endif

[Setup]
AppId={{8C3E2B6A-5F1D-4C7E-9A2B-3D4E5F6A7B8C}
AppName=Tasklet
AppVersion={#AppVersion}
AppVerName=Tasklet {#AppVersion}
AppPublisher=Tasklet contributors
AppPublisherURL=https://github.com/aasifashraf/tasklet
AppSupportURL=https://github.com/aasifashraf/tasklet/issues
AppUpdatesURL=https://github.com/aasifashraf/tasklet/releases
DefaultDirName={autopf}\Tasklet
DefaultGroupName=Tasklet
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
; Installs for the current user without admin rights; the user can choose all-users instead.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Tasklet-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Tasklet.exe
UninstallDisplayName=Tasklet
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
; Ask to close a running Tasklet (it keeps running in the tray) before installing or uninstalling.
AppMutex=Tasklet.SingleInstance
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\dist\Tasklet\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The AppUserModelID matches the one notifications use, so reminders show "Tasklet" as the sender.
Name: "{autoprograms}\Tasklet"; Filename: "{app}\Tasklet.exe"; AppUserModelID: "Tasklet.Tasklet.Desktop"
Name: "{autodesktop}\Tasklet"; Filename: "{app}\Tasklet.exe"; AppUserModelID: "Tasklet.Tasklet.Desktop"; Tasks: desktopicon

[Run]
Filename: "{app}\Tasklet.exe"; Description: "{cm:LaunchProgram,Tasklet}"; Flags: nowait postinstall skipifsilent
