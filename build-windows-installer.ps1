# LightScope Windows Installer Build Script
# This script builds the Windows installer using NSIS automatically (no arguments needed)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $ScriptDir "windows-build"
$OutputDir = Join-Path $ScriptDir "windows-output"
$NSISPath = "${env:ProgramFiles(x86)}\NSIS\makensis.exe"

# Colors for output
function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Version {
    $CoreFile = Join-Path $ScriptDir "lightscope\lightscope_core.py"
    if (Test-Path $CoreFile) {
        $Content = Get-Content $CoreFile -Raw
        if ($Content -match 'ls_version\s*=\s*["'']([^"'']+)["'']') {
            return $Matches[1]
        }
    }
    throw "Could not extract version from lightscope_core.py"
}

function Test-Dependencies {
    Write-ColoredOutput "=== Checking Dependencies ===" "Yellow"
    
    # Check if NSIS is installed
    if (-not (Test-Path $NSISPath)) {
        Write-ColoredOutput "Error: NSIS not found at $NSISPath" "Red"
        Write-ColoredOutput "Please install NSIS from https://nsis.sourceforge.io/" "Red"
        exit 1
    }
    Write-ColoredOutput "OK NSIS found: $NSISPath" "Green"
    
    # Check if Python is installed
    try {
        $PythonVersion = python --version 2>&1
        Write-ColoredOutput "OK Python found: $PythonVersion" "Green"
    } catch {
        Write-ColoredOutput "Error: Python not found" "Red"
        Write-ColoredOutput "Please install Python from https://python.org/" "Red"
        exit 1
    }
    
    # Check required Python packages
    $RequiredPackages = @(
        @("cryptography", "cryptography"),
        @("psutil", "psutil"),
        @("requests", "requests"),
        @("dpkt", "dpkt"),
        @("pywin32", "pywintypes"),  # Install pywin32 but test pywintypes
        @("wmi", "wmi"),
        @("pystray", "pystray"),
        @("Pillow", "PIL")
    )
    
    foreach ($PackageInfo in $RequiredPackages) {
        $InstallName = $PackageInfo[0]
        $ImportName = $PackageInfo[1]
        
        try {
            python -c "import $ImportName" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-ColoredOutput "OK Python package found: $InstallName" "Green"
            } else {
                Write-ColoredOutput "Warning: Python package missing: $InstallName" "Yellow"
                Write-ColoredOutput "Installing $InstallName..." "Yellow"
                python -m pip install $InstallName
                
                # If we just installed pywin32, run its post-install registration
                if ($InstallName -eq "pywin32") {
                    Write-ColoredOutput "Running pywin32 post-install..." "Yellow"
                    python -m pywin32_postinstall -install
                    if ($LASTEXITCODE -eq 0) {
                        Write-ColoredOutput "OK pywin32 post-install completed successfully" "Green"
                    } else {
                        Write-ColoredOutput "Warning: pywin32 post-install failed" "Yellow"
                    }
                }
            }
        } catch {
            Write-ColoredOutput "Warning: Could not check Python package: $InstallName" "Yellow"
        }
    }
}

function Clean-BuildDirectory {
    Write-ColoredOutput "=== Cleaning Build Directory ===" "Yellow"
    if (Test-Path $BuildDir) {
        Remove-Item $BuildDir -Recurse -Force
        Write-ColoredOutput "OK Cleaned build directory" "Green"
    }
    if (Test-Path $OutputDir) {
        Remove-Item $OutputDir -Recurse -Force
        Write-ColoredOutput "OK Cleaned output directory" "Green"
    }
}

function Prepare-BuildFiles {
    Write-ColoredOutput "=== Preparing Build Files ===" "Yellow"
    
    # Debug output
    Write-ColoredOutput "Script directory: $ScriptDir" "Cyan"
    Write-ColoredOutput "Build directory: $BuildDir" "Cyan"
    Write-ColoredOutput "Output directory: $OutputDir" "Cyan"

    # Make sure build & output dirs exist
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    # Define all required files with their correct source paths
    $filesToCopy = @(
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'lightscope\lightscope_core.py'); name = 'lightscope_core.py'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'lightscope-runner-windows.py'); name = 'lightscope-runner-windows.py'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'install-missing-dependencies.py'); name = 'install-missing-dependencies.py'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'README-INSTALLATION.md'); name = 'README-INSTALLATION.md'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'lightscope-installer.nsi'); name = 'lightscope-installer.nsi'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'lightscope-public.pem'); name = 'lightscope-public.pem'},
        @{src = (Join-Path -Path $ScriptDir -ChildPath 'ls.png'); name = 'ls.png'}
    )

    # Copy all required files
    foreach ($file in $filesToCopy) {
        if (Test-Path -Path $file.src) {
            $dest = Join-Path -Path $BuildDir -ChildPath $file.name
            Copy-Item -LiteralPath $file.src -Destination $dest -Force
            Write-ColoredOutput "OK Copied: $($file.name)" "Green"
        } else {
            Write-ColoredOutput "ERROR: Required file not found: $($file.src)" "Red"
            Write-ColoredOutput "This file is required for building the installer." "Red"
            exit 1
        }
    }
    
    # Create license file if it doesn't exist
    $LicensePath = Join-Path $BuildDir "license.txt"
    if (-not (Test-Path $LicensePath)) {
        $LicenseContent = @"
LightScope Network Security Monitor

Copyright (c) $(Get-Date -Format yyyy) TheLightScope

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
        $LicenseContent | Out-File -FilePath $LicensePath -Encoding UTF8
        Write-ColoredOutput "OK Created license file" "Green"
    }
}

