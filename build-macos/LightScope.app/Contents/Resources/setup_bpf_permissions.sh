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
