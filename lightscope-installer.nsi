; LightScope Windows Installer Script
; This script creates a complete Windows installer for LightScope

;--------------------------------
; General

!define PRODUCT_NAME "LightScope"
!define PRODUCT_VERSION "0.0.102"
!define PRODUCT_PUBLISHER "TheLightScope"
!define PRODUCT_WEB_SITE "https://thelightscope.com"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\lightscope.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"

Name "${PRODUCT_NAME}"
OutFile "LightScope-${PRODUCT_VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES\LightScope"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" ""
ShowInstDetails show
ShowUnInstDetails show

; Request administrator privileges
RequestExecutionLevel admin

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
  
  ; MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "${PRODUCT_NAME} is already installed.\n\nClick OK to remove the previous version or Cancel to abort." IDOK uninst
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
  ; Important message about Python PATH requirement
  DetailPrint "Checking Python Installation..."
  FileWrite $9 "=== Python Dependency Check ===$\r$\n"
  
  ; Check if Python is installed by trying to run it
  ClearErrors
  
  ; Try to run python command to check if it's available
  FileWrite $9 "Testing 'python --version' command...$\r$\n"
  nsExec::ExecToStack 'python --version'
  Pop $0 ; exit code
  Pop $1 ; output
  FileWrite $9 "Python check exit code: $0, output: $1$\r$\n"
  
  ; If python command worked, check if it's version 3.8+
  ${If} $0 == 0
    ; Python found via 'python' command
    DetailPrint "Found Python via 'python' command: $1"
    FileWrite $9 "Python found successfully: $1$\r$\n"
    Goto python_found
  ${EndIf}
  
  ; Try python3 command
  FileWrite $9 "Testing 'python3 --version' command...$\r$\n"
  nsExec::ExecToStack 'python3 --version'
  Pop $0 ; exit code
  Pop $1 ; output
  FileWrite $9 "Python3 check exit code: $0, output: $1$\r$\n"
  
  ${If} $0 == 0
    ; Python found via 'python3' command
    DetailPrint "Found Python via 'python3' command: $1"
    FileWrite $9 "Python3 found successfully: $1$\r$\n"
    Goto python_found
  ${EndIf}
  
  ; Try to find Python in common installation paths
  IfFileExists "$LOCALAPPDATA\Programs\Python\Python38\python.exe" python_found
  IfFileExists "$LOCALAPPDATA\Programs\Python\Python39\python.exe" python_found
  IfFileExists "$LOCALAPPDATA\Programs\Python\Python310\python.exe" python_found
  IfFileExists "$LOCALAPPDATA\Programs\Python\Python311\python.exe" python_found
  IfFileExists "$LOCALAPPDATA\Programs\Python\Python312\python.exe" python_found
  IfFileExists "$PROGRAMFILES\Python38\python.exe" python_found
  IfFileExists "$PROGRAMFILES\Python39\python.exe" python_found
  IfFileExists "$PROGRAMFILES\Python310\python.exe" python_found
  IfFileExists "$PROGRAMFILES\Python311\python.exe" python_found
  IfFileExists "$PROGRAMFILES\Python312\python.exe" python_found
  
  ; Check registry as fallback
  ClearErrors
  ReadRegStr $0 HKLM "SOFTWARE\Python\PythonCore\3.8\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKLM "SOFTWARE\Python\PythonCore\3.9\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKLM "SOFTWARE\Python\PythonCore\3.10\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKLM "SOFTWARE\Python\PythonCore\3.11\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKLM "SOFTWARE\Python\PythonCore\3.12\InstallPath" ""
  IfErrors 0 python_found
  
  ; Check HKCU registry for user installations
  ReadRegStr $0 HKCU "SOFTWARE\Python\PythonCore\3.8\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKCU "SOFTWARE\Python\PythonCore\3.9\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKCU "SOFTWARE\Python\PythonCore\3.10\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKCU "SOFTWARE\Python\PythonCore\3.11\InstallPath" ""
  IfErrors 0 python_found
  ReadRegStr $0 HKCU "SOFTWARE\Python\PythonCore\3.12\InstallPath" ""
  IfErrors 0 python_found
  
  ; Python not found
  DetailPrint "ERROR: Python 3.8+ is required but not found!"
  FileWrite $9 "ERROR: Python not found after all checks!$\r$\n"
  MessageBox MB_YESNO "Python required. Install now?" IDYES download_python IDNO skip_python
  
  download_python:
    DetailPrint "Opening Python download page..."
    FileWrite $9 "Opening Python download page for user...$\r$\n"
    ExecShell "open" "https://www.python.org/downloads/"
    
    python_retry_loop:
      MessageBox MB_YESNOCANCEL "Install Python with PATH option. Done?" IDYES recheck_python IDNO skip_python IDCANCEL abort_install
      
    recheck_python:
      ; Clear errors and recheck Python installation
      ClearErrors
      nsExec::ExecToStack 'python --version'
      Pop $0
      ${If} $0 == 0
        DetailPrint "Python successfully detected after installation!"
        Goto python_found
      ${EndIf}
      
      ; Try python3 command
      nsExec::ExecToStack 'python3 --version'
      Pop $0
      ${If} $0 == 0
        DetailPrint "Python3 successfully detected after installation!"
        Goto python_found
      ${EndIf}
      
      ; Still not found, show retry option
      MessageBox MB_YESNO "Python not found. Try again?" IDYES python_retry_loop IDNO skip_python
      
    abort_install:
      Abort
  
  skip_python:
    MessageBox MB_YESNO "Python required. Continue anyway?" IDYES python_found IDNO download_python
  
  python_found:
    DetailPrint "Python found and appears to be in PATH - excellent!"
    FileWrite $9 "Python dependency check completed successfully$\r$\n"
