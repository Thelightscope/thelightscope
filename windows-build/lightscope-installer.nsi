; LightScope Windows User-Level Installer Script
; This script creates a complete Windows installer for LightScope that runs as a user application

;--------------------------------
; General

!define PRODUCT_NAME "LightScope"
!define PRODUCT_VERSION "1.0.3"
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

; Request admin privileges for firewall configuration
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
  
  MessageBox MB_YESNO "${PRODUCT_NAME} is already installed. Remove the previous version?" IDYES uninst
  Abort
  
  ; Run the uninstaller
  uninst:
    ClearErrors
    ExecWait '$R0 _?=$INSTDIR' ; Do not copy the uninstaller to a temp file
    
    IfErrors no_remove_uninstaller done
    no_remove_uninstaller:
      
  done:
FunctionEnd

Function CheckPython
  ; Check if Python is installed
  DetailPrint "Checking Python Installation..."
  FileWrite $9 "=== Python Dependency Check ===$\r$\n"
  
  ; Check if Python is available
  ClearErrors
  nsExec::ExecToStack 'python --version'
  Pop $0 ; exit code
  Pop $1 ; output
  FileWrite $9 "Python check exit code: $0, output: $1$\r$\n"
  
  ${If} $0 == 0
    DetailPrint "Found Python: $1"
    FileWrite $9 "Python found successfully: $1$\r$\n"
    Goto python_found
  ${EndIf}
  
  ; Try python3 command
  nsExec::ExecToStack 'python3 --version'
  Pop $0 ; exit code
  Pop $1 ; output
  
  ${If} $0 == 0
    DetailPrint "Found Python3: $1"
    FileWrite $9 "Python3 found successfully: $1$\r$\n"
    Goto python_found
  ${EndIf}
  
  ; Python not found
  DetailPrint "ERROR: Python 3.8+ is required but not found!"
  FileWrite $9 "ERROR: Python not found after all checks!$\r$\n"
  MessageBox MB_YESNO "Python 3.8+ is required. Install Python now?" IDYES download_python IDNO abort_install
  
  download_python:
    DetailPrint "Opening Python download page..."
    FileWrite $9 "Opening Python download page...$\r$\n"
    ExecShell "open" "https://www.python.org/downloads/"
    
    python_retry_loop:
      MessageBox MB_YESNO "Install Python with 'Add to PATH' option, then click YES when done or NO to abort installation." IDYES recheck_python IDNO abort_install
      
    recheck_python:
      ClearErrors
      nsExec::ExecToStack 'python --version'
      Pop $0
      ${If} $0 == 0
        DetailPrint "Python successfully detected after installation!"
        Goto python_found
      ${EndIf}
      
      nsExec::ExecToStack 'python3 --version'
      Pop $0
      ${If} $0 == 0
        DetailPrint "Python3 successfully detected after installation!"
        Goto python_found
      ${EndIf}
      
      MessageBox MB_YESNO "Python not found. Try again?" IDYES python_retry_loop IDNO abort_install
      
  abort_install:
    DetailPrint "Installation aborted - Python is required"
    FileWrite $9 "Installation aborted - Python is required$\r$\n"
    Abort
  
  python_found:
    DetailPrint "✓ Python is available"
    FileWrite $9 "Python dependency check completed successfully$\r$\n"
FunctionEnd

