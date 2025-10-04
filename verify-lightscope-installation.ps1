# LightScope Installation Verification Script
# Run this script to verify that LightScope is properly installed and running

param(
    [switch]$Detailed,
    [switch]$FixIssues
)

function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-LightScopeInstallation {
    Write-ColoredOutput "=== LightScope Installation Verification ===" "Cyan"
    Write-ColoredOutput ""
    
    $installPath = "$env:LOCALAPPDATA\LightScope"
    $issues = @()
    $status = @{}
    
    # 1. Check Installation Directory
    Write-ColoredOutput "1. Checking Installation Directory..." "Yellow"
    if (Test-Path $installPath) {
        Write-ColoredOutput "   ✓ Installation directory found: $installPath" "Green"
        $status.InstallDir = $true
        
        # List key files
        $keyFiles = @(
            "lightscope_core.py",
            "lightscope-runner-windows.py", 
            "start-lightscope.bat",
            "config\lightscope-public.pem",
            "config\config.ini"
        )
        
        foreach ($file in $keyFiles) {
            $filePath = Join-Path $installPath $file
            if (Test-Path $filePath) {
                Write-ColoredOutput "   ✓ Found: $file" "Green"
            } else {
                Write-ColoredOutput "   ✗ Missing: $file" "Red"
                $issues += "Missing file: $file"
            }
        }
    } else {
        Write-ColoredOutput "   ✗ Installation directory not found!" "Red"
        $status.InstallDir = $false
        $issues += "Installation directory missing"
    }
    
    # 2. Check Auto-Start Registry
    Write-ColoredOutput "`n2. Checking Auto-Start Configuration..." "Yellow"
    try {
        $regValue = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LightScope" -ErrorAction SilentlyContinue
        if ($regValue) {
            Write-ColoredOutput "   ✓ Auto-start registry entry found" "Green"
            Write-ColoredOutput "     Command: $($regValue.LightScope)" "Gray"
            $status.AutoStart = $true
        } else {
            Write-ColoredOutput "   ✗ Auto-start registry entry not found" "Red"
            $status.AutoStart = $false
            $issues += "Auto-start not configured"
        }
    } catch {
        Write-ColoredOutput "   ✗ Error checking registry: $($_.Exception.Message)" "Red"
        $status.AutoStart = $false
        $issues += "Registry check failed"
    }
    
    # 3. Check Running Processes
    Write-ColoredOutput "`n3. Checking Running Processes..." "Yellow"
    $pythonProcesses = Get-Process python* -ErrorAction SilentlyContinue
    $lightScopeProcess = $null
    
    if ($pythonProcesses) {
        foreach ($proc in $pythonProcesses) {
            try {
                $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                if ($cmdLine -like "*lightscope*") {
                    $lightScopeProcess = $proc
                    break
                }
            } catch {
                # Ignore access denied errors
            }
        }
        
        if ($lightScopeProcess) {
            Write-ColoredOutput "   ✓ LightScope process is running (PID: $($lightScopeProcess.Id))" "Green"
            $status.ProcessRunning = $true
        } else {
            Write-ColoredOutput "   ⚠ Python processes found, but no LightScope process detected" "Yellow"
            $status.ProcessRunning = $false
            $issues += "LightScope process not running"
        }
    } else {
        Write-ColoredOutput "   ✗ No Python processes running" "Red"
        $status.ProcessRunning = $false
        $issues += "No Python processes found"
    }
    
    # 4. Check Installation Log
    Write-ColoredOutput "`n4. Checking Installation Log..." "Yellow"
    $logPath = Join-Path $installPath "lightscope-installation.log"
    if (Test-Path $logPath) {
        Write-ColoredOutput "   ✓ Installation log found" "Green"
        $status.InstallLog = $true
        
        if ($Detailed) {
            Write-ColoredOutput "   Last 10 lines of installation log:" "Gray"
            Get-Content $logPath -Tail 10 | ForEach-Object { Write-ColoredOutput "     $_" "Gray" }
        }
    } else {
        Write-ColoredOutput "   ✗ Installation log not found" "Red"
        $status.InstallLog = $false
        $issues += "Installation log missing"
    }
    
    # 5. Check Runtime Logs
    Write-ColoredOutput "`n5. Checking Runtime Logs..." "Yellow"
    $logsDir = Join-Path $installPath "logs"
    if (Test-Path $logsDir) {
        $logFiles = Get-ChildItem $logsDir -Filter "*.log" -ErrorAction SilentlyContinue
        if ($logFiles) {
            Write-ColoredOutput "   ✓ Runtime logs found: $($logFiles.Count) files" "Green"
            $status.RuntimeLogs = $true
            
            if ($Detailed) {
                foreach ($logFile in $logFiles) {
                    Write-ColoredOutput "   Log file: $($logFile.Name) (Size: $([math]::Round($logFile.Length/1KB, 2)) KB)" "Gray"
                }
                
                # Show recent entries from main log
                $mainLog = Join-Path $logsDir "lightscope-runner.log"
                if (Test-Path $mainLog) {
                    Write-ColoredOutput "   Recent entries from lightscope-runner.log:" "Gray"
                    Get-Content $mainLog -Tail 5 | ForEach-Object { Write-ColoredOutput "     $_" "Gray" }
                }
            }
        } else {
            Write-ColoredOutput "   ⚠ Logs directory exists but no log files found" "Yellow"
            $status.RuntimeLogs = $false
            $issues += "No runtime log files"
        }
    } else {
        Write-ColoredOutput "   ✗ Logs directory not found" "Red"
        $status.RuntimeLogs = $false
        $issues += "Logs directory missing"
    }
    
    # 6. Check Configuration
    Write-ColoredOutput "`n6. Checking Configuration..." "Yellow"
    $configPath = Join-Path $installPath "config\config.ini"
    if (Test-Path $configPath) {
        Write-ColoredOutput "   ✓ Configuration file found" "Green"
        $status.Config = $true
        
        if ($Detailed) {
            Write-ColoredOutput "   Configuration contents:" "Gray"
            Get-Content $configPath | ForEach-Object { Write-ColoredOutput "     $_" "Gray" }
        }
    } else {
        Write-ColoredOutput "   ✗ Configuration file not found" "Red"
        $status.Config = $false
        $issues += "Configuration file missing"
    }
    
    # 7. Check Dependencies
    Write-ColoredOutput "`n7. Checking Python Dependencies..." "Yellow"
    $requiredPackages = @("cryptography", "psutil", "requests", "dpkt", "pcap")
    $missingPackages = @()
    
    foreach ($package in $requiredPackages) {
        try {
            $result = python -c "import $package; print('OK')" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-ColoredOutput "   ✓ $package: installed" "Green"
            } else {
                Write-ColoredOutput "   ✗ $package: missing or broken" "Red"
                $missingPackages += $package
            }
        } catch {
            Write-ColoredOutput "   ✗ $package: error checking" "Red"
            $missingPackages += $package
        }
    }
    
    if ($missingPackages.Count -eq 0) {
        $status.Dependencies = $true
    } else {
        $status.Dependencies = $false
        $issues += "Missing Python packages: $($missingPackages -join ', ')"
    }
    
    # Summary
    Write-ColoredOutput "`n=== Summary ===" "Cyan"
    $totalChecks = $status.Keys.Count
    $passedChecks = ($status.Values | Where-Object { $_ -eq $true }).Count
    
    if ($passedChecks -eq $totalChecks) {
        Write-ColoredOutput "✓ All checks passed! LightScope appears to be installed and running correctly." "Green"
    } else {
        Write-ColoredOutput "⚠ $passedChecks/$totalChecks checks passed. Issues found:" "Yellow"
        foreach ($issue in $issues) {
            Write-ColoredOutput "  • $issue" "Red"
        }
        
        if ($FixIssues) {
            Write-ColoredOutput "`n=== Attempting to Fix Issues ===" "Cyan"
            
            # Try to start LightScope if it's not running
            if (-not $status.ProcessRunning -and $status.InstallDir) {
                Write-ColoredOutput "Attempting to start LightScope..." "Yellow"
                try {
                    $startScript = Join-Path $installPath "start-lightscope.bat"
                    if (Test-Path $startScript) {
                        Start-Process -FilePath $startScript -WindowStyle Minimized
                        Write-ColoredOutput "✓ Started LightScope process" "Green"
                    }
                } catch {
                    Write-ColoredOutput "✗ Failed to start LightScope: $($_.Exception.Message)" "Red"
                }
            }
            
            # Install missing packages
            if ($missingPackages.Count -gt 0) {
                Write-ColoredOutput "Installing missing Python packages..." "Yellow"
                foreach ($package in $missingPackages) {
                    try {
                        python -m pip install $package
                        Write-ColoredOutput "✓ Installed $package" "Green"
                    } catch {
                        Write-ColoredOutput "✗ Failed to install $package" "Red"
                    }
                }
            }
        }
    }
    
    Write-ColoredOutput "`n=== Manual Commands ===" "Cyan"
    Write-ColoredOutput "To manually start LightScope:" "Gray"
    Write-ColoredOutput "  cd `"$installPath`"" "White"
    Write-ColoredOutput "  .\start-lightscope.bat" "White"
    Write-ColoredOutput ""
    Write-ColoredOutput "To view logs:" "Gray"
    Write-ColoredOutput "  Get-Content `"$installPath\logs\lightscope-runner.log`" -Tail 20" "White"
    Write-ColoredOutput ""
    Write-ColoredOutput "To check processes:" "Gray"
    Write-ColoredOutput "  Get-Process python* | Where-Object {`$_.ProcessName -like '*python*'}" "White"
}

# Main execution
if ($args.Count -eq 0 -or $args[0] -eq "-h" -or $args[0] -eq "--help") {
    Write-ColoredOutput "LightScope Installation Verification Script" "Cyan"
    Write-ColoredOutput "Usage:" "White"
    Write-ColoredOutput "  .\verify-lightscope-installation.ps1           # Basic verification" "White"
    Write-ColoredOutput "  .\verify-lightscope-installation.ps1 -Detailed # Detailed verification" "White"
    Write-ColoredOutput "  .\verify-lightscope-installation.ps1 -FixIssues # Try to fix issues" "White"
    Write-ColoredOutput ""
    exit 0
}

Test-LightScopeInstallation 