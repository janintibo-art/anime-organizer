; Installateur Windows d'Anime Organizer, compilé par Inno Setup 6 dans le
; workflow GitHub. La version arrive de la ligne de commande :
;   ISCC /DAppVersion=1.42.0 installer\anime_organizer.iss
; Les chemins sont relatifs à ce fichier, d'où les « ..\ ».

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Anime Organizer"
#define AppExe "anime_organizer.exe"
#define AppRepo "https://github.com/janintibo-art/anime-organizer"

[Setup]
; Identifiant fixe : c'est lui qui permet à une nouvelle version de
; remplacer l'ancienne au même endroit au lieu de s'installer à côté.
; Propre à cette application — ne jamais le changer, ni le réutiliser.
AppId={{F6F37135-0D1C-4451-B404-24666BEAFE43}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=janintibo-art
AppPublisherURL={#AppRepo}
AppSupportURL={#AppRepo}/issues
AppUpdatesURL={#AppRepo}/actions

; Installation pour soi seul par défaut, sans droits administrateur ;
; l'assistant propose aussi « pour tous les utilisateurs ». {autopf} vaut
; alors Program Files, ou le dossier Programmes de l'utilisateur.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir=..\dist
OutputBaseFilename=AnimeOrganizer-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; On ferme l'application si elle tourne avant de remplacer ses fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Tout le dossier Release : l'exécutable, les DLL de Flutter et de
; media_kit, le dossier data, et les trois DLL Visual C++ que le workflow
; y a copiées — sans elles l'application ne démarre pas sur un PC neuf.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; La bibliothèque, les réglages et l'index hors connexion vivent dans le
; dossier de données de l'utilisateur, pas ici : ils sont conservés, et
; une réinstallation les retrouve.
