#!/bin/bash
set -e

# Build script for LightScope macOS Application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-macos"
PACKAGE_NAME="LightScope"
APP_DIR="$BUILD_DIR/$PACKAGE_NAME.app"

# Get version from lightscope_core.py
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from lightscope_core.py"
    exit 1
fi

echo "Building LightScope v$VERSION for macOS..."

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create macOS application bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Resources/bin"
mkdir -p "$APP_DIR/Contents/Resources/config"
mkdir -p "$APP_DIR/Contents/Resources/logs"

# Copy the actual lightscope_core.py
echo "Copying lightscope/lightscope_core.py (v$VERSION)..."
cp lightscope/lightscope_core.py "$APP_DIR/Contents/Resources/bin/"

# Copy the lightscope-runner.py
echo "Copying lightscope-runner.py..."
cp debian_package/opt/lightscope/bin/lightscope-runner.py "$APP_DIR/Contents/Resources/bin/"

# Get runner version for logging
RUNNER_VERSION=$(grep -o 'runner_version = "[^"]*"' "$APP_DIR/Contents/Resources/bin/lightscope-runner.py" | sed 's/runner_version = "\(.*\)"/\1/')
if [ -n "$RUNNER_VERSION" ]; then
    echo "Runner version: $RUNNER_VERSION"
else
    echo "Warning: Could not extract runner version"
fi

# Copy python-libpcap directory for local installation
if [ -d "python-libpcap" ]; then
    echo "Copying python-libpcap directory..."
    cp -r python-libpcap "$APP_DIR/Contents/Resources/"
else
    echo "Warning: python-libpcap directory not found"
fi

# Copy configuration example
echo "Copying configuration files..."
cp debian_package/usr/share/lightscope/config.ini.example "$APP_DIR/Contents/Resources/config/"

# Create Info.plist for the app bundle
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>LightScope</string>
    <key>CFBundleExecutable</key>
    <string>lightscope-launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.thelightscope.lightscope</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LightScope</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Create the main launcher script
cat > "$APP_DIR/Contents/MacOS/lightscope-launcher" << 'EOF'
#!/bin/bash

# LightScope macOS Launcher
# This script sets up the environment and runs LightScope

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$APP_DIR/Resources"
VENV_PATH="$RESOURCES_DIR/venv"
LOGS_DIR="$RESOURCES_DIR/logs"
CONFIG_DIR="$RESOURCES_DIR/config"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Log file for the launcher
LOG_FILE="$LOGS_DIR/lightscope-launcher.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "Starting LightScope launcher..."

# Check BPF permissions
check_bpf_permissions() {
    log "Checking BPF permissions..."
    
    # Check if we can access BPF devices
    BPF_ACCESSIBLE=false
    for bpf_dev in /dev/bpf*; do
        if [ -e "$bpf_dev" ] && [ -r "$bpf_dev" ]; then
            BPF_ACCESSIBLE=true
            break
        fi
    done
    
    if [ "$BPF_ACCESSIBLE" = false ]; then
        log "BPF devices not accessible, packet capture may fail"
        log "Consider running: sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh"
        return 1
    else
        log "BPF permissions OK"
        return 0
    fi
}

# Check if virtual environment exists, create if not
if [ ! -d "$VENV_PATH" ]; then
    log "Creating Python virtual environment..."
    python3 -m venv "$VENV_PATH"
    
    # Activate and install dependencies
    source "$VENV_PATH/bin/activate"
    
    log "Installing dependencies..."
    pip install --upgrade pip
    pip install dpkt psutil requests cryptography
    
    # Install local python-libpcap if available
    if [ -d "$RESOURCES_DIR/python-libpcap" ]; then
        log "Installing local python-libpcap..."
        cd "$RESOURCES_DIR/python-libpcap"
        pip install .
        cd "$RESOURCES_DIR"
    fi
    
    deactivate
    log "Virtual environment setup complete"
fi

