# LightScope Firewall Configuration

## Overview

LightScope now includes automatic Windows Firewall configuration during installation to allow honeypot services to receive incoming connections. This resolves the issue where ports could be opened but Windows Firewall blocked external traffic.

## Changes Made

### 1. Installer Requirements
- **Admin Privileges**: The installer now requires administrator privileges (`RequestExecutionLevel admin`) to configure firewall rules
- **Automatic Configuration**: Firewall rules are automatically created during installation
- **Clean Removal**: Firewall rules are automatically removed during uninstallation

### 2. Firewall Rules Created

The installer creates three firewall rules:

#### LightScope Honeypot Services
- **Direction**: Inbound
- **Protocol**: TCP
- **Ports**: 21,22,23,25,53,80,110,135,139,143,443,445,993,995,1433,1521,3306,3389,5432,5900,8080,8443
- **Program**: Specific Python executable (virtual environment or system Python)
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows common honeypot services to receive connections

#### LightScope Dynamic Ports
- **Direction**: Inbound
- **Protocol**: TCP
- **Ports**: 32768-65535 (Windows ephemeral port range)
- **Program**: Specific Python executable
- **Profiles**: Private, Domain (not Public for security)
- **Purpose**: Allows dynamic honeypot services on high ports

#### LightScope Outbound
- **Direction**: Outbound
- **Protocol**: TCP
- **Program**: Specific Python executable
- **Profiles**: Private, Domain, Public
- **Purpose**: Allows LightScope to communicate with external servers

### 3. Python Executable Detection

The installer intelligently detects and configures firewall rules for:
1. **Virtual Environment Python**: `%LOCALAPPDATA%\LightScope\venv\Scripts\python.exe` (preferred)
2. **System Python**: Found via `where python` command
3. **Fallback**: Generic `python.exe` if specific path not found

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
- **Common Ports**: Allowed on all profiles (Private, Domain, Public)
- **Dynamic Ports**: Limited to Private and Domain profiles only
- **Program-Specific**: Rules target specific Python executable, not all Python processes

### Port Selection
- **Honeypot Ports**: Common service ports that attackers typically target
- **Dynamic Range**: Windows ephemeral ports (32768-65535) for dynamic services
- **Avoided Ports**: No rules for system-critical ports below 1024 except common honeypot services

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
# Test if port 22 is accessible
Test-NetConnection -ComputerName localhost -Port 22
```

### Manual Rule Creation
```powershell
# Create rule for specific Python executable
New-NetFirewallRule -DisplayName "LightScope Honeypot Services" -Direction Inbound -Protocol TCP -LocalPort 22,23,80,443 -Program "C:\Path\To\python.exe" -Action Allow -Profile Private,Domain,Public
```

### Remove Rules
```powershell
# Remove all LightScope firewall rules
Remove-NetFirewallRule -DisplayName "*LightScope*"
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