function Build-Installer {
    Write-ColoredOutput "=== Building Windows Installer ===" "Yellow"
    
    $Version = Get-Version
    Write-ColoredOutput "Building LightScope v$Version installer..." "Cyan"
    
    # Update version in NSIS script
    $NSISScript = Join-Path $BuildDir "lightscope-installer.nsi"
    $Content = Get-Content $NSISScript -Raw
    $Content = $Content -replace '!define PRODUCT_VERSION ".*"', "!define PRODUCT_VERSION `"$Version`""
    $Content | Out-File -FilePath $NSISScript -Encoding UTF8
    
    # Debug: Show what files are actually in the build directory
    Write-ColoredOutput "Files in build directory:" "Cyan"
    Get-ChildItem $BuildDir | ForEach-Object { Write-ColoredOutput "  - $($_.Name)" "White" }
    
    # Build installer
    $InstallerPath = Join-Path $OutputDir "LightScope-$Version-Setup.exe"
    $NSISArgs = @("/DOUTFILE=`"$InstallerPath`"", "`"$NSISScript`"")
    
    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    Write-ColoredOutput "Running NSIS compiler..." "Cyan"
    Write-ColoredOutput "Working directory: $BuildDir" "Cyan"
    Write-ColoredOutput "NSIS script: $NSISScript" "Cyan"
    Write-ColoredOutput "NSIS arguments: $($NSISArgs -join ' ')" "Cyan"
    
    # Capture NSIS output for debugging
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = $NSISPath
    $ProcessInfo.Arguments = $NSISArgs -join ' '
    $ProcessInfo.WorkingDirectory = $BuildDir
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo
    $Process.Start() | Out-Null
    
    $stdout = $Process.StandardOutput.ReadToEnd()
    $stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    
    if ($stdout) {
        Write-ColoredOutput "NSIS Output:" "Cyan"
        $stdout -split "`n" | ForEach-Object { 
            if ($_.Trim()) { Write-ColoredOutput "  $_" "White" }
        }
    }
    
    if ($stderr) {
        Write-ColoredOutput "NSIS Errors:" "Red"
        $stderr -split "`n" | ForEach-Object { 
            if ($_.Trim()) { Write-ColoredOutput "  $_" "Red" }
        }
    }
    
    if ($Process.ExitCode -eq 0) {
        # NSIS creates the file in the build directory, we need to move it to output directory
        $ActualInstallerPath = Join-Path $BuildDir "LightScope-$Version-Setup.exe"
        
        if (Test-Path $ActualInstallerPath) {
            # Move the installer to the correct output location
            Move-Item $ActualInstallerPath $InstallerPath -Force
            Write-ColoredOutput "OK Installer built successfully: $(Split-Path $InstallerPath -Leaf)" "Green"
            
            # Display file size
            $FileSize = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)
            Write-ColoredOutput "OK Installer size: $FileSize MB" "Green"
            
            return $InstallerPath
        } else {
            Write-ColoredOutput "Error: NSIS compiled successfully but installer not found at expected location" "Red"
            Write-ColoredOutput "Expected at: $ActualInstallerPath" "Red"
            Write-ColoredOutput "Looking for files in build directory:" "Red"
            Get-ChildItem $BuildDir -Filter "*.exe" | ForEach-Object { 
                Write-ColoredOutput "  Found: $($_.Name)" "Yellow" 
            }
            exit 1
        }
    } else {
        Write-ColoredOutput "Error: NSIS compiler failed with exit code $($Process.ExitCode)" "Red"
        Write-ColoredOutput "Expected installer path: $InstallerPath" "Red"
        exit 1
    }
}

