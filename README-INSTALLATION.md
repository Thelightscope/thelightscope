# LightScope dpkg Installation Guide

This guide explains how to build, sign, and deploy LightScope using the new dpkg-based installation system.

## Overview

The new installation system provides:
- **dpkg package**: Easy installation and removal on Debian/Ubuntu systems
- **systemd service**: Automatic startup, restart on crashes, proper logging
- **Auto-updates**: Secure automatic updates from thelightscope.com
- **Code signing**: Cryptographic verification of updates for security

## Directory Structure

```
thelightscope/
├── lightscope/
│   └── lightscope_core.py          # Main LightScope code
├── debian_package/                 # dpkg package structure
│   ├── DEBIAN/
│   │   ├── control                 # Package metadata
│   │   ├── postinst               # Post-installation script
│   │   └── prerm                  # Pre-removal script
│   ├── lib/systemd/system/
│   │   └── lightscope.service     # systemd service file
│   ├── opt/lightscope/bin/
│   │   └── lightscope-runner.py   # Auto-update runner script
│   └── usr/share/lightscope/
│       └── config.ini.example     # Configuration template
├── build-dpkg.sh                  # Build script
├── sign-and-upload.py              # Code signing script
└── README-INSTALLATION.md         # This file
```

## Building the Package

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y dpkg-dev lintian python3-pip