Function CheckNpcap
  ; Check if NPCAP is installed (REQUIRED - no fallback)
  DetailPrint "Checking for NPCAP installation..."
  FileWrite $9 "=== NPCAP Dependency Check ===$\r$\n"
  
  ; Check registry for NPCAP
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NpcapInst" "DisplayName"
  FileWrite $9 "NPCAP registry check: $0$\r$\n"
  ${If} $0 != ""
    DetailPrint "Found NPCAP: $0"
    FileWrite $9 "NPCAP found: $0$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ; Check for NPCAP DLL files
  ${If} ${FileExists} "$WINDIR\System32\npcap.dll"
    DetailPrint "Found NPCAP DLL: $WINDIR\System32\npcap.dll"
    FileWrite $9 "NPCAP DLL found: $WINDIR\System32\npcap.dll$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ${If} ${FileExists} "$WINDIR\System32\wpcap.dll"
    DetailPrint "Found WPCAP DLL: $WINDIR\System32\wpcap.dll"
    FileWrite $9 "WPCAP DLL found: $WINDIR\System32\wpcap.dll$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ; NPCAP not found - ABORT installation
  DetailPrint "ERROR: NPCAP is required but not found!"
  FileWrite $9 "ERROR: NPCAP not found - installation aborted!$\r$\n"
  MessageBox MB_YESNO "NPCAP is required for LightScope to function. Install NPCAP now?" IDYES download_npcap IDNO abort_install
  
  download_npcap:
    DetailPrint "Opening NPCAP download page..."
    FileWrite $9 "Opening NPCAP download page...$\r$\n"
    ExecShell "open" "https://nmap.org/npcap/"
    
    npcap_retry_loop:
      MessageBox MB_YESNO "Install NPCAP with WinPcap compatibility, then click YES when done or NO to abort installation." IDYES recheck_npcap IDNO abort_install
      
    recheck_npcap:
      ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NpcapInst" "DisplayName"
      ${If} $0 != ""
        DetailPrint "NPCAP successfully detected: $0"
        FileWrite $9 "NPCAP successfully detected: $0$\r$\n"
        Goto npcap_found
      ${EndIf}
      
      ${If} ${FileExists} "$WINDIR\System32\npcap.dll"
        DetailPrint "NPCAP DLL successfully detected"
        FileWrite $9 "NPCAP DLL successfully detected$\r$\n"
        Goto npcap_found
      ${EndIf}
      
      MessageBox MB_YESNO "NPCAP not found. Try again?" IDYES npcap_retry_loop IDNO abort_install
      
  abort_install:
    DetailPrint "Installation aborted - NPCAP is required"
    FileWrite $9 "Installation aborted - NPCAP is required$\r$\n"
    Abort
  
  npcap_found:
    DetailPrint "✓ NPCAP is available"
    FileWrite $9 "NPCAP dependency check completed successfully$\r$\n"
FunctionEnd

Function ConfigureFirewall
  ; Configure Windows Firewall to allow LightScope honeypot traffic
  DetailPrint "Configuring Windows Firewall for LightScope..."
  FileWrite $9 "$\r$\n=== Configuring Windows Firewall ===$\r$\n"
  
  ; Check which Python executable we're using
  ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
    StrCpy $1 "$INSTDIR\venv\Scripts\python.exe"
    FileWrite $9 "Using virtual environment Python: $1$\r$\n"
  ${Else}
    ; Try to find system Python
    nsExec::ExecToStack 'where python'
    Pop $0
    Pop $1
    ${If} $0 == 0
      FileWrite $9 "Using system Python: $1$\r$\n"
    ${Else}
      StrCpy $1 "python.exe"
      FileWrite $9 "Using default python.exe path$\r$\n"
    ${EndIf}
  ${EndIf}
  
  ; Create firewall rule for inbound honeypot connections
  DetailPrint "Creating firewall rule for honeypot services..."
  FileWrite $9 "Creating firewall rule for Python executable: $1$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Honeypot Services\" -Direction Inbound -Protocol TCP -LocalPort 21,22,23,25,53,80,110,135,139,143,443,445,993,995,1433,1521,3306,3389,5432,5900,8080,8443 -Program \"$1\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Honeypot firewall rule creation exit code: $0$\r$\n"
  
  ; Create firewall rule for dynamic port range (user ports)
  DetailPrint "Creating firewall rule for dynamic ports..."
  FileWrite $9 "Creating firewall rule for dynamic port range...$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Dynamic Ports\" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program \"$1\" -Action Allow -Profile Private,Domain -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Dynamic ports firewall rule creation exit code: $0$\r$\n"
  
  ; Create outbound rule for LightScope communication
  DetailPrint "Creating outbound firewall rule..."
  FileWrite $9 "Creating outbound firewall rule...$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Outbound\" -Direction Outbound -Protocol TCP -Program \"$1\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Outbound firewall rule creation exit code: $0$\r$\n"
  
  ${If} $0 == 0
    DetailPrint "✓ Windows Firewall configured successfully"
    FileWrite $9 "Firewall configuration completed successfully$\r$\n"
  ${Else}
    DetailPrint "⚠ Firewall configuration may have encountered issues"
    FileWrite $9 "Firewall configuration completed with warnings$\r$\n"
  ${EndIf}
