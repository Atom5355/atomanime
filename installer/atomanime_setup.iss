; ATOM ANIME Installer Script for Inno Setup

#define MyAppName "ATOM ANIME"
#define MyAppVersion "1.3.0"
#define MyAppPublisher "ATOM"
#define MyAppURL "https://github.com/atom/atomanime"
#define MyAppExeName "atomanime.exe"
#define MyAppAssocName "ATOM ANIME"
#define MyAppAssocExt ".atomanime"
#define MyAppAssocKey StringChange(MyAppAssocName, " ", "") + MyAppAssocExt

[Setup]
AppId={{A7B8C9D0-E1F2-3456-7890-ABCDEF123456}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename=ATOM_ANIME_Setup_v{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main application
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; Bundled Tools - yt-dlp
Source: "..\assets\yt-dlp\yt-dlp.exe"; DestDir: "{app}\tools\yt-dlp"; Flags: ignoreversion

; Bundled Tools - FFmpeg
Source: "..\assets\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"; DestDir: "{app}\tools\ffmpeg\bin"; Flags: ignoreversion
Source: "..\assets\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffprobe.exe"; DestDir: "{app}\tools\ffmpeg\bin"; Flags: ignoreversion skipifsourcedoesntexist

; Bundled Tools - RealESRGAN (optional - for upscaling)
Source: "..\assets\realesrgan\realesrgan-ncnn-vulkan-20220424-windows\*"; DestDir: "{app}\tools\realesrgan"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

; Bundled Tools - Waifu2x (optional - for upscaling)
Source: "..\assets\waifu2x\waifu2x-ncnn-vulkan-20220728-windows\*"; DestDir: "{app}\tools\waifu2x"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

; Bundled Tools - RIFE (optional - for frame interpolation)
Source: "..\assets\rife\rife-ncnn-vulkan-20221029-windows\*"; DestDir: "{app}\tools\rife"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