# Generate config if it doesn't exist
if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    log "Creating configuration file..."
    
    # Generate unique database name
    TODAY=$(date +%Y%m%d)
    RAND_PART=$(cat /dev/urandom | tr -dc 'a-z' | head -c 47)
    DB_NAME="${TODAY}_${RAND_PART}"
    
    # Create config from example
    sed "s/database = /database = $DB_NAME/" "$CONFIG_DIR/config.ini.example" > "$CONFIG_DIR/config.ini"
    
    log "Configuration created with database: $DB_NAME"
fi

# Check BPF permissions
if ! check_bpf_permissions; then
    log "WARNING: BPF permissions may not be properly configured"
fi

# Set environment variables
export PYTHONPATH="$RESOURCES_DIR/bin"
export LIGHTSCOPE_CONFIG="$CONFIG_DIR/config.ini"

# Run LightScope
log "Starting LightScope runner..."
source "$VENV_PATH/bin/activate"
exec python3 "$RESOURCES_DIR/bin/lightscope-runner.py"
EOF

# Make the launcher executable
chmod +x "$APP_DIR/Contents/MacOS/lightscope-launcher"

# Create BPF permissions setup script
cat > "$APP_DIR/Contents/Resources/setup_bpf_permissions.sh" << 'EOF'
#!/bin/bash
# BPF Permissions Setup Script for LightScope
# This script sets up the necessary permissions for packet capture without root

set -e

echo "Setting up BPF permissions for LightScope..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (with sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# Create access_bpf group if it doesn't exist
if ! dscl . list /Groups | grep -q "^access_bpf$"; then
    echo "Creating access_bpf group..."
    dseditgroup -o create access_bpf
else
    echo "access_bpf group already exists"
fi

# Add current user to access_bpf group
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" != "root" ]; then
    echo "Adding user '$REAL_USER' to access_bpf group..."
    dseditgroup -o edit -a "$REAL_USER" access_bpf
else
    echo "Warning: Running as root, cannot determine original user"
fi

# Create launch daemon to set BPF permissions at boot
LAUNCH_DAEMON_PATH="/Library/LaunchDaemons/com.thelightscope.chmodbpf.plist"

cat > "$LAUNCH_DAEMON_PATH" << 'LAUNCHD_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.thelightscope.chmodbpf</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>chmod g+r /dev/bpf* || true</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
</dict>
</plist>
LAUNCHD_EOF

# Set proper permissions on launch daemon
chown root:wheel "$LAUNCH_DAEMON_PATH"
chmod 644 "$LAUNCH_DAEMON_PATH"

# Load the launch daemon
launchctl load "$LAUNCH_DAEMON_PATH"

# Set immediate permissions on existing BPF devices
echo "Setting immediate permissions on BPF devices..."
chgrp access_bpf /dev/bpf*
chmod g+r /dev/bpf*

echo "✅ BPF permissions setup complete!"
echo ""
echo "📋 What was done:"
echo "   - Created 'access_bpf' group"
echo "   - Added user '$REAL_USER' to access_bpf group"
echo "   - Created launch daemon to set BPF permissions at boot"
echo "   - Set immediate permissions on /dev/bpf* devices"
echo ""
echo "🔄 You may need to log out and log back in for group changes to take effect"
echo "🎉 LightScope should now be able to capture packets without root privileges"
EOF

# Make the BPF setup script executable
chmod +x "$APP_DIR/Contents/Resources/setup_bpf_permissions.sh"

# Create Launch Agent plist for user-level startup
LAUNCH_AGENT_DIR="$BUILD_DIR/LaunchAgents"
mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT_DIR/com.thelightscope.lightscope.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.thelightscope.lightscope</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/LightScope.app/Contents/MacOS/lightscope-launcher</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Applications/LightScope.app/Contents/Resources/logs/lightscope.log</string>
    <key>StandardErrorPath</key>
    <string>/Applications/LightScope.app/Contents/Resources/logs/lightscope-error.log</string>
    <key>WorkingDirectory</key>
    <string>/Applications/LightScope.app/Contents/Resources</string>