# Install Python dependencies for signing
pip3 install cryptography
```

### Build Process

1. **Build the dpkg package:**
   ```bash
   cd thelightscope
   ./build-dpkg.sh
   ```

   This will:
   - Extract version from `lightscope_core.py`
   - Create the package structure
   - Build `lightscope_x.x.x_amd64.deb`

2. **Install the package:**
   ```bash
   sudo dpkg -i lightscope_*.deb
   sudo apt-get install -f  # Fix any dependency issues
   ```
   
   The service will start automatically after installation!

## Code Signing and Security

### Generate Signing Keys (One-time setup)

```bash
# Generate RSA key pair for signing
python3 sign-and-upload.py --generate-keys
```

This creates:
- `lightscope-private.pem` (keep secure!)
- `lightscope-public.pem` (distribute with updates)

### Sign a Release

```bash
# Sign the current version
python3 sign-and-upload.py --verify
```

This creates in `signed_output/`:
- `lightscope_core.py` (signed file)
- `lightscope_core.py.sig` (cryptographic signature)
- `lightscope-public.pem` (public key for verification)
- `version.json` (version metadata)

### Upload to Server

Upload the signed files to your web server:

```bash
# Upload to https://thelightscope.com/latest/
scp signed_output/* user@server:/path/to/website/latest/

# Update version API endpoint
curl -X POST https://thelightscope.com/api/version \
     -H "Content-Type: application/json" \
     -d '@signed_output/version.json'
```

## Service Management

### After Installation

The dpkg package automatically:
1. Creates `lightscope` user
2. Sets up virtual environment in `/opt/lightscope/venv`
3. Configures systemd service
4. Sets network capabilities on Python interpreter
5. **Starts the service immediately** - LightScope begins monitoring right away!

### Service Commands

```bash
# Check status (service starts automatically after install)
sudo systemctl status lightscope

# Start LightScope (if stopped)
sudo systemctl start lightscope

# Enable auto-start on boot (done automatically during install)
sudo systemctl enable lightscope

# View logs
sudo journalctl -u lightscope -f

# Restart service
sudo systemctl restart lightscope

# Stop service
sudo systemctl stop lightscope
```

### Configuration

Edit `/opt/lightscope/config/config.ini`:

```ini
[Settings]
# Auto-generated unique database name
database = 20241201_abcdefghijklmnop

# Auto-generated randomization key
randomization_key = randomization_key_qrstuvwxyzabcdef

# Enable automatic updates
autoupdate = yes

# Update check interval (hours)
update_check_interval = 24
```

## Auto-Update System

### How It Works

1. **Runner Script**: `lightscope-runner.py` wraps the core functionality
2. **Version Checking**: Checks thelightscope.com every 24 hours
3. **Secure Download**: Downloads signed updates only
4. **Signature Verification**: Verifies cryptographic signatures before installation
5. **Automatic Restart**: systemd restarts the service after updates

### Security Features

- **RSA-4096 signatures**: Strong cryptographic signing
- **Public key pinning**: Public key stored locally and verified
- **HTTPS-only downloads**: Encrypted transmission
- **Signature verification**: Files must be validly signed to install
- **Backup system**: Previous versions backed up before update

### Manual Update Check

```bash
# Check for updates manually
sudo systemctl restart lightscope

# Or check logs for update activity
sudo journalctl -u lightscope | grep -i update
```

## File Locations

After installation:

```
/opt/lightscope/
├── venv/                          # Python virtual environment
├── bin/
│   ├── lightscope-runner.py       # Auto-update wrapper
│   └── lightscope_core.py         # Main LightScope code
├── config/
│   ├── config.ini                 # Main configuration
│   └── lightscope-public.pem      # Public key for updates
├── logs/
│   └── lightscope-runner.log      # Runner logs
└── updates/
    └── lightscope_core_backup_*   # Backup files
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status lightscope

# Check logs
sudo journalctl -u lightscope -n 50

# Check Python capabilities
getcap /opt/lightscope/venv/bin/python3

# Should show: cap_net_raw,cap_net_admin+eip
```

### Update Issues

```bash
# Check runner logs
sudo tail -f /opt/lightscope/logs/lightscope-runner.log

# Manual update check
sudo -u lightscope /opt/lightscope/venv/bin/python3 \
    /opt/lightscope/bin/lightscope-runner.py --check-update
```

### Network Permission Issues

```bash
# Re-apply network capabilities
sudo setcap 'cap_net_raw,cap_net_admin+eip' \
    /opt/lightscope/venv/bin/python3
```

## Uninstallation

LightScope uninstalls completely by default (nuclear option):

### Complete Removal (Default)
```bash
# Remove LightScope and ALL data permanently
sudo dpkg -r lightscope
```
This will:
- ✅ Stop and disable the service
- ✅ Remove the package files
- ✅ Remove service definition
- ✅ Delete lightscope user account
- ✅ Delete `/opt/lightscope` directory completely
- ✅ Remove all logs and configuration
- ✅ Kill any running processes

**Note**: Both `dpkg -r` and `dpkg --purge` do complete cleanup.

### 3. Manual Cleanup (If Needed)
If you need to manually clean up after a failed uninstall:
```bash
# Stop all lightscope processes
sudo pkill -f lightscope

# Remove user and home directory
sudo userdel -r lightscope

# Remove any remaining files
sudo rm -rf /opt/lightscope
sudo rm -f /lib/systemd/system/lightscope.service
sudo rm -rf /usr/share/lightscope

# Reload systemd
sudo systemctl daemon-reload
```

## Development and Testing

### Test Package Before Distribution

```bash
# Build package
./build-dpkg.sh

# Test install in VM or container
sudo dpkg -i lightscope_*.deb

# Test service
sudo systemctl start lightscope
sudo systemctl status lightscope

# Test auto-update (point to test server)
# Edit UPDATE_CHECK_URL in lightscope-runner.py
```

### Server-Side Requirements

Your web server needs these endpoints:

1. **Version API**: `GET /api/version`
   ```json
   {
     "version": "0.0.102",
     "sha256": "abc123...",
     "download_url": "https://thelightscope.com/latest/lightscope_core.py"
   }
   ```

2. **Public Key**: `GET /api/public-key`
   - Returns the PEM-formatted public key

3. **File Downloads**: `GET /latest/`
   - `lightscope_core.py` (signed file)
   - `lightscope_core.py.sig` (signature)

## Migration from pip Installation

1. **Stop old installation**:
   ```bash
   # Stop any running lightscope processes
   pkill -f lightscope
   ```

2. **Backup configuration**:
   ```bash
   # Copy existing config.ini if you have one
   cp config.ini /tmp/lightscope-config-backup.ini
   ```

3. **Install dpkg version**:
   ```bash
   sudo dpkg -i lightscope_*.deb
   ```

4. **Migrate configuration**:
   ```bash
   # Copy settings to new location
   sudo cp /tmp/lightscope-config-backup.ini /opt/lightscope/config/config.ini
   sudo chown lightscope:lightscope /opt/lightscope/config/config.ini
   ```

5. **Start service**:
   ```bash
   sudo systemctl start lightscope
   ```

This new system provides much better reliability, security, and ease of management compared to the previous pip-based installation.

## Need Help?

If you encounter any issues during installation or have questions about LightScope, we're here to help!

**Contact Support:**
- **Email**: e@alumni.usc.edu
- **Response Time**: We typically respond within 24 hours 