; LightScope Windows User-Level Installer Script
; This script creates a complete Windows installer for LightScope that runs as a user application

;--------------------------------
; General

!define PRODUCT_NAME "LightScope"
!define PRODUCT_VERSION "1.0.7"
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
!include "StrFunc.nsh"

; String functions
${StrRep}
${StrTrimNewLines}

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
  ; Check dependencies FIRST, before any installer UI is shown
  ; This ensures users are notified immediately if requirements are missing
  
  ; Create a temporary log file for dependency check
  FileOpen $9 "$TEMP\lightscope-dependency-check.log" w
  FileWrite $9 "=== LightScope Dependency Check ===$\r$\n"
  FileWrite $9 "Check started at: $\r$\n"
  
  ; Check Python first
  DetailPrint "Checking for Python..."
  FileWrite $9 "=== Python Dependency Check ===$\r$\n"
  
  ; Check if Python is available
  ClearErrors
  nsExec::ExecToStack 'python --version'
  Pop $0 ; exit code
  Pop $1 ; output
  FileWrite $9 "Python check exit code: $0, output: $1$\r$\n"
  
  ${If} $0 != 0
    ; Try python3 command
    nsExec::ExecToStack 'python3 --version'
    Pop $0 ; exit code
    Pop $1 ; output
    FileWrite $9 "Python3 check exit code: $0, output: $1$\r$\n"
  ${EndIf}
  
  ${If} $0 != 0
    ; Python not found
    FileWrite $9 "ERROR: Python not found after all checks!$\r$\n"
    FileClose $9
    MessageBox MB_OK "Thank you for supporting cybersecurity research and downloading LightScope!$\r$\n$\r$\nLightScope requires Python 3.8+, which we didn't find on your system path. Please download and install Python, make sure ADD TO PATH is selected, and restart this installer.$\r$\n$\r$\nWhen you click $\"Ok$\" we will open a browser where you can download python." /SD IDOK
    ExecShell "open" "https://www.python.org/downloads/"
    Abort
  ${EndIf}
  
  FileWrite $9 "Python found successfully: $1$\r$\n"
  
  ; Check NPCAP next
  DetailPrint "Checking for NPCAP..."
  FileWrite $9 "=== NPCAP Dependency Check ===$\r$\n"
  
  npcap_check_loop:
  ; Check registry for NPCAP
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NpcapInst" "DisplayName"
  FileWrite $9 "NPCAP registry check: $0$\r$\n"
  ${If} $0 != ""
    FileWrite $9 "NPCAP found via registry: $0$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ; Check for NPCAP DLL files
  ${If} ${FileExists} "$WINDIR\System32\npcap.dll"
    FileWrite $9 "NPCAP DLL found: $WINDIR\System32\npcap.dll$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ${If} ${FileExists} "$WINDIR\System32\wpcap.dll"
    FileWrite $9 "WPCAP DLL found: $WINDIR\System32\wpcap.dll$\r$\n"
    Goto npcap_found
  ${EndIf}
  
  ; NPCAP not found - offer to install or retry
  FileWrite $9 "NPCAP not found - prompting user for installation$\r$\n"
  MessageBox MB_YESNO "Almost there! Npcap is the last thing you need to install, and we will take care of the rest. We will open that window for you now. Please make sure you select $\"Install Npcap in WinPcap API-compatible Mode$\" is selected. This is probably selected by default.$\r$\n$\r$\nClick YES to open the download page, or NO to exit the installer." IDYES download_npcap IDNO abort_install
  
  download_npcap:
    FileWrite $9 "Opening NPCAP download page...$\r$\n"
    ExecShell "open" "https://nmap.org/npcap/"
    
    npcap_retry_loop:
      MessageBox MB_YESNO "Install NPCAP with WinPcap compatibility, then click YES when done or NO to exit the installer." IDYES recheck_npcap IDNO abort_install
      
    recheck_npcap:
      FileWrite $9 "Rechecking NPCAP installation...$\r$\n"
      ; Check registry again
      ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NpcapInst" "DisplayName"
      ${If} $0 != ""
        FileWrite $9 "NPCAP successfully detected via registry: $0$\r$\n"
        Goto npcap_found
      ${EndIf}
      
      ; Check for DLL files again
      ${If} ${FileExists} "$WINDIR\System32\npcap.dll"
        FileWrite $9 "NPCAP DLL successfully detected$\r$\n"
        Goto npcap_found
      ${EndIf}
      
      ${If} ${FileExists} "$WINDIR\System32\wpcap.dll"
        FileWrite $9 "WPCAP DLL successfully detected$\r$\n"
        Goto npcap_found
      ${EndIf}
      
      ; Still not found - ask to try again
      MessageBox MB_YESNO "NPCAP not found. Try again?" IDYES npcap_retry_loop IDNO abort_install
      
  abort_install:
    FileWrite $9 "Installation aborted - NPCAP is required$\r$\n"
    FileClose $9
    Abort
  
  npcap_found:
  FileWrite $9 "NPCAP dependency check completed successfully$\r$\n"
  
  ; Close dependency check log
  FileWrite $9 "=== All Dependencies Found ===$\r$\n"
  FileWrite $9 "Proceeding with installation...$\r$\n"
  FileClose $9
  
  ; Now check if already installed (original functionality)
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





