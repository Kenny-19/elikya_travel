; =====================================================================
;  Elikya Agents — installeur Windows (NSIS 3)
;  Construit par : node scripts/build-installer.js   (ne pas lancer à la main)
;  Paramètres reçus (/D) : VERSION, VERSION4, SRC (dossier Release Flutter), ICON,
;                          CRT (DLL du runtime Visual C++), OUTFILE
;  - Installation par utilisateur (pas besoin des droits administrateur)
;    dans %LOCALAPPDATA%\Programs\Elikya Agents
;  - Raccourcis menu Démarrer + bureau, entrée « Applications installées »
;  - Mise à jour : relancer un installeur plus récent par-dessus, ou à distance depuis l'app
;    (installation silencieuse /S : attend que l'app se ferme, installe, relance l'app)
;  - Désinstallation : les DONNÉES LOCALES (copie hors ligne + saisies en attente)
;    sont conservées, pour ne jamais perdre une saisie pas encore synchronisée.
; =====================================================================
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"

!define APP      "Elikya Agents"
!define EXE      "elikya_agents.exe"
!define PUBLISHER "Elikya Group"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ElikyaAgents"
; ICON est fourni par build-installer.js (agents\windows\runner\resources\app_icon.ico)

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${UNINST_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${PUBLISHER} · ${APP} ${VERSION}"

VIProductVersion "${VERSION4}"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileDescription" "Installation de ${APP}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${PUBLISHER}"

!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Installation de ${APP} ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Application de suivi d’activité des agents d’Elikya Group : voyage, caisse, mobile money, fourniture et clients.$\r$\n$\r$\nLa base en ligne est utilisée en priorité ; en cas de coupure internet, les saisies sont gardées sur ce poste et envoyées automatiquement au retour du réseau.$\r$\n$\r$\nCliquez sur Suivant pour continuer."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Lancer ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "French"

; L'application ne doit pas tourner pendant l'installation / la désinstallation
!macro FermerApp un
Function ${un}FermerApp
  StrCpy $2 0
  boucle:
    nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq ${EXE}" /NH | find /I "${EXE}"'
    Pop $0
    Pop $1
    ${If} $0 == 0
      ; mise à jour à distance (/S) : l'application est en train de se fermer, on attend jusqu'à 30 s
      ${If} ${Silent}
        IntOp $2 $2 + 1
        ${If} $2 < 30
          Sleep 1000
          Goto boucle
        ${EndIf}
        Abort
      ${EndIf}
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${APP} est ouvert.$\r$\nFermez l’application (bouton Quitter ou croix de la fenêtre), puis cliquez sur Réessayer." /SD IDCANCEL IDRETRY boucle
      Abort
    ${EndIf}
FunctionEnd
!macroend
!insertmacro FermerApp ""
!insertmacro FermerApp "un."

Section "Application" SecApp
  Call FermerApp
  SetOutPath "$INSTDIR"
  ; mise à jour : on remplace les fichiers de l'application (les données sont ailleurs)
  RMDir /r "$INSTDIR\data"
  File /r "${SRC}\*.*"
  ; runtime Visual C++ (indispensable sur un poste neuf), déployé à côté de l'exe
  File "${CRT}\msvcp140.dll"
  File "${CRT}\vcruntime140.dll"
  File "${CRT}\vcruntime140_1.dll"

  WriteUninstaller "$INSTDIR\Desinstaller.exe"
  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP}\Désinstaller ${APP}.lnk" "$INSTDIR\Desinstaller.exe"
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0

  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayName"     "${APP}"
  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr   HKCU "${UNINST_KEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayIcon"     "$INSTDIR\${EXE}"
  WriteRegStr   HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Desinstaller.exe"'
  WriteRegStr   HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Desinstaller.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  ; mise à jour à distance (installation silencieuse lancée par l'application) : on la relance
  IfSilent 0 +2
    Exec '"$INSTDIR\${EXE}"'
SectionEnd

Section "Uninstall"
  Call un.FermerApp
  Delete "$DESKTOP\${APP}.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UNINST_KEY}"
  ; Données locales conservées volontairement (voir en-tête)
  IfSilent +2
    MessageBox MB_ICONINFORMATION "${APP} a été désinstallé.$\r$\n$\r$\nLes données locales de ce poste (copie hors ligne et saisies en attente) sont conservées dans :$\r$\n$APPDATA\Elikya Group\Elikya Agents$\r$\n$\r$\nElles seront reprises si vous réinstallez l’application."
SectionEnd
