#!/usr/bin/env powershell

# LightScope Firewall Debug Script
# This script helps identify which Python executable LightScope is using and verifies firewall rules

Write-Host "=== LightScope Firewall Debug Script ===" -ForegroundColor Green
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as administrator" -ForegroundColor Yellow
    Write-Host "Some operations may require administrator privileges" -ForegroundColor Yellow
    Write-Host ""
}

# Function to check if LightScope is running
function Check-LightScopeProcesses {
    Write-Host "=== Checking Running LightScope Processes ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check for Python processes that might be LightScope
    $pythonProcesses = Get-Process | Where-Object { $_.ProcessName -like "*python*" }
    
    if ($pythonProcesses) {
        Write-Host "Found Python processes:" -ForegroundColor Green
        foreach ($proc in $pythonProcesses) {
            try {
                $path = $proc.Path
                $commandLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                Write-Host "  PID: $($proc.Id)" -ForegroundColor White
                Write-Host "  Name: $($proc.ProcessName)" -ForegroundColor White
                Write-Host "  Path: $path" -ForegroundColor White
                Write-Host "  Command Line: $commandLine" -ForegroundColor White
                
                # Check if this looks like LightScope
                if ($commandLine -like "*lightscope*") {
                    Write-Host "  *** THIS LOOKS LIKE LIGHTSCOPE ***" -ForegroundColor Yellow
                }
                Write-Host ""
            } catch {
                Write-Host "  PID: $($proc.Id) - Could not get details" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No Python processes found running" -ForegroundColor Red
    }
    
    # Check for specific LightScope files being executed
    $allProcesses = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*lightscope*" }
    if ($allProcesses) {
        Write-Host "Found LightScope-related processes:" -ForegroundColor Green
        foreach ($proc in $allProcesses) {
            Write-Host "  PID: $($proc.ProcessId)" -ForegroundColor White
            Write-Host "  Name: $($proc.Name)" -ForegroundColor White
            Write-Host "  Command Line: $($proc.CommandLine)" -ForegroundColor White
            Write-Host ""
        }
    }
}

# Function to find all Python executables on the system
function Find-PythonExecutables {
    Write-Host "=== Finding Python Executables ===" -ForegroundColor Cyan
    Write-Host ""
    
    $pythonPaths = @()
    
    # Check system PATH
    try {
        $systemPython = (Get-Command python -ErrorAction Stop).Source
        $pythonPaths += @{Type="System Python"; Path=$systemPython}
        Write-Host "✓ System Python: $systemPython" -ForegroundColor Green
    } catch {
        Write-Host "✗ System Python not found in PATH" -ForegroundColor Red
    }
    
    try {
        $systemPythonw = (Get-Command pythonw -ErrorAction Stop).Source
        $pythonPaths += @{Type="System Pythonw"; Path=$systemPythonw}
        Write-Host "✓ System Pythonw: $systemPythonw" -ForegroundColor Green
    } catch {
        Write-Host "✗ System Pythonw not found in PATH" -ForegroundColor Red
    }
    
    # Check for LightScope virtual environment
    $lightScopeVenv = "$env:LOCALAPPDATA\LightScope\venv\Scripts\python.exe"
    if (Test-Path $lightScopeVenv) {
        $pythonPaths += @{Type="LightScope Virtual Environment"; Path=$lightScopeVenv}
        Write-Host "✓ LightScope Virtual Environment: $lightScopeVenv" -ForegroundColor Green
    } else {
        Write-Host "✗ LightScope Virtual Environment not found" -ForegroundColor Red
    }
    
    # Check for other common Python locations
    $commonPaths = @(
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\python.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\pythonw.exe",
        "C:\Python*\python.exe",
        "C:\Python*\pythonw.exe"
    )
    
    foreach ($pattern in $commonPaths) {
        $found = Get-ChildItem $pattern -ErrorAction SilentlyContinue
        foreach ($path in $found) {
            $pythonPaths += @{Type="Found Python"; Path=$path.FullName}
            Write-Host "✓ Found Python: $($path.FullName)" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    return $pythonPaths
}

# Function to check current firewall rules
function Check-FirewallRules {
    Write-Host "=== Checking Current Firewall Rules ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Get all LightScope related firewall rules
    $rules = Get-NetFirewallRule -DisplayName "*LightScope*" -ErrorAction SilentlyContinue
    
    if ($rules) {
        Write-Host "Found LightScope firewall rules:" -ForegroundColor Green
        foreach ($rule in $rules) {
            Write-Host "  Rule: $($rule.DisplayName)" -ForegroundColor White
            Write-Host "    Status: $($rule.Enabled)" -ForegroundColor White
            Write-Host "    Direction: $($rule.Direction)" -ForegroundColor White
            Write-Host "    Action: $($rule.Action)" -ForegroundColor White
            Write-Host "    Profile: $($rule.Profile)" -ForegroundColor White
            
            # Get port information
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            if ($portFilter) {
                Write-Host "    Protocol: $($portFilter.Protocol)" -ForegroundColor White
                Write-Host "    Local Port: $($portFilter.LocalPort)" -ForegroundColor White
            }
            
            # Get application information
            $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            if ($appFilter) {
                Write-Host "    Program: $($appFilter.Program)" -ForegroundColor White
                
                # Check if the program path exists
                if (Test-Path $appFilter.Program) {
                    Write-Host "    Program Status: EXISTS" -ForegroundColor Green
                } else {
                    Write-Host "    Program Status: MISSING" -ForegroundColor Red
                }
            }
            
            Write-Host ""
        }
    } else {
        Write-Host "No LightScope firewall rules found!" -ForegroundColor Red
    }
}

# Function to test network connectivity
function Test-NetworkConnectivity {
    Write-Host "=== Testing Network Connectivity ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Test some common ports that LightScope might use
    $testPorts = @(8080, 8443, 2222, 2223, 8888)
    
    foreach ($port in $testPorts) {
        try {
            $result = Test-NetConnection -ComputerName "localhost" -Port $port -WarningAction SilentlyContinue
            if ($result.TcpTestSucceeded) {
                Write-Host "  Port $port`: OPEN" -ForegroundColor Green
            } else {
                Write-Host "  Port $port`: CLOSED" -ForegroundColor Red
            }
        } catch {
            Write-Host "  Port $port`: ERROR - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}

# Function to check LightScope installation
function Check-LightScopeInstallation {
    Write-Host "=== Checking LightScope Installation ===" -ForegroundColor Cyan
    Write-Host ""
    
    $lightScopeDir = "$env:LOCALAPPDATA\LightScope"
    if (Test-Path $lightScopeDir) {
        Write-Host "LightScope installation directory: $lightScopeDir" -ForegroundColor Green
        
        # Check for key files
        $keyFiles = @(
            "lightscope_core.py",
            "lightscope-runner-windows.py",
            "start-lightscope.bat",
            "start-lightscope-background.bat"
        )
        
        foreach ($file in $keyFiles) {
            $fullPath = Join-Path $lightScopeDir $file
            if (Test-Path $fullPath) {
                Write-Host "  ✓ $file exists" -ForegroundColor Green
            } else {
                Write-Host "  ✗ $file missing" -ForegroundColor Red
            }
        }
        
        # Check virtual environment
        $venvPath = Join-Path $lightScopeDir "venv"
        if (Test-Path $venvPath) {
            Write-Host "  ✓ Virtual environment exists: $venvPath" -ForegroundColor Green
            
            $venvPython = Join-Path $venvPath "Scripts\python.exe"
            if (Test-Path $venvPython) {
                Write-Host "  ✓ Virtual environment Python: $venvPython" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Virtual environment Python missing" -ForegroundColor Red
            }
        } else {
            Write-Host "  ✗ Virtual environment missing" -ForegroundColor Red
        }
        
        # Check installation log
        $logPath = Join-Path $lightScopeDir "lightscope-installation.log"
        if (Test-Path $logPath) {
            Write-Host "  ✓ Installation log exists: $logPath" -ForegroundColor Green
            Write-Host "    Recent log entries:" -ForegroundColor White
            $logContent = Get-Content $logPath -Tail 10
            foreach ($line in $logContent) {
                Write-Host "    $line" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ✗ Installation log missing" -ForegroundColor Red
        }
    } else {
        Write-Host "LightScope installation directory not found!" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Function to generate recommendations
function Generate-Recommendations {
    param([array]$PythonPaths)
    
    Write-Host "=== Recommendations ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Get current firewall rules
    $rules = Get-NetFirewallRule -DisplayName "*LightScope*" -ErrorAction SilentlyContinue
    $firewallPaths = @()
    
    foreach ($rule in $rules) {
        $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($appFilter) {
            $firewallPaths += $appFilter.Program
        }
    }
    
    Write-Host "Current firewall rules target:" -ForegroundColor Yellow
    foreach ($path in $firewallPaths | Sort-Object | Get-Unique) {
        if (Test-Path $path) {
            Write-Host "  ✓ $path (EXISTS)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $path (MISSING)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Available Python executables:" -ForegroundColor Yellow
    foreach ($python in $PythonPaths) {
        Write-Host "  $($python.Type): $($python.Path)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "To fix firewall rules, run as administrator:" -ForegroundColor Yellow
    Write-Host "  .\check-firewall-rules.ps1" -ForegroundColor White
    Write-Host "  Choose option 3 to remove existing rules" -ForegroundColor White
    Write-Host "  Choose option 2 to create new rules" -ForegroundColor White
    Write-Host ""
}

# Main execution
Write-Host "Starting LightScope firewall debug..." -ForegroundColor Green
Write-Host ""

Check-LightScopeProcesses
$pythonPaths = Find-PythonExecutables
Check-FirewallRules
Test-NetworkConnectivity
Check-LightScopeInstallation
Generate-Recommendations -PythonPaths $pythonPaths

Write-Host "=== Debug Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Check if LightScope is running with the correct Python executable" -ForegroundColor White
Write-Host "2. Verify firewall rules match the actual Python executable being used" -ForegroundColor White
Write-Host "3. Update firewall rules if there is a mismatch" -ForegroundColor White
Write-Host "4. Test connectivity after fixing firewall rules" -ForegroundColor White 