# LightScope Live Monitor Script
# This script monitors LightScope logs and process status in real-time

param(
    [switch]$ShowLogs = $true,
    [switch]$ShowProcess = $true,
    [int]$RefreshInterval = 2
)

# Configuration
$InstallDir = "$env:LOCALAPPDATA\LightScope"
$LogFile = "$InstallDir\logs\lightscope-runner.log"
$ProcessName = "pythonw"

function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Get-LightScopeProcess {
    Get-Process | Where-Object { 
        $_.ProcessName -eq "pythonw" -and 
        $_.CommandLine -like "*lightscope-runner-windows.py*" 
    } -ErrorAction SilentlyContinue
}

function Show-ProcessStatus {
    $process = Get-LightScopeProcess
    if ($process) {
        Write-ColoredOutput "✅ LightScope Status: RUNNING" "Green"
        Write-ColoredOutput "   Process ID: $($process.Id)" "Gray"
        Write-ColoredOutput "   Memory Usage: $([math]::Round($process.WorkingSet64/1MB, 2)) MB" "Gray"
        Write-ColoredOutput "   Start Time: $($process.StartTime)" "Gray"
    } else {
        Write-ColoredOutput "❌ LightScope Status: NOT RUNNING" "Red"
    }
}

function Show-LogLocation {
    Write-ColoredOutput "📁 Log Files Location:" "Cyan"
    Write-ColoredOutput "   $LogFile" "Gray"
    Write-ColoredOutput "   $InstallDir\lightscope-installation.log" "Gray"
    Write-ColoredOutput ""
}

# Main monitoring loop
Clear-Host
Write-ColoredOutput "🔍 LightScope Live Monitor" "Yellow"
Write-ColoredOutput "=" * 50 "Yellow"
Write-ColoredOutput ""

Show-LogLocation

if ($ShowProcess) {
    Show-ProcessStatus
    Write-ColoredOutput ""
}

if ($ShowLogs) {
    if (Test-Path $LogFile) {
        Write-ColoredOutput "📊 Live Log Output (Press Ctrl+C to stop):" "Cyan"
        Write-ColoredOutput "-" * 50 "Gray"
        
        # Start tailing the log file
        try {
            Get-Content $LogFile -Wait | ForEach-Object {
                $timestamp = Get-Date -Format "HH:mm:ss"
                
                # Color code log levels
                if ($_ -match "ERROR") {
                    Write-ColoredOutput "[$timestamp] $_" "Red"
                } elseif ($_ -match "WARNING") {
                    Write-ColoredOutput "[$timestamp] $_" "Yellow"
                } elseif ($_ -match "INFO") {
                    Write-ColoredOutput "[$timestamp] $_" "Green"
                } else {
                    Write-ColoredOutput "[$timestamp] $_" "White"
                }
            }
        } catch {
            Write-ColoredOutput "Error reading log file: $_" "Red"
        }
    } else {
        Write-ColoredOutput "⚠️  Log file not found: $LogFile" "Yellow"
        Write-ColoredOutput "   LightScope may not be running or hasn't started logging yet." "Yellow"
        Write-ColoredOutput ""
        Write-ColoredOutput "🔧 To start LightScope:" "Cyan"
        Write-ColoredOutput "   1. Use Start Menu > LightScope > Start LightScope (Debug Mode)" "White"
        Write-ColoredOutput "   2. Or run: $InstallDir\start-lightscope.bat" "White"
    }
}

Write-ColoredOutput "" "White"
Write-ColoredOutput "💡 Tips:" "Cyan"
Write-ColoredOutput "   - Use Ctrl+C to stop monitoring" "Gray"
Write-ColoredOutput "   - Run with -ShowProcess to see process info" "Gray"
Write-ColoredOutput "   - Check Task Manager for pythonw.exe processes" "Gray" 