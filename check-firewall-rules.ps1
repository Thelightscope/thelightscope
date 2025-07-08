#!/usr/bin/env powershell

# Check LightScope Firewall Rules
# This script displays current firewall rules for LightScope and allows manual firewall configuration

Write-Host "=== LightScope Firewall Rules Check ===" -ForegroundColor Green
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as administrator" -ForegroundColor Yellow
    Write-Host "Some firewall operations may require administrator privileges" -ForegroundColor Yellow
    Write-Host ""
}

# Function to display firewall rules
function Show-LightScopeFirewallRules {
    Write-Host "Current LightScope Firewall Rules:" -ForegroundColor Cyan
    Write-Host ""
    
    # Get all LightScope related firewall rules
    $rules = Get-NetFirewallRule -DisplayName "*LightScope*" -ErrorAction SilentlyContinue
    
    if ($rules) {
        foreach ($rule in $rules) {
            Write-Host "Rule: $($rule.DisplayName)" -ForegroundColor Green
            Write-Host "  Status: $($rule.Enabled)"
            Write-Host "  Direction: $($rule.Direction)"
            Write-Host "  Action: $($rule.Action)"
            Write-Host "  Profile: $($rule.Profile)"
            
            # Get port information
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            if ($portFilter) {
                Write-Host "  Protocol: $($portFilter.Protocol)"
                Write-Host "  Local Port: $($portFilter.LocalPort)"
            }
            
            # Get application information
            $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            if ($appFilter) {
                Write-Host "  Program: $($appFilter.Program)"
            }
            
            Write-Host ""
        }
    } else {
        Write-Host "No LightScope firewall rules found!" -ForegroundColor Red
        Write-Host ""
    }
}

# Function to find Python executable paths
function Find-PythonExecutables {
    Write-Host "Finding Python executable paths..." -ForegroundColor Cyan
    Write-Host ""
    
    $pythonPaths = @()
    
    # Check for LightScope virtual environment
    $localAppData = $env:LOCALAPPDATA
    $lightScopeVenv = "$localAppData\LightScope\venv\Scripts\python.exe"
    if (Test-Path $lightScopeVenv) {
        $pythonPaths += $lightScopeVenv
        Write-Host "✓ LightScope Virtual Environment: $lightScopeVenv" -ForegroundColor Green
    }
    
    # Check for system Python
    try {
        $systemPython = (Get-Command python -ErrorAction Stop).Source
        $pythonPaths += $systemPython
        Write-Host "✓ System Python: $systemPython" -ForegroundColor Green
    } catch {
        Write-Host "✗ System Python not found in PATH" -ForegroundColor Red
    }
    
    # Check for Python Launcher
    if (Test-Path "C:\Windows\py.exe") {
        Write-Host "✓ Python Launcher: C:\Windows\py.exe" -ForegroundColor Green
    }
    
    Write-Host ""
    return $pythonPaths
}

