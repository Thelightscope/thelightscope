# LightScope Windows Installation and Deployment Guide

This guide covers building Windows installers and deploying LightScope on Windows systems.

## Overview

The Windows implementation provides the same functionality as the Linux version:
- **Automatic startup** on system boot via Windows Service
- **Automatic crash recovery** with exponential backoff
- **Secure auto-updates** with digital signature verification
- **Service management** through Windows Service Control Manager
- **Professional installer** with dependency checking

## Files Created

| File | Purpose |
|------|---------|
| `lightscope-service-windows.py` | Windows Service wrapper |
| `lightscope-runner-windows.py` | Runner with auto-update capability |
| `lightscope-installer.nsi` | NSIS installer script |
| `build-windows-installer.ps1` | PowerShell build script |

## Prerequisites for Building

### Required Software

1. **Python 3.8+** - https://python.org/downloads/
2. **NSIS (Nullsoft Scriptable Install System)** - https://nsis.sourceforge.io/
3. **Windows PowerShell** (included with Windows)

### Required Python Packages
```bash
pip install cryptography psutil requests dpkt pywin32
```

### Optional for Code Signing
- **Windows SDK** (for SignTool.exe)
- **Code signing certificate** (.pfx file)

## Building the Windows Installer

### Automatic Build (No Arguments Needed)
```powershell
# Navigate to the thelightscope directory
cd thelightscope

# Build installer automatically (like Linux dpkg script)
.\build-windows-installer.ps1
```

The script automatically:
- ✅ Cleans previous build artifacts  
- ✅ Checks and installs dependencies
- ✅ Builds the installer
- ✅ Looks for certificates and signs if found
- ✅ Creates distribution packages
- ✅ Shows deployment instructions

### Code Signing (Automatic Detection)
Place any of these certificate files in the project directory:
- `lightscope-cert.pfx`
- `certificate.pfx` 
- `code-signing.pfx`
- `lightscope.pfx`

The script will automatically detect and use the certificate for signing.

### Build Output

The build process creates:
- `windows-output/LightScope-{version}-Setup.exe` - Windows installer
- `windows-output/lightscope_v{version}_windows.zip` - Distribution package
- `windows-output/distribution/` - Files for manual installation

## Installation

### For End Users

1. **Download** `LightScope-{version}-Setup.exe`
2. **Right-click** and select "Run as Administrator"
3. **Follow** the installation wizard
4. The service starts automatically after installation

### Prerequisites Check

The installer automatically checks for:
- **Python 3.8+** - Opens download page if missing
- **Npcap** - Opens download page if missing
- **Python packages** - Installs automatically

### Installation Locations

- **Program Files**: `C:\Program Files\LightScope\`
- **Configuration**: `C:\Program Files\LightScope\config\`
- **Logs**: `C:\Program Files\LightScope\logs\`
- **Updates**: `C:\Program Files\LightScope\updates\`

## Service Management

### Using Windows Services

1. **Open Services** (services.msc)
2. **Find "LightScope Network Security Monitor"**
3. **Right-click** for Start/Stop/Restart options

### Using Command Line

```cmd
# Check service status
sc query LightScope

# Start service
sc start LightScope

# Stop service
sc stop LightScope

# View service configuration
sc qc LightScope
```

### Using Python Scripts

```cmd
# Navigate to installation directory
cd "C:\Program Files\LightScope\bin"

# Service management
python lightscope-service-windows.py start
python lightscope-service-windows.py stop
python lightscope-service-windows.py restart
```

## Manual Installation

If you prefer manual installation:

### Step 1: Install Dependencies
```cmd
# Install Python from https://python.org/
# Install Npcap from https://nmap.org/npcap/

# Install Python packages
pip install cryptography psutil requests dpkt pywin32
```

### Step 2: Create Directory Structure
```cmd
mkdir "C:\Program Files\LightScope"
mkdir "C:\Program Files\LightScope\bin"
mkdir "C:\Program Files\LightScope\config"
mkdir "C:\Program Files\LightScope\logs"
mkdir "C:\Program Files\LightScope\updates"
```

### Step 3: Copy Files
Copy these files to `C:\Program Files\LightScope\bin\`:
- `lightscope_core.py`
- `lightscope-service-windows.py`
- `lightscope-runner-windows.py`

Copy to `C:\Program Files\LightScope\config\`:
- `lightscope-public.pem` (for updates)

### Step 4: Install and Start Service
```cmd
cd "C:\Program Files\LightScope\bin"
python lightscope-service-windows.py install
python lightscope-service-windows.py start
```

## Configuration

### Config File Location
`C:\Program Files\LightScope\config\config.ini`

### Sample Configuration
```ini
[DEFAULT]
interface = auto
upload_url = https://thelightscope.com/upload
update_interval = 86400
```

## Auto-Updates

### How It Works
1. **Daily check** for new versions at startup and every 24 hours
2. **Downloads** new version from `https://thelightscope.com/latest/`
3. **Verifies** digital signature using bundled public key
4. **Backs up** current version before updating
5. **Installs** new version and restarts service

