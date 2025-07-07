; LightScope Windows Installer Script
; This script creates a complete Windows installer for LightScope as a startup application

;--------------------------------
; General

!define PRODUCT_NAME "LightScope"
!define PRODUCT_VERSION "1.0.2"
!define PRODUCT_PUBLISHER "TheLightScope"
!define PRODUCT_WEB_SITE "https://thelightscope.com"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\lightscope.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKCU"

Name "${PRODUCT_NAME}"
OutFile "LightScope-${PRODUCT_VERSION}-Setup.exe"
InstallDir "$LOCALAPPDATA\LightScope"
InstallDirRegKey HKCU "${PRODUCT_DIR_REGKEY}" ""
ShowInstDetails show
ShowUnInstDetails show

; Request user level privileges only (no admin required)
RequestExecutionLevel user

; Modern UI
!include "MUI2.nsh"
!include "LogicLib.nsh"

; Interface Settings
!define MUI_ABORTWARNING

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Languages
!insertmacro MUI_LANGUAGE "English"

;--------------------------------
; Version Information
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "Comments" "Network Security Monitor"
VIAddVersionKey /LANG=${LANG_ENGLISH} "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "LegalCopyright" "© ${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileDescription" "${PRODUCT_NAME} Installer"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "InternalName" "lightscope"
VIAddVersionKey /LANG=${LANG_ENGLISH} "LegalTrademarks" ""
VIAddVersionKey /LANG=${LANG_ENGLISH} "OriginalFilename" "LightScope-${PRODUCT_VERSION}-Setup.exe"

;--------------------------------
; Functions

Function .onInit
  ; Check if already installed
  ReadRegStr $R0 ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString"
  StrCmp $R0 "" done
  
  MessageBox MB_YESNO "${PRODUCT_NAME} is already installed. Do you want to remove the previous version and continue?" IDYES uninst
  Abort
  
  ; Run the uninstaller
  uninst:
    ClearErrors
    ExecWait '$R0 _?=$INSTDIR' ; Do not copy the uninstaller to a temp file
    
    IfErrors no_remove_uninstaller done
      ; You can either use Delete /REBOOTOK in the uninstaller or add some code
      ; here to remove the uninstaller. Use a registry key to check
      ; whether the user has chosen to uninstall. If you are using an uninstaller
      ; components page, make sure all sections are uninstalled.
    no_remove_uninstaller:
      
  done:
FunctionEnd

Function CheckPython
  ; Check if Python is installed and accessible
  FileWrite $9 "Checking Python installation...$\r$\n"
  
  nsExec::ExecToLog 'python --version'
  Pop $0
  FileWrite $9 "Python version check exit code: $0$\r$\n"
  
  ${If} $0 != 0
    FileWrite $9 "Python 'python' command failed, trying 'py'...$\r$\n"
    nsExec::ExecToLog 'py --version'
    Pop $0
    FileWrite $9 "Python 'py' command exit code: $0$\r$\n"
    
    ${If} $0 != 0
      FileWrite $9 "Python 'py' command failed, trying 'python3'...$\r$\n"
      nsExec::ExecToLog 'python3 --version'
      Pop $0
      FileWrite $9 "Python 'python3' command exit code: $0$\r$\n"
      
      ${If} $0 != 0
        DetailPrint "ERROR: Python not found in PATH!"
        DetailPrint "Please install Python from https://python.org/downloads/"
        DetailPrint "Make sure to check 'Add Python to PATH' during installation"
        FileWrite $9 "ERROR: Python not found in PATH!$\r$\n"
        MessageBox MB_OK "Python not found! Please install Python from https://python.org/downloads/ and make sure to check 'Add Python to PATH' during installation."
        Abort
      ${Else}
        DetailPrint "✓ Python found via 'python3' command"
        FileWrite $9 "Python found via 'python3' command$\r$\n"
      ${EndIf}
    ${Else}
      DetailPrint "✓ Python found via 'py' command"
      FileWrite $9 "Python found via 'py' command$\r$\n"
    ${EndIf}
  ${Else}
    DetailPrint "✓ Python found via 'python' command"
    FileWrite $9 "Python found via 'python' command$\r$\n"
  ${EndIf}
FunctionEnd

Function CheckNpcap
  ; Check if Npcap is installed (REQUIRED - no fallbacks)
  FileWrite $9 "Checking Npcap installation...$\r$\n"
  
  ; Check for Npcap in System32
  IfFileExists "$WINDIR\System32\Npcap\wpcap.dll" npcap_found npcap_not_found
  
  npcap_not_found:
    DetailPrint "ERROR: Npcap is required but not found!"
    FileWrite $9 "ERROR: Npcap not found - REQUIRED for LightScope operation$\r$\n"
    
    ; Show error and offer to open download page
    MessageBox MB_YESNO "Npcap is REQUIRED for LightScope to function. Npcap was not found on your system. Would you like to open the Npcap download page now?" IDYES open_npcap_download
    
    ; User chose not to install Npcap
    MessageBox MB_OK "Installation cancelled. LightScope requires Npcap to function. Please install Npcap from https://nmap.org/npcap/ and run this installer again."
    Abort
    
    open_npcap_download:
      DetailPrint "Opening Npcap download page..."
      FileWrite $9 "Opening Npcap download page for user...$\r$\n"
      ExecShell "open" "https://nmap.org/npcap/"
      MessageBox MB_OK "Please install Npcap with WinPcap compatibility enabled, then restart this LightScope installer."
      Abort
  
  npcap_found:
    DetailPrint "✓ Npcap found and appears to be properly installed"
    FileWrite $9 "Npcap dependency check completed successfully$\r$\n"
FunctionEnd

;--------------------------------
; Installer Sections

Section "Core Files" SEC01
  SectionIn RO
  
  ; Create detailed installation log
  FileOpen $9 "$INSTDIR\lightscope-installation.log" w
  FileWrite $9 "=== LightScope Installation Log ===$\r$\n"
  FileWrite $9 "Installation started: $\r$\n"
  FileWrite $9 "Target directory: $INSTDIR$\r$\n"
  FileWrite $9 "Installation type: User-level startup application$\r$\n"
  FileWrite $9 "Windows version: "
  
  ; Get Windows version info
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "ProductName"
  FileWrite $9 "$R0$\r$\n"
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentVersion"
  FileWrite $9 "Windows version: $R0$\r$\n"
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuild"
  FileWrite $9 "Build: $R0$\r$\n"
  FileWrite $9 "$\r$\n"
  
  ; Check dependencies
  FileWrite $9 "=== Checking Dependencies ===$\r$\n"
  Call CheckPython
  Call CheckNpcap
  
  SetOutPath "$INSTDIR"
  SetOverwrite on
  
  FileWrite $9 "=== Installing Core Files ===$\r$\n"
  
  ; Install core files
  FileWrite $9 "Installing Python files...$\r$\n"
  File "lightscope_core.py"
  File "lightscope-runner-windows.py"
  File "lightscope-manager.py"
  File "lightscope-manager.bat"
  
  ; Install documentation
  IfFileExists "README-USER-INSTALLATION.md" install_readme skip_readme
  install_readme:
  File "README-USER-INSTALLATION.md"
  skip_readme:
  
  FileWrite $9 "Core files installed successfully$\r$\n"
  
  ; Create directories
  FileWrite $9 "Creating directories...$\r$\n"
  CreateDirectory "$INSTDIR\config"
  CreateDirectory "$INSTDIR\logs"
  CreateDirectory "$INSTDIR\updates"
  FileWrite $9 "Directories created successfully$\r$\n"
  
  ; Copy public key if available
  IfFileExists "lightscope-public.pem" copy_public_key skip_public_key
  copy_public_key:
  File "/oname=$INSTDIR\config\lightscope-public.pem" "lightscope-public.pem"
  skip_public_key:
  
  ; Create config file
  FileOpen $0 "$INSTDIR\config\config.ini" w
  FileWrite $0 "[DEFAULT]$\r$\n"
  FileWrite $0 "interface = auto$\r$\n"
  FileWrite $0 "upload_url = https://thelightscope.com/upload$\r$\n"
  FileWrite $0 "update_interval = 86400$\r$\n"
  FileWrite $0 "user_mode = true$\r$\n"
  FileClose $0
  
  ; Create Python virtual environment for LightScope
  DetailPrint "Creating Python virtual environment for LightScope..."
  FileWrite $9 "$\r$\n=== Creating Virtual Environment ===$\r$\n"
  
  ; Check Python version first
  FileWrite $9 "Checking Python installation...$\r$\n"
  nsExec::ExecToLog 'python --version'
  Pop $0
  FileWrite $9 "Python version check exit code: $0$\r$\n"
  
  ; Create virtual environment in the installation directory
  FileWrite $9 "Creating virtual environment with: python -m venv $\"$INSTDIR\venv$\"$\r$\n"
  nsExec::ExecToLog 'python -m venv "$INSTDIR\venv"'
  Pop $0
  FileWrite $9 "Virtual environment creation exit code: $0$\r$\n"
  ${If} $0 != 0
    FileWrite $9 "First attempt failed, trying python3...$\r$\n"
    nsExec::ExecToLog 'python3 -m venv "$INSTDIR\venv"'
    Pop $0
    FileWrite $9 "Python3 venv creation exit code: $0$\r$\n"
    ${If} $0 != 0
      FileWrite $9 "Second attempt failed, trying py...$\r$\n"
      nsExec::ExecToLog 'py -m venv "$INSTDIR\venv"'
      Pop $0
      FileWrite $9 "py venv creation exit code: $0$\r$\n"
      ${If} $0 != 0
        DetailPrint "ERROR: Failed to create virtual environment!"
        DetailPrint "Falling back to system Python installation..."
        FileWrite $9 "ERROR: Failed to create virtual environment! Falling back to system Python.$\r$\n"
        Goto system_python_install
      ${EndIf}
    ${EndIf}
  ${EndIf}
  
  ; Use virtual environment
  DetailPrint "✓ Virtual environment created successfully"
  FileWrite $9 "Virtual environment created successfully$\r$\n"
  
  ; Set up paths for virtual environment
  StrCpy $1 "$INSTDIR\venv\Scripts\python.exe"  ; venv Python executable
  StrCpy $2 "$INSTDIR\venv\Scripts\pip.exe"     ; venv pip executable
  
  ; Verify virtual environment Python
  FileWrite $9 "Verifying virtual environment Python...$\r$\n"
  nsExec::ExecToLog '"$1" --version'
  Pop $0
  FileWrite $9 "Virtual environment Python version check exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "ERROR: Virtual environment Python not working!"
    DetailPrint "Falling back to system Python installation..."
    FileWrite $9 "ERROR: Virtual environment Python not working! Falling back to system Python.$\r$\n"
    Goto system_python_install
  ${EndIf}
  
  DetailPrint "✓ Virtual environment Python verified"
  FileWrite $9 "Virtual environment Python verified$\r$\n"
  
  ; Install dependencies in virtual environment
  DetailPrint "Installing Python dependencies in virtual environment..."
  FileWrite $9 "$\r$\n=== Installing Dependencies ===$\r$\n"
  
  ; Update pip first
  FileWrite $9 "Updating pip...$\r$\n"
  nsExec::ExecToLog '"$2" install --upgrade pip'
  Pop $0
  FileWrite $9 "pip upgrade exit code: $0$\r$\n"
  
  ; Install core dependencies
  FileWrite $9 "Installing core dependencies...$\r$\n"
  nsExec::ExecToLog '"$2" install cryptography psutil requests dpkt'
  Pop $0
  FileWrite $9 "Core dependencies install exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "Warning: Some dependencies failed to install"
    FileWrite $9 "Warning: Some dependencies failed to install$\r$\n"
  ${Else}
    DetailPrint "✓ Core dependencies installed"
    FileWrite $9 "Core dependencies installed successfully$\r$\n"
  ${EndIf}
  
  ; Try to install Windows-specific dependencies (optional)
  FileWrite $9 "Installing Windows-specific dependencies...$\r$\n"
  nsExec::ExecToLog '"$2" install wmi pywin32'
  Pop $0
  FileWrite $9 "Windows dependencies install exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "Warning: Some Windows dependencies failed to install"
    FileWrite $9 "Warning: Some Windows dependencies failed to install$\r$\n"
  ${Else}
    DetailPrint "✓ Windows dependencies installed"
    FileWrite $9 "Windows dependencies installed successfully$\r$\n"
  ${EndIf}
  
  Goto install_complete
  
  system_python_install:
    DetailPrint "Using system Python installation..."
    FileWrite $9 "$\r$\n=== Using System Python ===$\r$\n"
    
    ; Use system Python
    StrCpy $1 "python"     ; system Python executable
    StrCpy $2 "pip"        ; system pip executable
    
    ; Test system Python
    FileWrite $9 "Testing system Python...$\r$\n"
    nsExec::ExecToLog '"$1" --version'
    Pop $0
    FileWrite $9 "System Python version check exit code: $0$\r$\n"
    ${If} $0 != 0
      ; Try py launcher
      StrCpy $1 "py"
      StrCpy $2 "py -m pip"
      nsExec::ExecToLog '"$1" --version'
      Pop $0
      FileWrite $9 "py launcher version check exit code: $0$\r$\n"
      ${If} $0 != 0
        DetailPrint "ERROR: No working Python installation found!"
        FileWrite $9 "ERROR: No working Python installation found!$\r$\n"
        MessageBox MB_OK "No working Python installation found! Please install Python from https://python.org/downloads/"
        Abort
      ${EndIf}
    ${EndIf}
    
    ; Install dependencies with system Python
    DetailPrint "Installing Python dependencies with system Python..."
    FileWrite $9 "Installing dependencies with system Python...$\r$\n"
    nsExec::ExecToLog '"$2" install --user cryptography psutil requests dpkt wmi pywin32'
    Pop $0
    FileWrite $9 "System Python dependencies install exit code: $0$\r$\n"
    ${If} $0 != 0
      DetailPrint "Warning: Some dependencies failed to install"
      FileWrite $9 "Warning: Some dependencies failed to install$\r$\n"
    ${Else}
      DetailPrint "✓ Dependencies installed with system Python"
      FileWrite $9 "Dependencies installed successfully with system Python$\r$\n"
    ${EndIf}
  
  install_complete:
  
  ; Create startup batch file
  DetailPrint "Creating startup script..."
  FileWrite $9 "$\r$\n=== Creating Startup Script ===$\r$\n"
  FileOpen $0 "$INSTDIR\start-lightscope.bat" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "cd /d $\"$INSTDIR$\"$\r$\n"
  
  ; Use virtual environment Python if available, otherwise system Python
  ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
    FileWrite $0 "$\"$INSTDIR\venv\Scripts\python.exe$\" $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $9 "Startup script configured to use virtual environment Python$\r$\n"
  ${Else}
    FileWrite $0 "python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $9 "Startup script configured to use system Python$\r$\n"
  ${EndIf}
  
  FileClose $0
  
  ; Add to Windows startup (current user only)
  DetailPrint "Adding LightScope to Windows startup..."
  FileWrite $9 "$\r$\n=== Adding to Windows Startup ===$\r$\n"
  
  ; Create startup shortcut
  CreateShortCut "$SMSTARTUP\LightScope.lnk" "$INSTDIR\start-lightscope.bat" "" "$INSTDIR\lightscope.ico" 0 SW_SHOWMINIMIZED
  FileWrite $9 "Startup shortcut created: $SMSTARTUP\LightScope.lnk$\r$\n"
  
  ; Also add registry entry for startup
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "LightScope" "$INSTDIR\start-lightscope.bat"
  FileWrite $9 "Registry startup entry added$\r$\n"
  
  DetailPrint "✓ LightScope added to Windows startup"
  DetailPrint "✓ LightScope will start automatically when you log in"
  
  ; Start LightScope immediately
  DetailPrint "Starting LightScope now..."
  FileWrite $9 "$\r$\n=== Starting LightScope ===$\r$\n"
  FileWrite $9 "Starting LightScope with: $INSTDIR\start-lightscope.bat$\r$\n"
  
  ; Start LightScope in the background
  ExecShell "open" "$INSTDIR\start-lightscope.bat" "" SW_HIDE
  
  DetailPrint "✓ LightScope started successfully"
  FileWrite $9 "LightScope started successfully$\r$\n"
  
  ; Close the log file
  FileWrite $9 "$\r$\n=== Installation Complete ===$\r$\n"
  FileWrite $9 "Installation type: User-level startup application$\r$\n"
  FileWrite $9 "No administrator privileges required$\r$\n"
  FileWrite $9 "Log file location: $INSTDIR\lightscope-installation.log$\r$\n"
  FileClose $9
  
  ; Show log file location to user
  DetailPrint "Installation log saved to: $INSTDIR\lightscope-installation.log"
  
SectionEnd

Section "Desktop Shortcut" SEC02
  CreateShortCut "$DESKTOP\LightScope.lnk" "$INSTDIR\start-lightscope.bat" "" "$INSTDIR\lightscope.ico"
SectionEnd

Section "Start Menu Shortcuts" SEC03
  CreateDirectory "$SMPROGRAMS\LightScope"
  CreateShortCut "$SMPROGRAMS\LightScope\LightScope.lnk" "$INSTDIR\start-lightscope.bat" "" "$INSTDIR\lightscope.ico"
  
  ; Create Python shortcuts for the manager
  ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
    CreateShortCut "$SMPROGRAMS\LightScope\Start LightScope.lnk" "$INSTDIR\venv\Scripts\python.exe" "$INSTDIR\lightscope-manager.py start"
    CreateShortCut "$SMPROGRAMS\LightScope\Stop LightScope.lnk" "$INSTDIR\venv\Scripts\python.exe" "$INSTDIR\lightscope-manager.py stop"
    CreateShortCut "$SMPROGRAMS\LightScope\Restart LightScope.lnk" "$INSTDIR\venv\Scripts\python.exe" "$INSTDIR\lightscope-manager.py restart"
    CreateShortCut "$SMPROGRAMS\LightScope\Status.lnk" "$INSTDIR\venv\Scripts\python.exe" "$INSTDIR\lightscope-manager.py status"
  ${Else}
    CreateShortCut "$SMPROGRAMS\LightScope\Start LightScope.lnk" "python" "$INSTDIR\lightscope-manager.py start"
    CreateShortCut "$SMPROGRAMS\LightScope\Stop LightScope.lnk" "python" "$INSTDIR\lightscope-manager.py stop"
    CreateShortCut "$SMPROGRAMS\LightScope\Restart LightScope.lnk" "python" "$INSTDIR\lightscope-manager.py restart"
    CreateShortCut "$SMPROGRAMS\LightScope\Status.lnk" "python" "$INSTDIR\lightscope-manager.py status"
  ${EndIf}
  
  CreateShortCut "$SMPROGRAMS\LightScope\Uninstall.lnk" "$INSTDIR\uninst.exe"
  CreateShortCut "$SMPROGRAMS\LightScope\View Logs.lnk" "$INSTDIR\logs\"
  CreateShortCut "$SMPROGRAMS\LightScope\Configuration.lnk" "$INSTDIR\config\"
  
  ; Add README shortcut if it exists
  ${If} ${FileExists} "$INSTDIR\README-USER-INSTALLATION.md"
    CreateShortCut "$SMPROGRAMS\LightScope\User Guide.lnk" "$INSTDIR\README-USER-INSTALLATION.md"
  ${EndIf}
SectionEnd

;--------------------------------
; Descriptions

LangString DESC_SecCore ${LANG_ENGLISH} "Core LightScope files and startup application installation"
LangString DESC_SecDesktop ${LANG_ENGLISH} "Desktop shortcut for LightScope"
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Start Menu shortcuts for LightScope"

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC01} $(DESC_SecCore)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC02} $(DESC_SecDesktop)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03} $(DESC_SecStartMenu)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