FunctionEnd

Function CheckNpcap
  ; Important message about Npcap compatibility requirement
  DetailPrint "Checking Npcap Installation..."
  FileWrite $9 "=== Npcap Dependency Check ===$\r$\n"
  
  ; Check if Npcap is installed
  FileWrite $9 "Checking for Npcap files in system directories...$\r$\n"
  IfFileExists "$SYSDIR\wpcap.dll" npcap_found 0
  IfFileExists "$SYSDIR\Packet.dll" npcap_found 0
  IfFileExists "$SYSDIR\Npcap\wpcap.dll" npcap_found 0
  FileWrite $9 "Npcap files not found in standard locations$\r$\n"
  
  ; Npcap not found
  DetailPrint "ERROR: Npcap is required but not found!"
  FileWrite $9 "ERROR: Npcap not found after all checks!$\r$\n"
  MessageBox MB_YESNO "Npcap required. Install now?" IDYES download_npcap IDNO skip_npcap
  
  download_npcap:
    DetailPrint "Opening Npcap download page..."
    FileWrite $9 "Opening Npcap download page for user...$\r$\n"
    ExecShell "open" "https://nmap.org/npcap/"
    
    npcap_retry_loop:
      MessageBox MB_YESNOCANCEL "Install Npcap with WinPcap compatibility. Done?" IDYES recheck_npcap IDNO skip_npcap IDCANCEL abort_install_npcap
      
    recheck_npcap:
      ; Clear errors and recheck Npcap installation
      ClearErrors
      IfFileExists "$SYSDIR\wpcap.dll" npcap_found_after_install 0
      IfFileExists "$SYSDIR\Packet.dll" npcap_found_after_install 0
      IfFileExists "$SYSDIR\Npcap\wpcap.dll" npcap_found_after_install 0
      
      ; Still not found, show retry option
      MessageBox MB_YESNO "Npcap not found. Try again?" IDYES npcap_retry_loop IDNO skip_npcap
      
    npcap_found_after_install:
      DetailPrint "Npcap successfully detected after installation!"
      Goto npcap_found
      
    abort_install_npcap:
      Abort
  
  skip_npcap:
    MessageBox MB_OK "Npcap required for LightScope."
  
  npcap_found:
    DetailPrint "Npcap found and appears to be properly installed - excellent!"
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
  File "lightscope-service-windows.py"
  File "lightscope-runner-windows.py"
  FileWrite $9 "Core files installed successfully$\r$\n"
  
  ; Create directories
  FileWrite $9 "Creating directories...$\r$\n"
  CreateDirectory "$INSTDIR\bin"
  CreateDirectory "$INSTDIR\config"
  CreateDirectory "$INSTDIR\logs"
  CreateDirectory "$INSTDIR\updates"
  FileWrite $9 "Directories created successfully$\r$\n"
  
  ; Copy files to bin directory
  CopyFiles "$INSTDIR\lightscope_core.py" "$INSTDIR\bin\"
  CopyFiles "$INSTDIR\lightscope-service-windows.py" "$INSTDIR\bin\"
  CopyFiles "$INSTDIR\lightscope-runner-windows.py" "$INSTDIR\bin\"
  
  ; Also keep copies in root directory for flexibility
  ; (in case scripts look in root directory instead of bin)
  File "/oname=$INSTDIR\lightscope_core.py" "lightscope_core.py"
  File "/oname=$INSTDIR\lightscope-service-windows.py" "lightscope-service-windows.py"
  File "/oname=$INSTDIR\lightscope-runner-windows.py" "lightscope-runner-windows.py"
  
  ; Copy public key if available
  IfFileExists "lightscope-public.pem" 0 +2
  File "/oname=$INSTDIR\config\lightscope-public.pem" "lightscope-public.pem"
  
  ; Create config file
  FileOpen $0 "$INSTDIR\config\config.ini" w
  FileWrite $0 "[DEFAULT]$\r$\n"
  FileWrite $0 "interface = auto$\r$\n"
  FileWrite $0 "upload_url = https://thelightscope.com/upload$\r$\n"
  FileWrite $0 "update_interval = 86400$\r$\n"
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
      DetailPrint "ERROR: Failed to create virtual environment!"
      DetailPrint "Falling back to system Python installation..."
      FileWrite $9 "ERROR: Failed to create virtual environment! Falling back to system Python.$\r$\n"
      Goto system_python_install
    ${EndIf}
  ${EndIf}
  
  DetailPrint "✓ Virtual environment created successfully"
  FileWrite $9 "Virtual environment created successfully$\r$\n"
  
  ; Use virtual environment Python for all subsequent operations
  StrCpy $1 "$INSTDIR\venv\Scripts\python.exe"
  StrCpy $2 "$INSTDIR\venv\Scripts\pip.exe"
  FileWrite $9 "Virtual environment Python: $1$\r$\n"
  FileWrite $9 "Virtual environment pip: $2$\r$\n"
  
  ; Verify virtual environment
  FileWrite $9 "Verifying virtual environment Python...$\r$\n"
  nsExec::ExecToLog '"$1" --version'
  Pop $0
  FileWrite $9 "Virtual environment Python verification exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "ERROR: Virtual environment Python not working!"
    DetailPrint "Falling back to system Python installation..."
    FileWrite $9 "ERROR: Virtual environment Python not working! Falling back to system Python.$\r$\n"
    Goto system_python_install
  ${EndIf}
  
  ; Install Python dependencies in virtual environment
  DetailPrint "Installing Python dependencies in virtual environment..."
  
  ; Upgrade pip in virtual environment
  nsExec::ExecToLog '"$2" install --upgrade pip'
  Pop $0
  
  Goto venv_python_install
  
  system_python_install:
  DetailPrint "Using system Python installation..."
  FileWrite $9 "$\r$\n=== Using System Python ===$\r$\n"
  StrCpy $1 "python"
  StrCpy $2 "python -m pip"
  FileWrite $9 "System Python executable: $1$\r$\n"
  FileWrite $9 "System pip command: $2$\r$\n"
  
  ; Try different Python commands to install packages
  FileWrite $9 "Testing system Python pip...$\r$\n"
  nsExec::ExecToLog 'python -m pip install --upgrade pip'
  Pop $0
  FileWrite $9 "System Python pip upgrade exit code: $0$\r$\n"
  ${If} $0 != 0
    FileWrite $9 "System python failed, trying python3...$\r$\n"
    nsExec::ExecToLog 'python3 -m pip install --upgrade pip'
    Pop $0
    FileWrite $9 "Python3 pip upgrade exit code: $0$\r$\n"
    StrCpy $1 "python3"
    StrCpy $2 "python3 -m pip"
    FileWrite $9 "Updated to use python3$\r$\n"
  ${EndIf}
  
  venv_python_install:
  
  ; Install pywin32 first (required for Windows services)
  DetailPrint "Installing pywin32 for Windows service support..."
  FileWrite $9 "$\r$\n=== Installing pywin32 ===$\r$\n"
  FileWrite $9 "Using Python: $1$\r$\n"
  FileWrite $9 "Using pip: $2$\r$\n"
  
  ; First, uninstall any existing pywin32 to ensure clean installation
  FileWrite $9 "Uninstalling existing pywin32...$\r$\n"
  nsExec::ExecToLog '"$2" uninstall -y pywin32'
  Pop $0
  FileWrite $9 "pywin32 uninstall exit code: $0$\r$\n"
  
  ; Install pywin32 with verbose output
  FileWrite $9 "Installing pywin32...$\r$\n"
  nsExec::ExecToLog '"$2" install --upgrade --force-reinstall --no-cache-dir pywin32'
  Pop $0
  FileWrite $9 "pywin32 install exit code: $0$\r$\n"
  
  ; Verify pywin32 installation
  DetailPrint "Verifying pywin32 installation..."
  FileWrite $9 "Verifying pywin32 basic import...$\r$\n"
  nsExec::ExecToLog '"$1" -c "import win32api; print($\'pywin32 basic import successful$\')"'
  Pop $0
  FileWrite $9 "pywin32 basic import exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "ERROR: pywin32 basic import failed!"
    FileWrite $9 "ERROR: pywin32 basic import failed!$\r$\n"
  ${Else}
    DetailPrint "✓ pywin32 basic import successful"
    FileWrite $9 "pywin32 basic import successful$\r$\n"
  ${EndIf}
  
  ; Run pywin32 post-install script (critical for service functionality)
  DetailPrint "Configuring pywin32 for Windows services..."
  FileWrite $9 "$\r$\n=== Running pywin32 post-install ===$\r$\n"
  
  ; Try multiple methods to run the post-install script
  FileWrite $9 "Method 1: Direct script execution...$\r$\n"
  nsExec::ExecToLog '"$1" "$INSTDIR\venv\Scripts\pywin32_postinstall.py" -install'
  Pop $0
  FileWrite $9 "Method 1 exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "First post-install attempt failed, trying alternative methods..."
    FileWrite $9 "Method 1 failed, trying method 2...$\r$\n"
    
    ; Try from Python prefix/Scripts
    FileWrite $9 "Method 2: sys.prefix Scripts directory...$\r$\n"
    nsExec::ExecToLog '"$1" -c "import sys, os; script = os.path.join(sys.prefix, $\'Scripts$\', $\'pywin32_postinstall.py$\'); exec(open(script).read())" -install'
    Pop $0
    FileWrite $9 "Method 2 exit code: $0$\r$\n"
    ${If} $0 != 0
      FileWrite $9 "Method 2 failed, trying method 3...$\r$\n"
      ; Try from site-packages
      FileWrite $9 "Method 3: site-packages directory...$\r$\n"
      nsExec::ExecToLog '"$1" -c "import sys, os; script = os.path.join(sys.prefix, $\'Lib$\', $\'site-packages$\', $\'pywin32_postinstall.py$\'); exec(open(script).read())" -install'
      Pop $0
      FileWrite $9 "Method 3 exit code: $0$\r$\n"
      ${If} $0 != 0
        FileWrite $9 "Method 3 failed, trying method 4...$\r$\n"
        ; Try direct execution
        FileWrite $9 "Method 4: Direct module import...$\r$\n"
        nsExec::ExecToLog '"$1" -c "import pywin32_postinstall; pywin32_postinstall.install()"'
        Pop $0
        FileWrite $9 "Method 4 exit code: $0$\r$\n"
        ${If} $0 != 0
          DetailPrint "WARNING: All pywin32 post-install attempts failed!"
          DetailPrint "Service installation may not work. You may need to run manually:"
          DetailPrint "python Scripts/pywin32_postinstall.py -install"
          FileWrite $9 "ERROR: All pywin32 post-install methods failed!$\r$\n"
        ${Else}
          DetailPrint "✓ pywin32 post-install successful (method 4)"
          FileWrite $9 "pywin32 post-install successful (method 4)$\r$\n"
        ${EndIf}
      ${Else}
        DetailPrint "✓ pywin32 post-install successful (method 3)"
        FileWrite $9 "pywin32 post-install successful (method 3)$\r$\n"
      ${EndIf}
    ${Else}
      DetailPrint "✓ pywin32 post-install successful (method 2)"
      FileWrite $9 "pywin32 post-install successful (method 2)$\r$\n"
    ${EndIf}
  ${Else}
    DetailPrint "✓ pywin32 post-install successful (method 1)"
    FileWrite $9 "pywin32 post-install successful (method 1)$\r$\n"
  ${EndIf}
  
  ; Final verification of service modules
  DetailPrint "Verifying Windows service modules..."
  FileWrite $9 "$\r$\n=== Verifying Service Modules ===$\r$\n"
  FileWrite $9 "Testing servicemanager import...$\r$\n"
  nsExec::ExecToLog '"$1" -c "import servicemanager; print($\'servicemanager imported successfully$\')"'
  Pop $0
  FileWrite $9 "servicemanager import exit code: $0$\r$\n"
  
  FileWrite $9 "Testing win32service import...$\r$\n"
  nsExec::ExecToLog '"$1" -c "import win32service; print($\'win32service imported successfully$\')"'
  Pop $0
  FileWrite $9 "win32service import exit code: $0$\r$\n"
  
  FileWrite $9 "Testing win32serviceutil import...$\r$\n"
  nsExec::ExecToLog '"$1" -c "import win32serviceutil; print($\'win32serviceutil imported successfully$\')"'
  Pop $0
  FileWrite $9 "win32serviceutil import exit code: $0$\r$\n"
  
  FileWrite $9 "Testing all service modules together...$\r$\n"
  nsExec::ExecToLog '"$1" -c "import servicemanager, win32service, win32serviceutil; print($\'All service modules imported successfully$\')"'
  Pop $0
  FileWrite $9 "All service modules import exit code: $0$\r$\n"
  ${If} $0 != 0
    DetailPrint "ERROR: Service modules still not available after installation!"
    DetailPrint "Manual fix required: python Scripts/pywin32_postinstall.py -install"
    FileWrite $9 "ERROR: Service modules still not available after installation!$\r$\n"
  ${Else}
    DetailPrint "✓ All Windows service modules available"
    FileWrite $9 "All Windows service modules available$\r$\n"
  ${EndIf}
  
  ; Install other dependencies
  DetailPrint "Installing other Python dependencies..."
  nsExec::ExecToLog '"$2" install cryptography psutil requests dpkt'
  Pop $0
  ${If} $0 != 0
    DetailPrint "Warning: Failed to install some Python dependencies. You may need to install them manually: pip install cryptography psutil requests dpkt"
  ${EndIf}
  
  ; Install and configure the service for automatic startup
  DetailPrint "Installing LightScope Windows service (will start automatically at boot)..."
  FileWrite $9 "$\r$\n=== Installing Windows Service ===$\r$\n"
  FileWrite $9 "Service installation command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" install$\r$\n"
  nsExec::ExecToLog '"$1" "$INSTDIR\bin\lightscope-service-windows.py" install'
  Pop $0
  FileWrite $9 "Service installation exit code: $0$\r$\n"
  ${If} $0 == 0
    DetailPrint "✓ LightScope service installed successfully and configured for automatic startup"
    FileWrite $9 "LightScope service installed successfully$\r$\n"
  ${Else}
    DetailPrint "✗ Warning: Failed to install service. You may need to install it manually as Administrator"
    DetailPrint "  Manual command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" install"
    FileWrite $9 "ERROR: Failed to install service. Exit code: $0$\r$\n"
    FileWrite $9 "Manual command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" install$\r$\n"
  ${EndIf}
  
  ; Start the service immediately
  DetailPrint "Starting LightScope service now..."
  FileWrite $9 "$\r$\n=== Starting Windows Service ===$\r$\n"
  FileWrite $9 "Service start command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" start$\r$\n"
  nsExec::ExecToLog '"$1" "$INSTDIR\bin\lightscope-service-windows.py" start'
  Pop $0
  FileWrite $9 "Service start exit code: $0$\r$\n"
  ${If} $0 == 0
    DetailPrint "✓ LightScope service started successfully"
    DetailPrint "✓ LightScope is now running and will start automatically on system boot"
    FileWrite $9 "LightScope service started successfully$\r$\n"
  ${Else}
    DetailPrint "✗ Warning: Failed to start service immediately"
    DetailPrint "  The service is installed and will start automatically on next boot"
    DetailPrint "  Manual command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" start"
    FileWrite $9 "WARNING: Failed to start service immediately. Exit code: $0$\r$\n"
    FileWrite $9 "Manual command: $\"$1$\" $\"$INSTDIR\bin\lightscope-service-windows.py$\" start$\r$\n"
  ${EndIf}
  
  ; Close the log file
  FileWrite $9 "$\r$\n=== Installation Complete ===$\r$\n"
  FileWrite $9 "Log file location: $INSTDIR\lightscope-installation.log$\r$\n"
  FileClose $9
  
  ; Show log file location to user
  DetailPrint "Installation log saved to: $INSTDIR\lightscope-installation.log"
  
