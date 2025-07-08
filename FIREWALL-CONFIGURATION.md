# LightScope Firewall Configuration

## Overview

LightScope now includes automatic Windows Firewall configuration during installation to allow honeypot services to receive incoming connections. This resolves the issue where ports could be opened but Windows Firewall blocked external traffic.

## Changes Made

### 1. Installer Requirements
- **Admin Privileges**: The installer now requires administrator privileges (`RequestExecutionLevel admin`) to configure firewall rules
- **Automatic Configuration**: Firewall rules are automatically created during installation
- **Clean Removal**: Firewall rules are automatically removed during uninstallation

### 2. Firewall Rules Created

The installer creates four firewall rules:

#### LightScope Dynamic Ports (Python)
- **Direction**: Inbound
- **Protocol**: TCP
- **Ports**: 1024-65535 (user port range)
- **Program**: System Python executable (python.exe)
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows LightScope services to receive connections on user ports

#### LightScope Outbound (Python)
- **Direction**: Outbound
- **Protocol**: TCP
- **Program**: System Python executable (python.exe)
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows LightScope to communicate with external servers

#### LightScope Dynamic Ports (Pythonw)
- **Direction**: Inbound
- **Protocol**: TCP
- **Ports**: 1024-65535 (user port range)
- **Program**: System Python windowed executable (pythonw.exe)
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows LightScope services to receive connections on user ports

#### LightScope Outbound (Pythonw)
- **Direction**: Outbound
- **Protocol**: TCP
- **Program**: System Python windowed executable (pythonw.exe)
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows LightScope to communicate with external servers

### 3. Python Executable Detection

The installer intelligently detects and configures firewall rules for:
1. **System Python**: Found via `where python` command (with newlines stripped)
2. **System Python Windowed**: Found via `where pythonw` command (with newlines stripped)
3. **Fallback**: Generic `python.exe` and `pythonw.exe` if specific paths not found

**Note**: The installer automatically strips newlines and whitespace from detected Python paths to prevent firewall rule corruption.

### 4. Installation Process

```
1. Check dependencies (Python, NPCAP)
2. Create virtual environment
3. Install Python packages
4. Configure Windows Firewall ← NEW
5. Create startup launchers
6. Configure automatic startup
```

### 5. Manual Firewall Management

A new PowerShell script `check-firewall-rules.ps1` is provided for manual firewall management:

```powershell
# Run as administrator
.\check-firewall-rules.ps1
```

Features:
- Display current LightScope firewall rules
- Find Python executable paths
- Create firewall rules manually
- Remove firewall rules
- Test port connectivity

## Security Considerations

### Firewall Rule Scope
- **Dynamic Ports**: Allowed on all profiles (Private, Domain, Public)
- **Program-Specific**: Rules target specific Python executable, not all Python processes

### Port Selection
- **Dynamic Range**: User ports (1024-65535) for all LightScope services
- **Avoided Ports**: No rules for system-critical ports below 1024

## Installation Impact

### Before (User-Level)
- No admin privileges required
- Firewall blocked incoming connections
- Honeypots could bind to ports but not receive external traffic

### After (Admin-Level)
- Admin privileges required for installation
- Firewall automatically configured
- Honeypots can receive external connections immediately

## Troubleshooting

### Check Firewall Rules
```powershell
# List all LightScope firewall rules
Get-NetFirewallRule -DisplayName "*LightScope*" | Format-Table DisplayName, Direction, Action, Enabled
```

### Test Port Connectivity
```powershell
# Test if a port in the dynamic range is accessible
Test-NetConnection -ComputerName localhost -Port 8080
```

### Check for Corrupted Firewall Rules
If firewall rules appear to exist but don't work, check for path corruption:
```powershell
# Check if firewall rule paths have illegal characters
Get-NetFirewallRule -DisplayName "*LightScope*" | ForEach-Object {
    $appFilter = $_ | Get-NetFirewallApplicationFilter
    $path = $appFilter.Program
    $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($path)
    $hasNewlines = ($pathBytes -contains 13) -or ($pathBytes -contains 10)
    Write-Host "$($_.DisplayName): Path has newlines = $hasNewlines"
    if ($hasNewlines) {
        Write-Host "  CORRUPTED RULE - needs to be recreated"
    }
}
```

