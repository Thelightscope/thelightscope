# LightScope Installation Verification Script

Write-Host "=== LightScope Installation Check ===" -ForegroundColor Cyan

$installPath = "$env:LOCALAPPDATA\LightScope"

Write-Host "1. Checking installation directory..." -ForegroundColor Yellow
if (Test-Path $installPath) {
    Write-Host "   ✓ Installation found at: $installPath" -ForegroundColor Green
} else {
    Write-Host "   ✗ Installation not found!" -ForegroundColor Red
    exit
}

Write-Host "2. Checking key files..." -ForegroundColor Yellow
$files = @("lightscope_core.py", "lightscope-runner-windows.py", "start-lightscope.bat")
foreach ($file in $files) {
    if (Test-Path (Join-Path $installPath $file)) {
        Write-Host "   ✓ $file" -ForegroundColor Green
    } else {
        Write-Host "   ✗ $file missing" -ForegroundColor Red
    }
}

Write-Host "3. Checking processes..." -ForegroundColor Yellow
$processes = Get-Process python* -ErrorAction SilentlyContinue
if ($processes) {
    Write-Host "   ✓ Python processes found: $($processes.Count)" -ForegroundColor Green
} else {
    Write-Host "   ⚠ No Python processes running" -ForegroundColor Yellow
}

Write-Host "4. Checking logs..." -ForegroundColor Yellow
$logPath = Join-Path $installPath "logs\lightscope-runner.log"
if (Test-Path $logPath) {
    Write-Host "   ✓ Log file found" -ForegroundColor Green
    Write-Host "   Recent log entries:" -ForegroundColor Gray
    Get-Content $logPath -Tail 3 | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
} else {
    Write-Host "   ⚠ No log file found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Manual Commands ===" -ForegroundColor Cyan
Write-Host "Start LightScope:   cd `"$installPath`" && .\start-lightscope.bat" -ForegroundColor White
Write-Host "View logs:         Get-Content `"$logPath`" -Tail 20" -ForegroundColor White
Write-Host "Check processes:   Get-Process python*" -ForegroundColor White 