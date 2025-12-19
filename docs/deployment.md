# LightScope dpkg Deployment Solution

## Summary

I've created a complete dpkg-based installation and auto-update system for LightScope that addresses all your requirements:

### ✅ Requirements Met

1. **dpkg installer** - Complete Debian package structure with proper dependencies
2. **systemd service** - Automatic startup, crash recovery, and proper service management
3. **Auto-update system** - Secure downloads from thelightscope.com with version checking
4. **Code signing** - RSA-4096 cryptographic signatures for security
5. **No pip dependency** - Self-contained with direct downloads

## Key Components

### 1. Package Structure
```
debian_package/
├── DEBIAN/
│   ├── control          # Package metadata and dependencies
│   ├── postinst         # Creates user, venv, sets capabilities
│   └── prerm           # Cleanup on removal
├── lib/systemd/system/
│   └── lightscope.service  # Service definition with restart policies
├── opt/lightscope/bin/
│   └── lightscope-runner.py  # Auto-update wrapper
└── usr/share/lightscope/
    └── config.ini.example   # Configuration template
```

### 2. Auto-Update System
- **Version checking**: Polls https://thelightscope.com/api/version every 24 hours
- **Secure downloads**: HTTPS-only with cryptographic verification
- **Signature validation**: RSA-4096 signatures prevent tampering
- **Backup system**: Previous versions backed up before updates
- **Automatic restart**: systemd restarts service after updates

### 3. Security Features
- **Code signing**: RSA-4096 signatures on all updates
- **Public key pinning**: Public key stored locally for verification
- **Isolated execution**: Dedicated user account with minimal privileges
- **Network capabilities**: Only necessary network permissions granted
- **systemd hardening**: Security restrictions in service file

### 4. Service Management
- **Automatic startup**: Enabled on system boot
- **Crash recovery**: Restarts automatically on failures
- **Rate limiting**: Prevents rapid restart loops
- **Proper logging**: Journald integration with structured logging
- **Resource limits**: Controlled resource usage

## Installation Process

### For End Users (Simple)
```bash
# Download and install
wget https://thelightscope.com/latest/lightscope_x.x.x_amd64.deb
sudo dpkg -i lightscope_*.deb
# Service starts automatically - monitoring begins immediately!
```

### For Developers (Build from source)
```bash
# Build package
cd thelightscope
./build-dpkg.sh

# Generate signing keys (one-time)
python3 sign-and-upload.py --generate-keys

# Sign release
python3 sign-and-upload.py --verify

# Test locally
sudo dpkg -i lightscope_*.deb
```

## Advantages Over pip Installation

| Feature | Old (pip) | New (dpkg) |
|---------|-----------|------------|
| Installation | Manual setup required | One-command install |
| Dependencies | Manual pip install | Automatic via dpkg |
| Service management | Manual process management | systemd integration |
| Auto-updates | None | Secure automatic updates |
| Security | Basic | Code signing + verification |
| Uninstall | Manual cleanup | `dpkg -r lightscope` |
| System integration | Poor | Full systemd integration |
| Logging | Ad-hoc | Structured journald logging |
| Permissions | Manual capability setting | Automatic during install |

## File Locations After Installation

```
/opt/lightscope/              # Main installation directory
├── venv/                     # Python virtual environment
├── bin/
│   ├── lightscope-runner.py  # Auto-update wrapper
│   └── lightscope_core.py    # Main LightScope code
├── config/
│   ├── config.ini           # Configuration file
│   └── lightscope-public.pem # Public key for updates
├── logs/
│   └── lightscope-runner.log # Application logs
└── updates/
    └── *_backup_*.py        # Backup files

/lib/systemd/system/
└── lightscope.service       # Service definition

/usr/share/lightscope/
└── config.ini.example      # Configuration template
```

## Management Commands

```bash
# Service control
sudo systemctl start lightscope
sudo systemctl stop lightscope
sudo systemctl restart lightscope
sudo systemctl status lightscope

# Logs
sudo journalctl -u lightscope -f
sudo tail -f /opt/lightscope/logs/lightscope-runner.log

# Configuration
sudo nano /opt/lightscope/config/config.ini

# Updates (automatic, but can check manually)
sudo systemctl restart lightscope  # Triggers update check
```

## Server-Side Setup Required

You'll need to set up these endpoints on thelightscope.com:

1. **Version API** (`/api/version`):
   ```json
   {
     "version": "0.0.102",
     "sha256": "abc123...",
     "download_url": "https://thelightscope.com/latest/lightscope_core.py"
   }
   ```

2. **Public Key** (`/api/public-key`):
   - Returns the PEM-formatted public key

3. **File Downloads** (`/latest/`):
   - `lightscope_core.py` (signed file)
   - `lightscope_core.py.sig` (signature)

## Security Model

1. **Code integrity**: All updates cryptographically signed
2. **Transport security**: HTTPS-only downloads
3. **Key management**: Public key pinning prevents MITM attacks
4. **Process isolation**: Runs as dedicated non-root user
5. **Capability model**: Only necessary network capabilities granted
6. **Audit trail**: All update activities logged

## Testing and Validation

Use the provided test script:
```bash
cd thelightscope
./test-build.sh
```

This will:
1. Build the dpkg package
2. Generate test signing keys
3. Sign the code
4. Validate the complete process

## Production Deployment Checklist

- [ ] Generate production signing keys with `--generate-keys`
- [ ] Secure the private key (offline storage recommended)
- [ ] Set up web server endpoints for version API and downloads
- [ ] Test the complete update cycle
- [ ] Configure monitoring for the systemd service
- [ ] Set up log rotation for application logs
- [ ] Document the signing and release process for your team

## Uninstallation

LightScope uses the "nuclear option" by default - complete removal:

### Complete Removal (Default)
```bash
sudo dpkg -r lightscope    # Nuclear option - removes everything
```
- ✅ Stops and disables service
- ✅ Removes package files
- ✅ Deletes lightscope user account
- ✅ Removes `/opt/lightscope` directory completely
- ✅ Cleans up all logs and configuration

**Clean slate**: Both `dpkg -r` and `dpkg --purge` do complete cleanup.

This solution provides enterprise-grade deployment and update capabilities while maintaining security and ease of use. 