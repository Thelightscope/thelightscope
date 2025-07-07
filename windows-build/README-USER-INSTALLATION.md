# LightScope Windows User Installation Guide

## Overview

LightScope now installs as a **user-level startup application** instead of a system service. This approach provides several benefits:

- ✅ **No administrator privileges required** for installation or operation
- ✅ **Runs when you log in** (not when the system boots)
- ✅ **Easier to manage** and troubleshoot
- ✅ **Better security** - runs with your user permissions only
- ✅ **Automatic updates** still work seamlessly

## Installation Process

1. **Download** the LightScope installer (`LightScope-x.x.x-Setup.exe`)
2. **Run the installer** - no admin privileges needed
3. **Follow the installation wizard** - it will:
   - Install to `%LOCALAPPDATA%\LightScope` (your user directory)
   - Create a Python virtual environment
   - Install all required dependencies
   - Add LightScope to your startup programs
   - Start LightScope immediately

## How It Works

### Startup Application
- LightScope automatically starts when you log in to Windows
- It runs in the background with your user permissions
- Uses a startup registry entry and shortcut in your startup folder

### File Locations
- **Installation**: `%LOCALAPPDATA%\LightScope` (typically `C:\Users\YourName\AppData\Local\LightScope`)
- **Logs**: `%LOCALAPPDATA%\LightScope\logs\`
- **Configuration**: `%LOCALAPPDATA%\LightScope\config\`
- **Updates**: `%LOCALAPPDATA%\LightScope\updates\`

## Managing LightScope

### Using the Start Menu
After installation, you can manage LightScope through the Start Menu:

- **LightScope** → **Start LightScope** - Start the application
- **LightScope** → **Stop LightScope** - Stop the application
- **LightScope** → **Restart LightScope** - Restart the application
- **LightScope** → **Status** - Check if LightScope is running
- **LightScope** → **View Logs** - Open the logs folder
- **LightScope** → **Configuration** - Open the config folder

### Using the Manager Script
You can also use the command-line manager:

```cmd
cd %LOCALAPPDATA%\LightScope
python lightscope-manager.py start      # Start LightScope
python lightscope-manager.py stop       # Stop LightScope  
python lightscope-manager.py restart    # Restart LightScope
python lightscope-manager.py status     # Check status
python lightscope-manager.py logs       # View recent logs
python lightscope-manager.py enable     # Enable startup
python lightscope-manager.py disable    # Disable startup
```

### Using the Batch File
For quick access, you can run the startup batch file:
```cmd
cd %LOCALAPPDATA%\LightScope
start-lightscope.bat
```

## Configuration

### User Mode Configuration
LightScope automatically runs in "user mode" with the following settings in `config\config.ini`:
```ini
[DEFAULT]
interface = auto
upload_url = https://thelightscope.com/upload
update_interval = 86400
user_mode = true
```

### Network Monitoring Requirements
LightScope requires Npcap for network packet capture:
- ✅ **Npcap is REQUIRED** - LightScope will not start without it
- ✅ **Updates and logging** work normally
- ✅ **Full network monitoring** with Npcap installed
- ⚠️ **Administrator privileges** may be needed for some network interfaces

**Npcap** (https://nmap.org/npcap/) is mandatory and must be installed before using LightScope.

## Troubleshooting

### LightScope Won't Start
1. **Check for Npcap**: Most startup failures are due to missing Npcap
   - Install Npcap from https://nmap.org/npcap/
   - Enable "WinPcap compatibility" during installation
2. **Check the logs**: Go to Start Menu → LightScope → View Logs
3. **Check Python installation**: Open Command Prompt and run `python --version`
4. **Restart**: Use Start Menu → LightScope → Restart LightScope
5. **Manual start**: Try running `start-lightscope.bat` directly

### Npcap Installation Issues
If you get "Npcap not found" errors:
1. **Download Npcap**: Go to https://nmap.org/npcap/
2. **Install as Administrator**: Right-click installer → "Run as Administrator"
3. **Enable WinPcap compatibility**: Check this box during installation
4. **Restart Windows**: Recommended after Npcap installation
5. **Verify installation**: Check if `C:\Windows\System32\Npcap\wpcap.dll` exists

### Missing Dependencies
If you get import errors:
1. Open Command Prompt as your user (not admin)
2. Navigate to the LightScope installation:
   ```cmd
   cd %LOCALAPPDATA%\LightScope
   ```
3. If using virtual environment:
   ```cmd
   venv\Scripts\pip install cryptography psutil requests dpkt
   ```
4. If using system Python:
   ```cmd
   pip install --user cryptography psutil requests dpkt
   ```

### Startup Issues
If LightScope doesn't start automatically:
1. Run: `python lightscope-manager.py enable`
2. Or manually add to startup via Windows Settings:
   - Open Windows Settings → Apps → Startup
   - Find LightScope and enable it

### Permission Issues
If you get permission errors:
1. **Check file permissions** in the installation directory
2. **Ensure antivirus** isn't blocking LightScope
3. **Try running as administrator** once to fix permissions, then switch back to user mode

## Uninstallation

1. **Stop LightScope**: Start Menu → LightScope → Stop LightScope
2. **Run uninstaller**: Start Menu → LightScope → Uninstall
3. **Or use Windows Settings**: Settings → Apps → LightScope → Uninstall

## Comparison with Service Installation

| Feature | User Application | System Service |
|---------|------------------|----------------|
| **Admin Rights** | ❌ Not required | ✅ Required |
| **Startup** | At user login | At system boot |
| **Permissions** | User-level | System-level |
| **Management** | Start Menu / Scripts | Service Manager |
| **Updates** | ✅ Automatic | ✅ Automatic |
| **Security** | ✅ Sandboxed | ⚠️ Full system access |
| **Troubleshooting** | ✅ Easier | ⚠️ More complex |

## Support

- **Logs**: Always check the logs first (`%LOCALAPPDATA%\LightScope\logs\`)
- **Configuration**: Check config files in `%LOCALAPPDATA%\LightScope\config\`
- **Process Status**: Use `python lightscope-manager.py status`
- **Manual Control**: Use the manager script for detailed control

The user-level installation provides better security and easier management while maintaining all the core functionality of LightScope. 