### Fix Corrupted Firewall Rules
If you find corrupted rules (containing newlines), remove and recreate them:
```powershell
# Remove corrupted rules
Remove-NetFirewallRule -DisplayName "*LightScope*"

# Recreate with clean paths
$pythonPath = (Get-Command python).Source.Trim()
$pythonwPath = (Get-Command pythonw).Source.Trim()

New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Python)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program $pythonPath -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Outbound (Python)" -Direction Outbound -Protocol TCP -Program $pythonPath -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Pythonw)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program $pythonwPath -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Outbound (Pythonw)" -Direction Outbound -Protocol TCP -Program $pythonwPath -Action Allow -Profile Private,Domain,Public
```

### Manual Rule Creation
```powershell
# Create rules for system Python executables
New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Python)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program "C:\Path\To\python.exe" -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Outbound (Python)" -Direction Outbound -Protocol TCP -Program "C:\Path\To\python.exe" -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Pythonw)" -Direction Inbound -Protocol TCP -LocalPort 1024-65535 -Program "C:\Path\To\pythonw.exe" -Action Allow -Profile Private,Domain,Public
New-NetFirewallRule -DisplayName "LightScope Outbound (Pythonw)" -Direction Outbound -Protocol TCP -Program "C:\Path\To\pythonw.exe" -Action Allow -Profile Private,Domain,Public
```

### Remove Rules
```powershell
# Remove all LightScope firewall rules
Remove-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Python)"
Remove-NetFirewallRule -DisplayName "LightScope Outbound (Python)"
Remove-NetFirewallRule -DisplayName "LightScope Dynamic Ports (Pythonw)"
Remove-NetFirewallRule -DisplayName "LightScope Outbound (Pythonw)"
```

## File Changes

### Modified Files
- `lightscope-installer.nsi`
- `windows-build/lightscope-installer.nsi`

### New Files
- `check-firewall-rules.ps1`
- `FIREWALL-CONFIGURATION.md` (this file)

### Key Functions Added
- `ConfigureFirewall()` - Creates firewall rules during installation
- Firewall rule removal in uninstall section
- Python executable path detection and logging

## Testing

### Pre-Installation Testing
1. Verify admin privileges are requested
2. Check Python executable detection
3. Confirm firewall rule creation

### Post-Installation Testing
1. Verify firewall rules exist: `Get-NetFirewallRule -DisplayName "*LightScope*"`
2. Test port connectivity: `Test-NetConnection -ComputerName localhost -Port 22`
3. Check logs for firewall configuration messages

### Uninstallation Testing
1. Verify firewall rules are removed
2. Check no LightScope rules remain: `Get-NetFirewallRule -DisplayName "*LightScope*"`

## Best Practices

1. **Run installer as administrator** - Required for firewall configuration
2. **Review firewall rules** - Use `check-firewall-rules.ps1` to verify configuration
3. **Test connectivity** - Verify honeypot services can receive connections
4. **Monitor logs** - Check installation logs for firewall configuration status
5. **Update rules if needed** - Recreate rules if Python executable path changes

## Limitations

1. **Path Stability**: Firewall rules point to specific Python executable path
2. **Virtual Environment**: Rules become invalid if virtual environment is moved/recreated
3. **Multiple Environments**: Each Python executable needs separate firewall rules
4. **Admin Requirement**: Installation now requires administrator privileges

## Future Improvements

1. **Self-Contained Executable**: Bundle LightScope into single .exe to avoid path issues
2. **Dynamic Rule Updates**: Update firewall rules if Python path changes
3. **Selective Port Configuration**: Allow users to choose which ports to open
4. **Network Profile Detection**: Automatically adjust rules based on network profile 