### Update URLs
- Version info: `https://thelightscope.com/latest/version`
- Core file: `https://thelightscope.com/latest/lightscope_core.py`
- Signature: `https://thelightscope.com/latest/lightscope_core.py.sig`

### Disabling Updates
To disable auto-updates, remove or rename the public key file:
```cmd
rename "C:\Program Files\LightScope\config\lightscope-public.pem" "lightscope-public.pem.disabled"
```

## Logging

### Service Logs
- **Location**: `C:\Program Files\LightScope\logs\`
- **Files**: 
  - `lightscope-service.log` - Service wrapper logs
  - `lightscope-runner.log` - Runner and update logs

### Windows Event Log
- **Location**: Windows Logs > Application
- **Source**: LightScope
- **Events**: Service start/stop, errors

### Viewing Logs
```cmd
# View latest service log
type "C:\Program Files\LightScope\logs\lightscope-service.log"

# View latest runner log  
type "C:\Program Files\LightScope\logs\lightscope-runner.log"

# View Windows Event Log
eventvwr.msc
```

## Troubleshooting

### Service Won't Start

1. **Check dependencies**:
   ```cmd
   python --version
   python -c "import dpkt, psutil, requests, cryptography"
   ```

2. **Check Npcap installation**:
   ```cmd
   dir C:\Windows\System32\wpcap.dll
   dir C:\Windows\System32\Packet.dll
   ```

3. **Check permissions**:
   - Service must run as Administrator
   - Verify folder permissions on `C:\Program Files\LightScope`

4. **Check logs**:
   ```cmd
   type "C:\Program Files\LightScope\logs\lightscope-service.log"
   ```

### Updates Failing

1. **Check internet connectivity**:
   ```cmd
   curl https://thelightscope.com/latest/version
   ```

2. **Verify public key**:
   ```cmd
   dir "C:\Program Files\LightScope\config\lightscope-public.pem"
   ```

3. **Check update logs**:
   ```cmd
   type "C:\Program Files\LightScope\logs\lightscope-runner.log"
   ```

### Performance Issues

1. **Check system resources**:
   - Monitor CPU and memory usage in Task Manager
   - Look for process `python.exe` running as service

2. **Review configuration**:
   - Ensure appropriate network interface is selected
   - Check upload URL accessibility

## Uninstallation

### Using Add/Remove Programs
1. **Open** Settings > Apps > Apps & features
2. **Search** for "LightScope"
3. **Click** Uninstall

### Using Start Menu
1. **Open** Start Menu
2. **Navigate** to LightScope folder
3. **Click** Uninstall

### Manual Uninstallation
```cmd
# Stop and remove service
cd "C:\Program Files\LightScope\bin"
python lightscope-service-windows.py stop
python lightscope-service-windows.py uninstall

# Remove installation directory
rmdir /s "C:\Program Files\LightScope"

# Remove registry entries (optional)
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\LightScope /f
```

## Distribution

### For Website Download
1. **Upload** `LightScope-{version}-Setup.exe` to your web server
2. **Update** download links on your website
3. **Test** download and installation

### For Enterprise Deployment
1. **Use** Group Policy for automated deployment
2. **Deploy** via System Center Configuration Manager
3. **Script** installation with PowerShell:
   ```powershell
   Start-Process -FilePath "LightScope-{version}-Setup.exe" -ArgumentList "/S" -Wait
   ```

## Security Considerations

### Service Security
- **Runs as Local System** for packet capture capabilities
- **Limited permissions** through service security descriptor
- **Automatic restart** on failure with rate limiting

### Update Security
- **Digital signatures** verify update authenticity
- **HTTPS download** ensures transport security
- **Backup and rollback** capability for failed updates

### Network Security
- **Encrypted uploads** to server
- **No inbound connections** accepted
- **Minimal attack surface** with service isolation

## Comparison with Linux Version

| Feature | Windows | Linux |
|---------|---------|-------|
| Service Management | Windows Service | systemd |
| Auto-start | Service Control Manager | systemd |
| Process Monitoring | Service wrapper | systemd watchdog |
| Crash Recovery | Exponential backoff | systemd restart |
| Logging | Windows Event Log + files | journald + files |
| Updates | Same secure mechanism | Same secure mechanism |
| Installer | NSIS | dpkg/rpm |
| Permissions | Local System | CAP_NET_RAW |

## Development

### Building from Source

1. **Clone repository**
2. **Install build dependencies**
3. **Run build script**:
   ```powershell
   .\build-windows-installer.ps1 -Clean
   ```

### Testing

1. **Test on clean Windows VM**
2. **Verify service installation**
3. **Test auto-updates**
4. **Test crash recovery**
5. **Test uninstallation**

### Code Signing

For production releases:
1. **Obtain code signing certificate**
2. **Install Windows SDK**
3. **Build with signing**:
   ```powershell
   .\build-windows-installer.ps1 -Sign -CertPath "cert.pfx" -CertPassword "password"
   ```

## Support

For issues or questions:
- **Website**: https://thelightscope.com/
- **Email**: e@alumni.usc.edu
- **Documentation**: https://thelightscope.com/docs/

## License

Same license as the main LightScope project. 