</dict>
</plist>
EOF

# Create installation script
cat > "$BUILD_DIR/install.sh" << 'EOF'
#!/bin/bash
set -e

echo "Installing LightScope for macOS..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please do not run this installer as root (sudo)"
    echo "   LightScope is designed to run as a regular user application"
    exit 1
fi

# Check for required dependencies
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    echo "   Please install Python 3.8 or later and try again"
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || [ "$PYTHON_MAJOR" -eq 3 -a "$PYTHON_MINOR" -lt 8 ]; then
    echo "❌ Python 3.8 or later is required (found $PYTHON_VERSION)"
    exit 1
fi

# Copy the application to /Applications
echo "📦 Installing LightScope.app to /Applications..."
if [ -d "/Applications/LightScope.app" ]; then
    echo "🔄 Removing existing installation..."
    rm -rf "/Applications/LightScope.app"
fi

cp -r "LightScope.app" "/Applications/"

# Check BPF permissions
echo "🔍 Checking BPF permissions for packet capture..."
BPF_ACCESSIBLE=false
for bpf_dev in /dev/bpf*; do
    if [ -e "$bpf_dev" ] && [ -r "$bpf_dev" ]; then
        BPF_ACCESSIBLE=true
        break
    fi
done

if [ "$BPF_ACCESSIBLE" = false ]; then
    echo "⚠️  BPF devices are not accessible for packet capture"
    echo "   This is normal on a fresh system. LightScope includes a setup script."
    echo ""
    echo "📋 To enable packet capture, run:"
    echo "   sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh"
    echo ""
    echo "💡 This is a one-time setup that:"
    echo "   - Creates an 'access_bpf' group"
    echo "   - Adds you to the group"
    echo "   - Sets up automatic BPF permissions at boot"
    echo "   - Does NOT require LightScope to run as root"
    echo ""
    read -p "Would you like to run the BPF setup now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh
    fi
else
    echo "✅ BPF permissions are already configured"
fi

# Install Launch Agent for user-level startup
echo "🚀 Setting up automatic startup..."
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"

# Stop existing service if running
launchctl unload "$LAUNCH_AGENTS_DIR/com.thelightscope.lightscope.plist" 2>/dev/null || true

# Install new Launch Agent
cp "LaunchAgents/com.thelightscope.lightscope.plist" "$LAUNCH_AGENTS_DIR/"

# Load the Launch Agent
launchctl load "$LAUNCH_AGENTS_DIR/com.thelightscope.lightscope.plist"

echo "✅ LightScope installed successfully!"
echo ""
echo "📍 Installed to: /Applications/LightScope.app"
echo "📊 Logs will be in: /Applications/LightScope.app/Contents/Resources/logs/"
echo "⚙️  Configuration: /Applications/LightScope.app/Contents/Resources/config/config.ini"
echo ""
echo "🎉 LightScope will start automatically and run in the background"
echo "   To stop: launchctl unload ~/Library/LaunchAgents/com.thelightscope.lightscope.plist"
echo "   To start: launchctl load ~/Library/LaunchAgents/com.thelightscope.lightscope.plist"
echo ""
echo "🔧 Network monitoring capabilities:"
echo "   - Monitors TCP traffic on all interfaces"
echo "   - Runs as regular user (not root)"
echo "   - Uses Berkeley Packet Filter (BPF) for packet capture"
EOF

# Create uninstall script
cat > "$BUILD_DIR/uninstall.sh" << 'EOF'
#!/bin/bash
set -e

echo "Uninstalling LightScope..."

# Stop the service
launchctl unload "$HOME/Library/LaunchAgents/com.thelightscope.lightscope.plist" 2>/dev/null || true

# Remove Launch Agent
rm -f "$HOME/Library/LaunchAgents/com.thelightscope.lightscope.plist"

# Remove application
rm -rf "/Applications/LightScope.app"