Function ConfigureFirewall
  ; Configure Windows Firewall to allow LightScope honeypot traffic
  DetailPrint "Configuring Windows Firewall for LightScope..."
  FileWrite $9 "$\r$\n=== Configuring Windows Firewall ===$\r$\n"
  
  ; Find system Python executable
  nsExec::ExecToStack 'where python'
  Pop $0
  Pop $1
  ${If} $0 == 0
    ; Strip newlines and whitespace from the path
    ${StrRep} $1 $1 "$\r" ""
    ${StrRep} $1 $1 "$\n" ""
    ${StrTrimNewLines} $1 $1
    FileWrite $9 "Found system Python: $1$\r$\n"
    StrCpy $2 "$1"  ; Store system python path
  ${Else}
    StrCpy $2 "python.exe"  ; Fallback
    FileWrite $9 "Using default python.exe path$\r$\n"
  ${EndIf}
  
  ; Find system pythonw executable
  nsExec::ExecToStack 'where pythonw'
  Pop $0
  Pop $1
  ${If} $0 == 0
    ; Strip newlines and whitespace from the path
    ${StrRep} $1 $1 "$\r" ""
    ${StrRep} $1 $1 "$\n" ""
    ${StrTrimNewLines} $1 $1
    FileWrite $9 "Found system pythonw: $1$\r$\n"
    StrCpy $3 "$1"  ; Store system pythonw path
  ${Else}
    StrCpy $3 "pythonw.exe"  ; Fallback
    FileWrite $9 "Using default pythonw.exe path$\r$\n"
  ${EndIf}
  
  ; Create firewall rules for system Python
  DetailPrint "Creating firewall rules for system Python..."
  FileWrite $9 "Creating firewall rules for system Python: $2$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Dynamic Ports (Python)\" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program \"$2\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Python dynamic ports firewall rule creation exit code: $0$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Outbound (Python)\" -Direction Outbound -Protocol TCP -Program \"$2\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Python outbound firewall rule creation exit code: $0$\r$\n"
  
  ; Create firewall rules for system pythonw
  DetailPrint "Creating firewall rules for system pythonw..."
  FileWrite $9 "Creating firewall rules for system pythonw: $3$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Dynamic Ports (Pythonw)\" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program \"$3\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Pythonw dynamic ports firewall rule creation exit code: $0$\r$\n"
  
  nsExec::ExecToLog 'powershell -Command "New-NetFirewallRule -DisplayName \"LightScope Outbound (Pythonw)\" -Direction Outbound -Protocol TCP -Program \"$3\" -Action Allow -Profile Private,Domain,Public -ErrorAction SilentlyContinue"'
  Pop $0
  FileWrite $9 "Pythonw outbound firewall rule creation exit code: $0$\r$\n"
  
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
  
  ; Dependencies already checked in .onInit
  FileWrite $9 "=== Dependencies Already Verified ===$\r$\n"
  
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
  
  ; Copy system tray icon
  File "/oname=$INSTDIR\ls.png" "ls.png"
  FileWrite $9 "System tray icon copied from installation package$\r$\n"
  
  ; Create config file
  FileOpen $0 "$INSTDIR\config\config.ini" w
  FileWrite $0 "[Settings]$\r$\n"
  FileWrite $0 "# Database name for storing LightScope data (auto-generated during installation)$\r$\n"
  FileWrite $0 "database = $\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Randomization key for IP address anonymization (auto-generated if empty)$\r$\n"
  FileWrite $0 "randomization_key = $\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Enable automatic SSH/Telnet honeypot port forwarding (yes/no)$\r$\n"
  FileWrite $0 "self_telnet_and_ssh_honeypot_ports_to_forward = no$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Enable automatic updates (yes/no)$\r$\n"
  FileWrite $0 "autoupdate = yes$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Update check interval in hours (minimum 1 hour)$\r$\n"
  FileWrite $0 "update_check_interval = 24$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Enable debug logging (yes/no)$\r$\n"
  FileWrite $0 "debug_logging = no$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Custom interface to monitor (leave empty for auto-detection)$\r$\n"
  FileWrite $0 "interface = $\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Maximum number of concurrent honeypot ports$\r$\n"
  FileWrite $0 "max_honeypot_ports = 10$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Honeypot rotation interval in hours$\r$\n"
  FileWrite $0 "honeypot_rotation_interval = 4$\r$\n"
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
  nsExec::ExecToLog '"$2" install --upgrade cryptography psutil requests dpkt packaging urllib3 scapy pywin32 pystray Pillow'
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
  
  ; Add registry entry for startup (background mode) - PRIMARY startup method
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "LightScope" "$\"$INSTDIR\start-lightscope-background.bat$\""
  FileWrite $9 "Added startup registry entry (background mode)$\r$\n"
  
  ; Remove any existing startup folder shortcut to prevent duplicate launches
  Delete "$SMSTARTUP\LightScope.lnk"
  FileWrite $9 "Removed any existing startup folder shortcut to prevent duplicates$\r$\n"
  
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
  MessageBox MB_OK "LightScope Installation Complete!$\r$\n$\r$\n✓ LightScope is installed and running in background$\r$\n✓ Will start automatically when you log in$\r$\n✓ Windows Firewall configured for honeypot services$\r$\n$\r$\nIf you ever want to uninstall LightScope, please go to $\"add or remove programs$\" and find LightScope on the list. It will give you an option to completely remove it from your system.$\r$\n$\r$\nThank you again for supporting cybersecurity research!"
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
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Dynamic Ports (Python)\" -ErrorAction SilentlyContinue"'
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Outbound (Python)\" -ErrorAction SilentlyContinue"'
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Dynamic Ports (Pythonw)\" -ErrorAction SilentlyContinue"'
  nsExec::ExecToLog 'powershell -Command "Remove-NetFirewallRule -DisplayName \"LightScope Outbound (Pythonw)\" -ErrorAction SilentlyContinue"'
  
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

