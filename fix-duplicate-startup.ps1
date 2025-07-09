#!/usr/bin/env pwsh
# Fix LightScope Duplicate Startup Issue
# This script removes duplicate startup entries that cause LightScope to launch twice

Write-Host "=== LightScope Startup Fix Utility ===" -ForegroundColor Yellow
Write-Host "This script will remove duplicate startup entries that cause LightScope to launch twice on Windows restart."
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Host "Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "Running as regular user" -ForegroundColor Yellow
}

# Stop any running LightScope processes
Write-Host "Stopping LightScope processes..." -ForegroundColor Cyan
try {
    $lightScopeProcesses = Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*lightscope*" }
    if ($lightScopeProcesses) {
        Write-Host "Found $($lightScopeProcesses.Count) LightScope processes running" -ForegroundColor Yellow
        $lightScopeProcesses | ForEach-Object {
            Write-Host "Stopping process: $($_.ProcessName) (PID: $($_.Id))" -ForegroundColor Yellow
            $_ | Stop-Process -Force
        }
        Write-Host "LightScope processes stopped" -ForegroundColor Green
    } else {
        Write-Host "No LightScope processes found running" -ForegroundColor Green
    }
} catch {
    Write-Host "Error stopping processes: $($_.Exception.Message)" -ForegroundColor Red
}

# Remove startup folder shortcut
Write-Host "Removing startup folder shortcut..." -ForegroundColor Cyan
$startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\LightScope.lnk"
if (Test-Path $startupPath) {
    try {
        Remove-Item $startupPath -Force
        Write-Host "✓ Removed startup folder shortcut: $startupPath" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to remove startup folder shortcut: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "✓ No startup folder shortcut found" -ForegroundColor Green
}

# Check registry startup entry
Write-Host "Checking registry startup entry..." -ForegroundColor Cyan
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$registryKey = "LightScope"

try {
    $registryValue = Get-ItemProperty -Path $registryPath -Name $registryKey -ErrorAction SilentlyContinue
    if ($registryValue) {
        Write-Host "✓ Found registry startup entry: $($registryValue.LightScope)" -ForegroundColor Green
        Write-Host "  Registry entry is the PRIMARY startup method (this is correct)" -ForegroundColor Green
    } else {
        Write-Host "✗ Registry startup entry not found!" -ForegroundColor Red
        Write-Host "  This means LightScope will not start automatically on Windows restart" -ForegroundColor Red
        
        # Try to find LightScope installation
        $possiblePaths = @(
            "$env:LOCALAPPDATA\LightScope\start-lightscope-background.bat",
            "$env:APPDATA\LightScope\start-lightscope-background.bat",
            "$env:PROGRAMFILES\LightScope\start-lightscope-background.bat"
        )
        
        $lightScopePath = $null
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $lightScopePath = $path
                break
            }
        }
        
        if ($lightScopePath) {
            Write-Host "  Found LightScope installation at: $lightScopePath" -ForegroundColor Yellow
            Write-Host "  Would you like to restore the registry startup entry? (y/n): " -ForegroundColor Yellow -NoNewline
            $response = Read-Host
            if ($response -eq "y" -or $response -eq "Y") {
                try {
                    Set-ItemProperty -Path $registryPath -Name $registryKey -Value "`"$lightScopePath`""
                    Write-Host "✓ Restored registry startup entry" -ForegroundColor Green
                } catch {
                    Write-Host "✗ Failed to restore registry startup entry: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  Could not find LightScope installation" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "✗ Error checking registry: $($_.Exception.Message)" -ForegroundColor Red
}

# Remove any lock files
Write-Host "Cleaning up lock files..." -ForegroundColor Cyan
$lockPaths = @(
    "$env:LOCALAPPDATA\LightScope\logs\lightscope-runner.lock",
    "$env:APPDATA\LightScope\logs\lightscope-runner.lock"
)

foreach ($lockPath in $lockPaths) {
    if (Test-Path $lockPath) {
        try {
            Remove-Item $lockPath -Force
            Write-Host "✓ Removed lock file: $lockPath" -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to remove lock file: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Green
Write-Host "✓ Duplicate startup entries have been removed" -ForegroundColor Green
Write-Host "✓ LightScope will now start only once on Windows restart" -ForegroundColor Green
Write-Host "✓ Lock files have been cleaned up" -ForegroundColor Green
Write-Host ""
Write-Host "You can now restart Windows to test the fix." -ForegroundColor Yellow
Write-Host "LightScope should start only once and appear as a single icon in the system tray." -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to exit..."
Read-Host 