echo "✅ LightScope uninstalled successfully!"
echo ""
echo "📋 Note: BPF permissions setup (access_bpf group) was NOT removed"
echo "   This is intentional as it might be used by other applications"
echo "   If you want to remove BPF permissions:"
echo "   sudo launchctl unload /Library/LaunchDaemons/com.thelightscope.chmodbpf.plist"
echo "   sudo rm /Library/LaunchDaemons/com.thelightscope.chmodbpf.plist"
echo "   sudo dseditgroup -o delete access_bpf"
EOF

# Make scripts executable
chmod +x "$BUILD_DIR/install.sh"
chmod +x "$BUILD_DIR/uninstall.sh"

# Create README for the package
cat > "$BUILD_DIR/README.md" << EOF
# LightScope for macOS v$VERSION

## Installation

1. Run the installation script:
   \`\`\`
   ./install.sh
   \`\`\`

2. When prompted, allow the BPF permissions setup for packet capture

3. LightScope will start automatically and run in the background

## Network Monitoring

LightScope monitors network traffic using the Berkeley Packet Filter (BPF). This requires special permissions but does NOT require running as root.

### First-time Setup

The installer will offer to run the BPF permissions setup script:
\`\`\`
sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh
\`\`\`

This one-time setup:
- Creates an 'access_bpf' group
- Adds you to the group
- Sets up automatic BPF permissions at boot
- Allows packet capture without root privileges

### Manual BPF Setup

If you skipped the setup during installation, you can run it later:
\`\`\`
sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh
\`\`\`

## Configuration

Edit the configuration file at:
\`/Applications/LightScope.app/Contents/Resources/config/config.ini\`

## Logs

View logs at:
\`/Applications/LightScope.app/Contents/Resources/logs/\`

## Management

- **Stop**: \`launchctl unload ~/Library/LaunchAgents/com.thelightscope.lightscope.plist\`
- **Start**: \`launchctl load ~/Library/LaunchAgents/com.thelightscope.lightscope.plist\`
- **Uninstall**: \`./uninstall.sh\`

## Requirements

- macOS 10.14 or later
- Python 3.8 or later
- Network access for monitoring
- BPF permissions for packet capture

## Features

- Runs as user application (no root required)
- Automatic startup at login
- Background operation
- Network packet monitoring
- Honeypot functionality
- Automatic updates

## Security

- Does not require root privileges to run
- Uses Berkeley Packet Filter (BPF) for safe packet capture
- Group-based permissions following macOS security best practices
- Same approach used by Wireshark and other professional tools

## Troubleshooting

If packet capture fails:
1. Check BPF permissions: \`ls -la /dev/bpf*\`
2. Verify group membership: \`groups\`
3. Re-run setup: \`sudo /Applications/LightScope.app/Contents/Resources/setup_bpf_permissions.sh\`
4. Log out and log back in for group changes to take effect
EOF

# Create a simple DMG or ZIP package
OUTPUT_FILE="LightScope-${VERSION}-macOS.zip"
echo "Creating package: $OUTPUT_FILE"

cd "$BUILD_DIR"
zip -r "../$OUTPUT_FILE" . -x "*.DS_Store"
cd "$SCRIPT_DIR"

echo "✅ macOS package built successfully: $OUTPUT_FILE"
echo ""
echo "📦 Package contents:"
echo "   - LightScope.app (application bundle)"
echo "   - install.sh (installation script)"
echo "   - uninstall.sh (uninstallation script)"
echo "   - README.md (documentation)"
echo "   - BPF permissions setup script"
echo ""
echo "🚀 To install:"
echo "   1. Extract the ZIP file"
echo "   2. Run ./install.sh"
echo "   3. Allow BPF permissions setup when prompted"
echo ""
echo "🔧 Network Monitoring:"
echo "   - Uses Berkeley Packet Filter (BPF) for packet capture"
echo "   - Requires one-time permissions setup (included)"
echo "   - Runs as regular user (not root)"
echo "   - Same approach as Wireshark and other professional tools" 