# Simple LightScope Installation Verification Script
# Run this script to verify LightScope is installed and running

Write-Host "=== LightScope Installation Verification ===" -ForegroundColor Cyan
Write-Host ""

$installPath = "$env:LOCALAPPDATA\LightScope"

# 1. Check Installation Directory
Write-Host "1. Checking Installation Directory..." -ForegroundColor Yellow
if (Test-Path $installPath) {
    Write-Host "   ✓ Installation directory found: $installPath" -ForegroundColor Green
    
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
            Write-Host "   ✓ Found: $file" -ForegroundColor Green
        } else {
            Write-Host "   ✗ Missing: $file" -ForegroundColor Red
        }
    }
} else {
    Write-Host "   ✗ Installation directory not found!" -ForegroundColor Red
}

# 2. Check Auto-Start Registry
Write-Host ""
Write-Host "2. Checking Auto-Start Configuration..." -ForegroundColor Yellow
try {
    $regValue = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LightScope" -ErrorAction SilentlyContinue
    if ($regValue) {
        Write-Host "   ✓ Auto-start registry entry found" -ForegroundColor Green
        Write-Host "     Command: $($regValue.LightScope)" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Auto-start registry entry not found" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Error checking registry" -ForegroundColor Red
}

# 3. Check Running Processes
Write-Host ""
Write-Host "3. Checking Running Processes..." -ForegroundColor Yellow
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
        Write-Host "   ✓ LightScope process is running (PID: $($lightScopeProcess.Id))" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Python processes found, but no LightScope process detected" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ No Python processes running" -ForegroundColor Red
}

# 4. Check Runtime Logs
Write-Host ""
Write-Host "4. Checking Runtime Logs..." -ForegroundColor Yellow
$logsDir = Join-Path $installPath "logs"
if (Test-Path $logsDir) {
    $logFiles = Get-ChildItem $logsDir -Filter "*.log" -ErrorAction SilentlyContinue
    if ($logFiles) {
        Write-Host "   ✓ Runtime logs found: $($logFiles.Count) files" -ForegroundColor Green
        
        # Show recent entries from main log
        $mainLog = Join-Path $logsDir "lightscope-runner.log"
        if (Test-Path $mainLog) {
            Write-Host "   Recent entries from lightscope-runner.log:" -ForegroundColor Gray
            Get-Content $mainLog -Tail 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
        }
    } else {
        Write-Host "   ⚠ Logs directory exists but no log files found" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ Logs directory not found" -ForegroundColor Red
}

# 5. Check Dependencies
Write-Host ""
Write-Host "5. Checking Python Dependencies..." -ForegroundColor Yellow
$requiredPackages = @("cryptography", "psutil", "requests", "dpkt")

foreach ($package in $requiredPackages) {
    try {
        $result = python -c "import $package; print('OK')" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✓ $package installed" -ForegroundColor Green
        } else {
            Write-Host "   ✗ $package missing or broken" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ✗ $package error checking" -ForegroundColor Red
    }
}

# Manual Commands
Write-Host ""
Write-Host "=== Manual Commands ===" -ForegroundColor Cyan
Write-Host "To manually start LightScope:" -ForegroundColor Gray
Write-Host "  cd `"$installPath`"" -ForegroundColor White
Write-Host "  .\start-lightscope.bat" -ForegroundColor White
Write-Host ""
Write-Host "To view logs:" -ForegroundColor Gray
Write-Host "  Get-Content `"$installPath\logs\lightscope-runner.log`" -Tail 20" -ForegroundColor White
Write-Host ""
Write-Host "To check processes:" -ForegroundColor Gray
Write-Host "  Get-Process python* | Where-Object {`$_.ProcessName -like '*python*'}" -ForegroundColor White
Write-Host "" 