SectionEnd

Section "Desktop Shortcut" SEC02
  CreateShortCut "$DESKTOP\LightScope.lnk" "$INSTDIR\bin\lightscope-service-windows.py" "start" "$INSTDIR\lightscope.ico"
SectionEnd

Section "Start Menu Shortcuts" SEC03
  CreateDirectory "$SMPROGRAMS\LightScope"
  CreateShortCut "$SMPROGRAMS\LightScope\LightScope.lnk" "$INSTDIR\bin\lightscope-service-windows.py" "start" "$INSTDIR\lightscope.ico"
  CreateShortCut "$SMPROGRAMS\LightScope\Start LightScope.lnk" "$INSTDIR\bin\lightscope-service-windows.py" "start"
  CreateShortCut "$SMPROGRAMS\LightScope\Stop LightScope.lnk" "$INSTDIR\bin\lightscope-service-windows.py" "stop"
  CreateShortCut "$SMPROGRAMS\LightScope\Restart LightScope.lnk" "$INSTDIR\bin\lightscope-service-windows.py" "restart"
  CreateShortCut "$SMPROGRAMS\LightScope\Uninstall.lnk" "$INSTDIR\uninst.exe"
  CreateShortCut "$SMPROGRAMS\LightScope\View Logs.lnk" "$INSTDIR\logs\"