function Sign-Installer {
    param([string]$InstallerPath)
    
    Write-ColoredOutput "=== Code Signing ===" "Yellow"
    
    # Look for certificate files automatically
    $CertPath = ""
    $PossibleCertPaths = @(
        "lightscope-cert.pfx",
        "certificate.pfx",
        "code-signing.pfx",
        "lightscope.pfx"
    )
    
    foreach ($Path in $PossibleCertPaths) {
        $FullPath = Join-Path $ScriptDir $Path
        if (Test-Path $FullPath) {
            $CertPath = $FullPath
            break
        }
    }
    
    if (-not $CertPath) {
        Write-ColoredOutput "No certificate found. Looking for common certificate names:" "Yellow"
        foreach ($Path in $PossibleCertPaths) {
            Write-ColoredOutput "  - $Path" "Yellow"
        }
        Write-ColoredOutput "Skipping code signing..." "Yellow"
        return
    }
    
    Write-ColoredOutput "Found certificate: $(Split-Path $CertPath -Leaf)" "Green"
    
    # Find signtool
    $SignTool = ""
    $PossiblePaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\*\bin\signtool.exe"
    )
    
    foreach ($Path in $PossiblePaths) {
        $Found = Get-ChildItem $Path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found) {
            $SignTool = $Found.FullName
            break
        }
    }
    
    if (-not $SignTool) {
        Write-ColoredOutput "Warning: SignTool not found. Install Windows SDK to enable code signing." "Yellow"
        return
    }
    
    Write-ColoredOutput "Signing installer with certificate..." "Cyan"
    
    # Try signing without password first (for certificates without passwords)
    $SignArgs = @(
        "sign",
        "/f", "`"$CertPath`"",
        "/fd", "SHA256",
        "/t", "http://timestamp.digicert.com",
        "`"$InstallerPath`""
    )
    
    $Process = Start-Process -FilePath $SignTool -ArgumentList $SignArgs -NoNewWindow -Wait -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Write-ColoredOutput "OK Installer signed successfully" "Green"
    } else {
        Write-ColoredOutput "Code signing failed - certificate may require password" "Yellow"
        Write-ColoredOutput "To sign with password, add certificate password to environment:" "Yellow"
        Write-ColoredOutput "  `$env:LIGHTSCOPE_CERT_PASSWORD = 'your-password'" "Yellow"
        Write-ColoredOutput "Continuing without code signing..." "Yellow"
    }
}