# Function to create firewall rules
function Create-LightScopeFirewallRules {
    param(
        [string]$PythonPath
    )
    
    if (-not $isAdmin) {
        Write-Host "ERROR: Administrator privileges required to create firewall rules" -ForegroundColor Red
        Write-Host "Please run this script as administrator" -ForegroundColor Red
        return
    }
    
    Write-Host "Creating firewall rules for: $PythonPath" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Find system Python
        try {
            $systemPython = (Get-Command python -ErrorAction Stop).Source.Trim()
        } catch {
            $systemPython = "python.exe"
        }
        
        # Find system pythonw
        try {
            $systemPythonw = (Get-Command pythonw -ErrorAction Stop).Source.Trim()
        } catch {
            $systemPythonw = "pythonw.exe"
        }
        
        # Create dynamic ports rule for python
        Write-Host "Creating dynamic ports rule for Python..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Python)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program $systemPython -Action Allow -Profile Private,Domain,Public -ErrorAction Stop
        Write-Host "✓ Dynamic ports rule for Python created" -ForegroundColor Green
        
        # Create outbound rule for python
        Write-Host "Creating outbound rule for Python..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName "LightScope Outbound (Python)" -Direction Outbound -Protocol TCP -Program $systemPython -Action Allow -Profile Private,Domain,Public -ErrorAction Stop
        Write-Host "✓ Outbound rule for Python created" -ForegroundColor Green
        
        # Create dynamic ports rule for pythonw
        Write-Host "Creating dynamic ports rule for Pythonw..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Pythonw)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program $systemPythonw -Action Allow -Profile Private,Domain,Public -ErrorAction Stop
        Write-Host "✓ Dynamic ports rule for Pythonw created" -ForegroundColor Green
        
        # Create outbound rule for pythonw
        Write-Host "Creating outbound rule for Pythonw..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName "LightScope Outbound (Pythonw)" -Direction Outbound -Protocol TCP -Program $systemPythonw -Action Allow -Profile Private,Domain,Public -ErrorAction Stop
        Write-Host "✓ Outbound rule for Pythonw created" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "All firewall rules created successfully!" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR: Failed to create firewall rules: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove firewall rules
function Remove-LightScopeFirewallRules {
    if (-not $isAdmin) {
        Write-Host "ERROR: Administrator privileges required to remove firewall rules" -ForegroundColor Red
        Write-Host "Please run this script as administrator" -ForegroundColor Red
        return
    }
    
    Write-Host "Removing LightScope firewall rules..." -ForegroundColor Cyan
    Write-Host ""
    
    try {
        Remove-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Python)" -ErrorAction SilentlyContinue
        Write-Host "✓ Removed dynamic ports rule for Python" -ForegroundColor Green
        
        Remove-NetFirewallRule -DisplayName "LightScope Outbound (Python)" -ErrorAction SilentlyContinue
        Write-Host "✓ Removed outbound rule for Python" -ForegroundColor Green
        
        Remove-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Pythonw)" -ErrorAction SilentlyContinue
        Write-Host "✓ Removed dynamic ports rule for Pythonw" -ForegroundColor Green
        
        Remove-NetFirewallRule -DisplayName "LightScope Outbound (Pythonw)" -ErrorAction SilentlyContinue
        Write-Host "✓ Removed outbound rule for Pythonw" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "All firewall rules removed successfully!" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR: Failed to remove firewall rules: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
Show-LightScopeFirewallRules
$pythonPaths = Find-PythonExecutables

# Interactive menu
while ($true) {
    Write-Host "=== Actions ===" -ForegroundColor Cyan
    Write-Host "1. Refresh firewall rules display"
    Write-Host "2. Create firewall rules"
    Write-Host "3. Remove firewall rules"
    Write-Host "4. Test port connectivity"
    Write-Host "5. Exit"
    Write-Host ""
    
    $choice = Read-Host "Choose an action (1-5)"
    
    switch ($choice) {
        "1" {
            Clear-Host
            Show-LightScopeFirewallRules
        }
        "2" {
            if ($pythonPaths.Count -eq 0) {
                Write-Host "No Python executables found!" -ForegroundColor Red
            } elseif ($pythonPaths.Count -eq 1) {
                Create-LightScopeFirewallRules -PythonPath $pythonPaths[0]
            } else {
                Write-Host "Multiple Python executables found:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $pythonPaths.Count; $i++) {
                    Write-Host "  $($i + 1). $($pythonPaths[$i])"
                }
                $pythonChoice = Read-Host "Choose Python executable (1-$($pythonPaths.Count))"
                $pythonIndex = [int]$pythonChoice - 1
                if ($pythonIndex -ge 0 -and $pythonIndex -lt $pythonPaths.Count) {
                    Create-LightScopeFirewallRules -PythonPath $pythonPaths[$pythonIndex]
                } else {
                    Write-Host "Invalid choice" -ForegroundColor Red
                }
            }
        }
        "3" {
            Remove-LightScopeFirewallRules
        }
        "4" {
            Write-Host "Testing common honeypot ports..." -ForegroundColor Cyan
            $testPorts = @(22, 23, 80, 443, 3389, 5900)
            foreach ($port in $testPorts) {
                $result = Test-NetConnection -ComputerName localhost -Port $port -InformationLevel Quiet
                $status = if ($result) { "OPEN" } else { "CLOSED/FILTERED" }
                $color = if ($result) { "Green" } else { "Red" }
                Write-Host "  Port $port`: $status" -ForegroundColor $color
            }
        }
        "5" {
            Write-Host "Exiting..." -ForegroundColor Green
            break
        }
        default {
            Write-Host "Invalid choice. Please select 1-5." -ForegroundColor Red
        }
    }
    
    Write-Host ""
} 