; TinserBox installer (NSIS). Built by tools/build_windows.sh:
;   makensis -DVERSION=1.0.0 -DSRC=<app dir> -DICON=<icon.ico> -DOUT=<setup.exe> installer.nsi
; Program files go to the chosen install folder. User data (music, backgrounds, settings.cfg)
; lives in Documents\TinserBox, which TinserBox creates and seeds on first launch; the installer
; and uninstaller never touch it, so it survives updates and uninstalls.
Target amd64-unicode  ; native 64-bit installer (TinserBox is x64-only)
!include "MUI2.nsh"

Name "TinserBox"
OutFile "${OUT}"
InstallDir "$PROGRAMFILES64\TinserBox"
InstallDirRegKey HKLM "Software\TinserBox" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "TinserBox ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "TinserBox"
VIAddVersionKey "FileDescription" "TinserBox Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\TinserBox"
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\TinserBox.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Start TinserBox"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "TinserBox" SecApp
  SectionIn RO
  SetShellVarContext all
  SetOutPath "$INSTDIR"
  File "${SRC}\TinserBox.exe"
  File "${SRC}\TinserBoxMedia.exe"
  File "${SRC}\README.txt"
  ; Marks this as an installed copy: TinserBox then keeps user data in Documents\TinserBox.
  FileOpen $0 "$INSTDIR\installed.flag" w
  FileClose $0
  ; Bundled songs/backgrounds, copied to the user's library on first launch.
  SetOutPath "$INSTDIR\music"
  File /nonfatal "${SRC}\music\*.*"
  SetOutPath "$INSTDIR\backgrounds"
  File /nonfatal "${SRC}\backgrounds\*.*"
  SetOutPath "$INSTDIR"

  CreateShortcut "$SMPROGRAMS\TinserBox.lnk" "$INSTDIR\TinserBox.exe" "" "$INSTDIR\TinserBox.exe" 0
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\TinserBox" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "TinserBox"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\TinserBox.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "TinserBox"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  SetShellVarContext all
  CreateShortcut "$DESKTOP\TinserBox.lnk" "$INSTDIR\TinserBox.exe" "" "$INSTDIR\TinserBox.exe" 0
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "TinserBox music player (required)."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "Add a TinserBox shortcut to the desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetShellVarContext all
  ; Only installed files are removed; Documents\TinserBox (user music, backgrounds, settings) is kept.
  Delete "$INSTDIR\TinserBox.exe"
  Delete "$INSTDIR\TinserBoxMedia.exe"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\installed.flag"
  RMDir /r "$INSTDIR\music"
  RMDir /r "$INSTDIR\backgrounds"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\TinserBox.lnk"
  Delete "$DESKTOP\TinserBox.lnk"
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "Software\TinserBox"
SectionEnd
