; How to use:
;
; Prerequisites:
; - Download and install NSIS: http://nsis.sourceforge.net/Download
;
; 1. Build DCD (this assumes dcd-{server,client}.exe are in ..\..)
; 2. Edit the Version definition below to match DCD's version
; 3. Right click installer.nsi (this file) and choose "Compile NSIS Script"
; 4. Upload somewhere for the masses

SetCompressor /SOLID lzma

;--------------------------------------------------------
; Defines
;--------------------------------------------------------

; Options
!define Version "0.7.0"
!define DCDExecsPath "..\.."

;--------------------------------------------------------
; Includes
;--------------------------------------------------------

!include "MUI.nsh"
!include "EnvVarUpdate.nsh"

;--------------------------------------------------------
; General definitions
;--------------------------------------------------------

; Name of the installer
Name "DCD - D Completion Daemon ${Version}"

; Name of the output file of the installer
OutFile "DCD-${Version}-setup.exe"

; Where the program will be installed
InstallDir "$PROGRAMFILES\DCD"

; Take the installation directory from the registry, if possible
InstallDirRegKey HKLM "Software\DCD" ""

; Prevent installation of a corrupt installer
CRCCheck force

RequestExecutionLevel admin

;--------------------------------------------------------
; Interface settings
;--------------------------------------------------------

;!define MUI_ICON "installer-icon.ico"
;!define MUI_UNICON "uninstaller-icon.ico"

;--------------------------------------------------------
; Installer pages
;--------------------------------------------------------

;!define MUI_WELCOMEFINISHPAGE_BITMAP "banner.bmp"
;!define MUI_HEADERIMAGE
;!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------------------------------
; The languages
;--------------------------------------------------------

!insertmacro MUI_LANGUAGE "English"


;--------------------------------------------------------
; Required section: main program files,
; registry entries, etc.
;--------------------------------------------------------
;
Section "DCD" DCDFiles

    ; This section is mandatory
    SectionIn RO

    SetOutPath $INSTDIR

    ; Create installation directory
    CreateDirectory "$INSTDIR"

    File "${DCDExecsPath}\dcd-server.exe"
    File "${DCDExecsPath}\dcd-client.exe"

    ; Create command line batch file
    FileOpen $0 "$INSTDIR\dcdvars.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up environment for using DCD from %~dp0$\n"
    FileWrite $0 "@set PATH=%~dp0;%PATH%$\n"
    FileClose $0

    ; Write installation dir in the registry
    WriteRegStr HKLM SOFTWARE\DCD "Install_Dir" "$INSTDIR"

    ; Write registry keys to make uninstall from Windows
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DCD" "DisplayName" "DCD - The D Completion Daemon"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DCD" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DCD" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DCD" "NoRepair" 1
    WriteUninstaller "uninstall.exe"

SectionEnd

Section "Add to PATH" AddDCDToPath

    ; Add DCD directory to path (for all users)
    ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR"

SectionEnd

Section /o "Start menu shortcuts" StartMenuShortcuts
    CreateDirectory "$SMPROGRAMS\DCD"

    ; install DCD command prompt
    CreateShortCut "$SMPROGRAMS\DCD\DCD Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dcdvars.bat""' "" "" SW_SHOWNORMAL "" "Open DCD Command Prompt"

    CreateShortCut "$SMPROGRAMS\DCD\Uninstall.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\uninstall.exe" 0
SectionEnd

;--------------------------------------------------------
; Uninstaller
;--------------------------------------------------------

Section "Uninstall"

    ; Remove directories to path (for all users)
    ; (if for the current user, use HKCU)
    ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR"

    ; Remove stuff from registry
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DCD"
    DeleteRegKey HKLM SOFTWARE\DCD
    DeleteRegKey /ifempty HKLM SOFTWARE\DCD

    ; This is for deleting the remembered language of the installation
    DeleteRegKey HKCU Software\DCD
    DeleteRegKey /ifempty HKCU Software\DCD

    ; Remove the uninstaller
    Delete $INSTDIR\uninstall.exe

    ; Remove shortcuts
    Delete "$SMPROGRAMS\DCD\DCD Command Prompt.lnk"

    ; Remove used directories
    RMDir /r /REBOOTOK "$INSTDIR"
    RMDir /r /REBOOTOK "$SMPROGRAMS\DCD"

SectionEnd