;--------------------------------
; Post-install

Section -Post
  WriteUninstaller "$INSTDIR\uninst.exe"
  WriteRegStr HKCU "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\lightscope-runner-windows.py"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayName" "$(^Name)"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninst.exe"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\lightscope.ico"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  
  ; Show final installation summary
  MessageBox MB_OK "LightScope Installation Complete! LightScope installed as startup application. No administrator privileges required. Will start automatically when you log in. LightScope is now running and monitoring your network. You can view logs and manage LightScope via Start Menu."
SectionEnd

;--------------------------------
; Uninstaller

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_OK "$(^Name) was successfully removed from your computer."
FunctionEnd

Function un.onInit
  MessageBox MB_YESNO "Are you sure you want to completely remove $(^Name) and all of its components?" IDYES continue_uninstall
  Abort
  continue_uninstall:
FunctionEnd

Section Uninstall
  ; Stop LightScope processes using the manager
  DetailPrint "Stopping LightScope processes..."
  
  ; Try to use the manager script first
  ${If} ${FileExists} "$INSTDIR\lightscope-manager.py"
    ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
      nsExec::ExecToLog '"$INSTDIR\venv\Scripts\python.exe" "$INSTDIR\lightscope-manager.py" stop'
    ${Else}
      nsExec::ExecToLog 'python "$INSTDIR\lightscope-manager.py" stop'
    ${EndIf}
  ${EndIf}
  
  ; Fallback to taskkill
  nsExec::ExecToLog 'taskkill /F /IM python.exe /FI "WINDOWTITLE eq LightScope*"'
  nsExec::ExecToLog 'taskkill /F /IM lightscope-runner-windows.py'
  
  ; Remove from startup
  Delete "$SMSTARTUP\LightScope.lnk"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "LightScope"
  
  ; Remove files
  Delete "$INSTDIR\uninst.exe"
  Delete "$INSTDIR\lightscope_core.py"
  Delete "$INSTDIR\lightscope-runner-windows.py"
  Delete "$INSTDIR\lightscope-manager.py"
  Delete "$INSTDIR\lightscope-manager.bat"
  Delete "$INSTDIR\start-lightscope.bat"
  Delete "$INSTDIR\README-USER-INSTALLATION.md"
  Delete "$INSTDIR\config\config.ini"
  Delete "$INSTDIR\config\lightscope-public.pem"
  
  ; Remove shortcuts
  Delete "$DESKTOP\LightScope.lnk"
  Delete "$SMPROGRAMS\LightScope\*.*"
  RMDir "$SMPROGRAMS\LightScope"
  
  ; Remove directories (only if empty)
  RMDir "$INSTDIR\config"
  RMDir /r "$INSTDIR\logs"
  RMDir /r "$INSTDIR\updates"
  RMDir /r "$INSTDIR\venv"
  RMDir "$INSTDIR"
  
  ; Remove registry keys
  DeleteRegKey ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}"
  DeleteRegKey HKCU "${PRODUCT_DIR_REGKEY}"
  
  SetAutoClose true
SectionEnd 