SectionEnd

;--------------------------------
; Descriptions

LangString DESC_SecCore ${LANG_ENGLISH} "Core LightScope files and service installation"
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
  WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\bin\lightscope-service-windows.py"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayName" "$(^Name)"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninst.exe"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\lightscope.ico"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  
  ; Show final installation summary
  ; MessageBox MB_OK|MB_ICONINFORMATION "LightScope Installation Complete!\n\n✓ LightScope service is installed and configured\n✓ Service will start automatically when Windows boots\n✓ Service is now running and monitoring your network\n\nYou can view logs in: $INSTDIR\\logs\\\nManage service via Start Menu: LightScope"
SectionEnd

;--------------------------------
; Uninstaller

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_ICONINFORMATION|MB_OK "$(^Name) was successfully removed from your computer."
FunctionEnd

Function un.onInit
  MessageBox MB_ICONQUESTION|MB_YESNO|MB_DEFBUTTON2 "Are you sure you want to completely remove $(^Name) and all of its components?" IDYES +2
  Abort
FunctionEnd

Section Uninstall
  ; Stop and remove the service
  ExecWait 'python "$INSTDIR\bin\lightscope-service-windows.py" stop'
  ExecWait 'python "$INSTDIR\bin\lightscope-service-windows.py" uninstall'
  
  ; Remove files
  Delete "$INSTDIR\uninst.exe"
  Delete "$INSTDIR\bin\lightscope_core.py"
  Delete "$INSTDIR\bin\lightscope-service-windows.py"
  Delete "$INSTDIR\bin\lightscope-runner-windows.py"
  Delete "$INSTDIR\lightscope_core.py"
  Delete "$INSTDIR\lightscope-service-windows.py"
  Delete "$INSTDIR\lightscope-runner-windows.py"
  Delete "$INSTDIR\config\config.ini"
  Delete "$INSTDIR\config\lightscope-public.pem"
  
  ; Remove shortcuts
  Delete "$DESKTOP\LightScope.lnk"
  Delete "$SMPROGRAMS\LightScope\*.*"
  RMDir "$SMPROGRAMS\LightScope"
  
  ; Remove directories (only if empty)
  RMDir "$INSTDIR\bin"
  RMDir "$INSTDIR\config"
  RMDir /r "$INSTDIR\logs"
  RMDir /r "$INSTDIR\updates"
  RMDir "$INSTDIR"
  
  ; Remove registry keys
  DeleteRegKey ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}"
  DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
  
  SetAutoClose true
SectionEnd 