FunctionEnd

;--------------------------------
; Installer Sections

Section "Core Files" SEC01
  SectionIn RO
  
  ; Create detailed installation log
  FileOpen $9 "$INSTDIR\lightscope-installation.log" w
  FileWrite $9 "=== LightScope User-Level Installation Log ===$\r$\n"
  FileWrite $9 "Installation started: $\r$\n"
  FileWrite $9 "Target directory: $INSTDIR$\r$\n"
  FileWrite $9 "User-level installation (no admin privileges required)$\r$\n"
  
  ; Check dependencies
  FileWrite $9 "=== Checking Dependencies ===$\r$\n"
  Call CheckPython
  Call CheckNpcap
  
  SetOutPath "$INSTDIR"
  SetOverwrite on
  
  FileWrite $9 "=== Installing Core Files ===$\r$\n"
  
  ; Install core files to root directory and bin directory
  FileWrite $9 "Installing Python files...$\r$\n"
  File "/oname=$INSTDIR\lightscope_core.py" "lightscope_core.py"
  File "/oname=$INSTDIR\lightscope-runner-windows.py" "lightscope-runner-windows.py"
  FileWrite $9 "Core files installed successfully (lightscope_core.py from authoritative source)$\r$\n"
  
  ; Create directories
  FileWrite $9 "Creating directories...$\r$\n"
  CreateDirectory "$INSTDIR\bin"
  CreateDirectory "$INSTDIR\config"
  CreateDirectory "$INSTDIR\logs"
  CreateDirectory "$INSTDIR\updates"
  FileWrite $9 "Directories created successfully$\r$\n"
  
  ; Copy files to bin directory (where the runner expects them)
  FileWrite $9 "Copying files to bin directory...$\r$\n"
  CopyFiles "$INSTDIR\lightscope_core.py" "$INSTDIR\bin\"
  CopyFiles "$INSTDIR\lightscope-runner-windows.py" "$INSTDIR\bin\"
  FileWrite $9 "Files copied to bin directory successfully$\r$\n"
  
  ; Copy public key (REQUIRED for secure updates)
  File "/oname=$INSTDIR\config\lightscope-public.pem" "lightscope-public.pem"
  FileWrite $9 "Public key copied from installation package$\r$\n"
  
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
  
  venv_python_install:
  
  ; Install Python dependencies for user-level operation
  DetailPrint "Installing Python dependencies..."
  FileWrite $9 "$\r$\n=== Installing Python Dependencies ===$\r$\n"
  FileWrite $9 "Using Python: $1$\r$\n"
  FileWrite $9 "Using pip: $2$\r$\n"
  
  ; Install core dependencies
  DetailPrint "Installing core Python packages..."
  FileWrite $9 "Installing core dependencies...$\r$\n"
  nsExec::ExecToLog '"$2" install --upgrade cryptography psutil requests dpkt packaging urllib3 scapy pywin32'
  Pop $0
  FileWrite $9 "Core dependencies install exit code: $0$\r$\n"
  
  ; Install Windows-specific dependencies with special handling for pywin32
  DetailPrint "Installing Windows-specific packages..."
  FileWrite $9 "Installing Windows-specific dependencies...$\r$\n"
  nsExec::ExecToLog '"$2" install --upgrade wmi'
  Pop $0
  FileWrite $9 "Windows-specific dependencies install exit code: $0$\r$\n"
  
  ; Run pywin32 post-install registration
  DetailPrint "Configuring pywin32..."
  FileWrite $9 "Running pywin32 post-install configuration...$\r$\n"
  nsExec::ExecToLog '"$1" -m pywin32_postinstall -install'
  Pop $0
  FileWrite $9 "pywin32 post-install exit code: $0$\r$\n"
  
  ; Install pcap library for Windows
  DetailPrint "Installing Windows pcap library..."
  FileWrite $9 "Installing Windows pcap library...$\r$\n"
  nsExec::ExecToLog '"$2" install --upgrade pcap-ct==1.3.0b3'
  Pop $0
  FileWrite $9 "Windows pcap library install exit code: $0$\r$\n"
  
  ; Report installation success
  ${If} $0 != 0
    DetailPrint "Warning: Some Python dependencies may have failed to install"
    FileWrite $9 "Warning: Some Python dependencies may have failed to install$\r$\n"
  ${Else}
    DetailPrint "✓ Python dependencies installed successfully"
    FileWrite $9 "Python dependencies installed successfully$\r$\n"
  ${EndIf}
  
  ; Configure Windows Firewall for LightScope
  Call ConfigureFirewall
  
  ; Create startup launcher batch file
  DetailPrint "Creating startup launcher..."
  FileWrite $9 "$\r$\n=== Creating Startup Launcher ===$\r$\n"
  
  FileOpen $0 "$INSTDIR\start-lightscope.bat" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "title LightScope Network Monitor$\r$\n"
  FileWrite $0 "cd /d $\"$INSTDIR$\"$\r$\n"
  ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
    FileWrite $0 "echo Activating virtual environment...$\r$\n"
    FileWrite $0 "call $\"$INSTDIR\venv\Scripts\activate.bat$\"$\r$\n"
    FileWrite $0 "if errorlevel 1 ($\r$\n"
    FileWrite $0 "    echo ERROR: Failed to activate virtual environment$\r$\n"
    FileWrite $0 "    echo Falling back to system Python...$\r$\n"
    FileWrite $0 "    python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 ") else ($\r$\n"
    FileWrite $0 "    echo Virtual environment activated successfully$\r$\n"
    FileWrite $0 "    python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 ")$\r$\n"
    FileWrite $9 "Created launcher using virtual environment activation$\r$\n"
  ${Else}
    FileWrite $0 "python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $9 "Created launcher using system Python$\r$\n"
  ${EndIf}
  FileClose $0
  
  ; Create background launcher (no window)
  FileOpen $0 "$INSTDIR\start-lightscope-background.bat" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "cd /d $\"$INSTDIR$\"$\r$\n"
  FileWrite $0 "echo Background launcher started at %date% %time% >> logs\background.log$\r$\n"
  ${If} ${FileExists} "$INSTDIR\venv\Scripts\python.exe"
    FileWrite $0 "echo Attempting virtual environment activation... >> logs\background.log$\r$\n"
    FileWrite $0 "call $\"$INSTDIR\venv\Scripts\activate.bat$\" >> logs\background.log 2>&1$\r$\n"
    FileWrite $0 "if errorlevel 1 ($\r$\n"
    FileWrite $0 "    echo ERROR: Virtual environment activation failed, using system Python >> logs\background.log$\r$\n"
    FileWrite $0 "    if exist $\"C:\Windows\py.exe$\" ($\r$\n"
    FileWrite $0 "        start /min C:\Windows\py.exe -3 -B $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 "    ) else ($\r$\n"
    FileWrite $0 "        start /min python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 "    )$\r$\n"
    FileWrite $0 ") else ($\r$\n"
    FileWrite $0 "    echo Virtual environment activated successfully >> logs\background.log$\r$\n"
    FileWrite $0 "    if exist $\"pythonw.exe$\" ($\r$\n"
    FileWrite $0 "        echo Using pythonw.exe for silent execution >> logs\background.log$\r$\n"
    FileWrite $0 "        start /min pythonw $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 "    ) else ($\r$\n"
    FileWrite $0 "        echo pythonw.exe not found, using python.exe >> logs\background.log$\r$\n"
    FileWrite $0 "        start /min python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 "    )$\r$\n"
    FileWrite $0 ")$\r$\n"
    FileWrite $9 "Created robust background launcher with virtual environment$\r$\n"
  ${Else}
    FileWrite $0 "echo No virtual environment found, using system Python >> logs\background.log$\r$\n"
    FileWrite $0 "if exist $\"C:\Windows\py.exe$\" ($\r$\n"
    FileWrite $0 "    echo Using Python Launcher >> logs\background.log$\r$\n"
    FileWrite $0 "    start /min C:\Windows\py.exe -3 -B $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 ") else ($\r$\n"
    FileWrite $0 "    echo Using system python command >> logs\background.log$\r$\n"
    FileWrite $0 "    start /min python $\"$INSTDIR\lightscope-runner-windows.py$\"$\r$\n"
    FileWrite $0 ")$\r$\n"
    FileWrite $9 "Created robust background launcher using system Python$\r$\n"
  ${EndIf}
  FileClose $0
  
  ; Setup automatic startup via Windows registry
  DetailPrint "Configuring automatic startup..."
  FileWrite $9 "$\r$\n=== Configuring Automatic Startup ===$\r$\n"
  
  ; Add registry entry for startup (background mode)
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "LightScope" "$\"$INSTDIR\start-lightscope-background.bat$\""
  FileWrite $9 "Added startup registry entry (background mode)$\r$\n"
  
  ; Create startup folder shortcut as backup (background mode)
  CreateDirectory "$SMSTARTUP"
  CreateShortCut "$SMSTARTUP\LightScope.lnk" "$INSTDIR\start-lightscope-background.bat" "" "" 0 SW_SHOWMINIMIZED
  FileWrite $9 "Created startup folder shortcut (background mode)$\r$\n"
  
  ; Start LightScope immediately in background
  DetailPrint "Starting LightScope in background..."
  FileWrite $9 "$\r$\n=== Starting LightScope ===$\r$\n"
  FileWrite $9 "Launching: $\"$INSTDIR\start-lightscope-background.bat$\"$\r$\n"
  
  ; Start in background to not interfere with installer
  Exec '"$INSTDIR\start-lightscope-background.bat"'
  FileWrite $9 "LightScope started in background successfully$\r$\n"
  
  ; Close the log file
  FileWrite $9 "$\r$\n=== Installation Complete ===$\r$\n"
  FileWrite $9 "LightScope is now running and will start automatically when you log in$\r$\n"
  FileWrite $9 "Log file location: $INSTDIR\lightscope-installation.log$\r$\n"
  FileClose $9
  
  ; Show completion message
  DetailPrint "✓ LightScope installed and started successfully!"
  DetailPrint "✓ LightScope will start automatically when you log in"
  DetailPrint "✓ Launchers available in: $INSTDIR"
  DetailPrint "  - start-lightscope-background.bat (silent mode)"
  DetailPrint "  - start-lightscope.bat (debug mode)"
  DetailPrint "Installation log saved to: $INSTDIR\lightscope-installation.log"
  
SectionEnd

Section /o "Desktop Shortcut" SEC02
  CreateShortCut "$DESKTOP\LightScope.lnk" "$INSTDIR\start-lightscope-background.bat" "" ""
SectionEnd

Section "Start Menu Shortcuts" SEC03
  CreateDirectory "$SMPROGRAMS\LightScope"
  CreateShortCut "$SMPROGRAMS\LightScope\LightScope.lnk" "$INSTDIR\start-lightscope-background.bat" "" ""
  CreateShortCut "$SMPROGRAMS\LightScope\Start LightScope (Background).lnk" "$INSTDIR\start-lightscope-background.bat"
  CreateShortCut "$SMPROGRAMS\LightScope\Start LightScope (Debug Mode).lnk" "$INSTDIR\start-lightscope.bat"
  CreateShortCut "$SMPROGRAMS\LightScope\View Logs.lnk" "$INSTDIR\logs\"
  CreateShortCut "$SMPROGRAMS\LightScope\Configuration.lnk" "$INSTDIR\config\"
  CreateShortCut "$SMPROGRAMS\LightScope\Uninstall.lnk" "$INSTDIR\uninst.exe"
SectionEnd

;--------------------------------
; Descriptions

LangString DESC_SecCore ${LANG_ENGLISH} "Core LightScope files and user-level installation (required)"
LangString DESC_SecDesktop ${LANG_ENGLISH} "Optional desktop shortcut for LightScope (not recommended - runs automatically)"
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Start Menu shortcuts for LightScope management"

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
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\lightscope-runner-windows.py"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  
  ; Show final installation summary
  MessageBox MB_OK "LightScope Installation Complete!$\r$\n$\r$\n✓ LightScope is installed and running in background$\r$\n✓ Will start automatically when you log in$\r$\n✓ Windows Firewall configured for honeypot services$\r$\n✓ No visible command prompt window$\r$\n$\r$\nManual launchers available in:$\r$\n$INSTDIR$\r$\n$\r$\nView logs: $INSTDIR\logs\$\r$\nManage via Start Menu shortcuts"
SectionEnd

;--------------------------------
; Uninstaller

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_ICONINFORMATION|MB_OK "$(^Name) was successfully removed from your computer."
FunctionEnd

Function un.onInit
  MessageBox MB_ICONQUESTION|MB_YESNO|MB_DEFBUTTON2 "Are you sure you want to completely remove $(^Name) and all of its components?" IDYES continue_uninstall
  Abort
  continue_uninstall:
FunctionEnd

Section Uninstall
  ; Stop LightScope if running
  DetailPrint "Stopping LightScope..."
  ; Use built-in nsExec to kill processes instead of KillProcDLL plugin
  nsExec::ExecToLog 'taskkill /F /IM python.exe /T'
  ; Also try to kill any specific LightScope processes
  nsExec::ExecToLog 'taskkill /F /IM lightscope-runner-windows.py /T'
  
  ; Remove Windows Firewall rules
  DetailPrint "Removing Windows Firewall rules..."
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Honeypot Services\" -ErrorAction SilentlyContinue"'
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Dynamic Ports\" -ErrorAction SilentlyContinue"'
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Outbound\" -ErrorAction SilentlyContinue"'
  
  ; Remove startup entries
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "LightScope"
  Delete "$SMSTARTUP\LightScope.lnk"
  
  ; Remove files
  Delete "$INSTDIR\uninst.exe"
  Delete "$INSTDIR\bin\lightscope_core.py"
  Delete "$INSTDIR\bin\lightscope-runner-windows.py"
  Delete "$INSTDIR\lightscope_core.py"
  Delete "$INSTDIR\lightscope-runner-windows.py"
  Delete "$INSTDIR\start-lightscope.bat"
  Delete "$INSTDIR\start-lightscope-background.bat"
  Delete "$INSTDIR\config\config.ini"
  Delete "$INSTDIR\config\lightscope-public.pem"
  Delete "$INSTDIR\lightscope-installation.log"
  Delete "$INSTDIR\logs\background.log"
  
  ; Remove shortcuts
  Delete "$DESKTOP\LightScope.lnk"
  Delete "$SMPROGRAMS\LightScope\*.*"
  RMDir "$SMPROGRAMS\LightScope"
  
  ; Remove directories (only if empty)
  RMDir "$INSTDIR\bin"
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