function Create-DistributionPackage {
    param([string]$InstallerPath)
    
    Write-ColoredOutput "=== Creating Distribution Package ===" "Yellow"
    
    $Version = Get-Version
    $DistributionDir = Join-Path $OutputDir "distribution"
    $ArchivePath = Join-Path $OutputDir "lightscope_v$Version`_windows.zip"
    
    # Create distribution directory
    if (Test-Path $DistributionDir) {
        Remove-Item $DistributionDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DistributionDir | Out-Null
    
    # Copy installer (if it exists)
    if ($InstallerPath -and (Test-Path $InstallerPath)) {
        Copy-Item $InstallerPath $DistributionDir
    } else {
        Write-ColoredOutput "Warning: Installer not found or not specified" "Yellow"
    }
    
    # Copy core files for manual installation
    Copy-Item (Join-Path $BuildDir "lightscope_core.py") $DistributionDir
    Copy-Item (Join-Path $BuildDir "lightscope-runner-windows.py") $DistributionDir
    
    # Copy public key
    $PublicKeyPath = Join-Path $BuildDir "lightscope-public.pem"
    if (Test-Path $PublicKeyPath) {
        Copy-Item $PublicKeyPath $DistributionDir
    }
    
    # Create version file
    @{
        version = $Version
        build_date = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        platform = "windows"
    } | ConvertTo-Json | Out-File -FilePath (Join-Path $DistributionDir "version.json") -Encoding UTF8
    
    # Create installation instructions
    $InstallInstructions = @"
LightScope Windows Installation Instructions
==========================================

AUTOMATIC INSTALLATION (Recommended):
1. Run LightScope-$Version-Setup.exe as Administrator
2. Follow the installation wizard
3. LightScope will start automatically in the background

MANUAL INSTALLATION:
1. Install Python 3.8+ from https://python.org/
2. Install Npcap from https://nmap.org/npcap/
3. Install required Python packages:
   pip install cryptography psutil requests dpkt pywin32
4. Copy all .py files to desired location (e.g., C:\LightScope\)
5. Run:
   python lightscope-runner-windows.py

USER MODE OPERATION:
- The software runs as a user-level application in a virtual environment
- No administrator privileges required
- Automatically starts with Windows login (background mode)
- Virtual environment is activated automatically
- No visible command prompt window

RUNNING LIGHTSCOPE:
- Background mode (default): start-lightscope-background.bat
- Debug mode (visible window): start-lightscope.bat
- Both launchers located in: %LOCALAPPDATA%\LightScope\
- Start Menu shortcuts available for management
- Desktop shortcut is optional (unchecked by default)

LOGS:
- Application logs: %LOCALAPPDATA%\LightScope\logs\
- Installation log: %LOCALAPPDATA%\LightScope\lightscope-installation.log

UNINSTALL:
- Use Add/Remove Programs or
- Run the uninstaller from Start Menu > LightScope

For support, visit: https://thelightscope.com/
"@
    $InstallInstructions | Out-File -FilePath (Join-Path $DistributionDir "INSTALL.txt") -Encoding UTF8
    
    # Create archive
    Write-ColoredOutput "Creating distribution archive..." "Cyan"
    Compress-Archive -Path "$DistributionDir\*" -DestinationPath $ArchivePath -Force
    
    Write-ColoredOutput "OK Distribution package created: $(Split-Path $ArchivePath -Leaf)" "Green"
}

function Show-Summary {
    param([string]$InstallerPath)
    
    $Version = Get-Version
    
    if ($InstallerPath -and (Test-Path $InstallerPath)) {
        $InstallerSize = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)
        $InstallerExists = $true
    } else {
        $InstallerSize = 0
        $InstallerExists = $false
    }
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "=== BUILD COMPLETE ===" "Green"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "WINDOWS DEPLOYMENT FILES:" "Cyan"
    Write-ColoredOutput "============================================" "Cyan"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "Files created in windows-output/:" "White"
    if ($InstallerExists) {
        Write-ColoredOutput "  1. LightScope-$Version-Setup.exe ($($InstallerSize) MB) - Windows Installer" "White"
    } else {
        Write-ColoredOutput "  1. LightScope-$Version-Setup.exe - FAILED TO CREATE" "Red"
    }
    Write-ColoredOutput "  2. lightscope_v$Version`_windows.zip - Complete distribution package" "White"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "DEPLOYMENT INSTRUCTIONS:" "Cyan"
    Write-ColoredOutput "============================================" "Cyan"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "FOR END USERS:" "Yellow"
    Write-ColoredOutput "- Download and run LightScope-$Version-Setup.exe as Administrator" "White"
    Write-ColoredOutput "- The installer creates a virtual environment and installs dependencies" "White"
    Write-ColoredOutput "- LightScope runs in the virtual environment automatically (background mode)" "White"
    Write-ColoredOutput "- No visible command prompt window - runs silently in background" "White"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "FOR DISTRIBUTION:" "Yellow"
    Write-ColoredOutput "- Upload LightScope-$Version-Setup.exe to your download server" "White"
    Write-ColoredOutput "- Update your website download links" "White"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "TESTING:" "Cyan"
    Write-ColoredOutput "============================================" "Cyan"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "Test the installer on a clean Windows system:" "White"
    Write-ColoredOutput "1. Run installer as Administrator" "White"
    Write-ColoredOutput "2. Check virtual environment: dir `"%LOCALAPPDATA%\LightScope\venv`"" "White"
    Write-ColoredOutput "3. Test background launcher: `"%LOCALAPPDATA%\LightScope\start-lightscope-background.bat`"" "White"
    Write-ColoredOutput "4. Test debug launcher: `"%LOCALAPPDATA%\LightScope\start-lightscope.bat`"" "White"
    Write-ColoredOutput "5. View logs: dir `"%LOCALAPPDATA%\LightScope\logs`"" "White"
    Write-ColoredOutput "6. Test uninstall from Add/Remove Programs" "White"
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "SUCCESS: Windows package ready for distribution!" "Green"
}

# Main execution
try {
    Write-ColoredOutput "=== LightScope Windows Build Script ===" "Cyan"
    Write-ColoredOutput "Building Windows installer automatically..." "Cyan"
    Write-ColoredOutput "" "White"
    
    # Check if we're in the right directory
    if (-not (Test-Path (Join-Path $ScriptDir "lightscope\lightscope_core.py"))) {
        Write-ColoredOutput "Error: Please run this script from the thelightscope directory" "Red"
        Write-ColoredOutput "Current directory: $(Get-Location)" "Red"
        exit 1
    }
    
    Write-ColoredOutput "1. Checking dependencies..." "Yellow"
    Test-Dependencies
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "2. Cleaning previous build artifacts..." "Yellow"
    Clean-BuildDirectory
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "3. Preparing build files..." "Yellow"
    Prepare-BuildFiles
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "4. Building Windows installer..." "Yellow"
    $InstallerPath = Build-Installer
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "5. Checking for code signing..." "Yellow"
    Sign-Installer -InstallerPath $InstallerPath
    
    Write-ColoredOutput "" "White"
    Write-ColoredOutput "6. Creating distribution package..." "Yellow"
    Create-DistributionPackage -InstallerPath $InstallerPath
    
    Write-ColoredOutput "" "White"
    Show-Summary -InstallerPath $InstallerPath
    
} catch {
    Write-ColoredOutput "Error: $($_.Exception.Message)" "Red"
    Write-ColoredOutput "Stack trace: $($_.ScriptStackTrace)" "Red"
    exit 1
} 