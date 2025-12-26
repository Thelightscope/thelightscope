#!/bin/bash
set -e

# Build script for LightScope Arch Linux package

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_BUILD_DIR="$SCRIPT_DIR/arch-build"
PACKAGE_NAME="lightscope"

# Get version from lightscope_core.py
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from lightscope_core.py"
    exit 1
fi

echo "Building LightScope v$VERSION Arch Linux package..."

# Clean previous builds
rm -f "$ARCH_BUILD_DIR"/*.pkg.tar.*
rm -f "$ARCH_BUILD_DIR"/lightscope_core.py
rm -f "$ARCH_BUILD_DIR"/lightscope_runner.py
rm -f "$ARCH_BUILD_DIR"/lightscope-public.pem
rm -f "$ARCH_BUILD_DIR"/lightscope.service
rm -f "$ARCH_BUILD_DIR"/config.ini.example

# Copy source files to arch-build directory
echo "Copying source files to arch-build directory..."
cp lightscope/lightscope_core.py "$ARCH_BUILD_DIR/"
cp lightscope/lightscope-runner.py "$ARCH_BUILD_DIR/lightscope_runner.py"

# Copy public key (try both naming conventions)
if [ -f "lightscope-public.pem" ]; then
    cp lightscope-public.pem "$ARCH_BUILD_DIR/"
    echo "Copied lightscope-public.pem"
elif [ -f "lightscope_public.pem" ]; then
    cp lightscope_public.pem "$ARCH_BUILD_DIR/lightscope-public.pem"
    echo "Copied lightscope_public.pem as lightscope-public.pem"
else
    echo "Warning: Public key not found, creating placeholder"
    touch "$ARCH_BUILD_DIR/lightscope-public.pem"
fi

# Create systemd service file
cat > "$ARCH_BUILD_DIR/lightscope.service" << 'SERVICE_EOF'
[Unit]
Description=LightScope Network Security Monitor
Documentation=https://thelightscope.com/docs
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=notify
User=lightscope
Group=lightscope
ExecStart=/opt/lightscope/venv/bin/python /opt/lightscope/bin/lightscope-runner.py
ExecReload=/bin/kill -HUP $MAINPID
WorkingDirectory=/opt/lightscope
Environment=PYTHONPATH=/opt/lightscope

# Network capabilities for packet capture and port binding
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

# Restart configuration
Restart=always
RestartSec=10
StartLimitInterval=300
StartLimitBurst=5

# Watchdog configuration
WatchdogSec=30
NotifyAccess=all

# Security settings
NoNewPrivileges=false
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/lightscope
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lightscope

# Process limits
LimitNOFILE=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Create config example
cat > "$ARCH_BUILD_DIR/config.ini.example" << 'CONFIG_EOF'
[Settings]
# Database name for storing LightScope data (auto-generated during installation)
database =

# Randomization key for IP address anonymization (auto-generated if empty)
randomization_key =

# Enable automatic SSH/Telnet honeypot port forwarding (yes/no)
self_telnet_and_ssh_honeypot_ports_to_forward = no

# Enable automatic updates (yes/no)
autoupdate = yes

# Update check interval in hours (minimum 1 hour)
update_check_interval = 24

# Enable debug logging (yes/no)
debug_logging = no

# Custom interface to monitor (leave empty for auto-detection)
interface =

# Maximum number of concurrent honeypot ports
max_honeypot_ports = 10

# Honeypot rotation interval in hours
honeypot_rotation_interval = 4
CONFIG_EOF

# Update version in PKGBUILD
echo "Updating version in PKGBUILD to $VERSION..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^pkgver=.*/pkgver=$VERSION/" "$ARCH_BUILD_DIR/PKGBUILD"
else
    sed -i "s/^pkgver=.*/pkgver=$VERSION/" "$ARCH_BUILD_DIR/PKGBUILD"
fi

# Verify version was updated
BUILT_VERSION=$(grep -o 'ls_version = "[^"]*"' "$ARCH_BUILD_DIR/lightscope_core.py" | sed 's/ls_version = "\(.*\)"/\1/')
echo "Verified source version: $BUILT_VERSION"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "ERROR: Version mismatch! Expected $VERSION, got $BUILT_VERSION"
    exit 1
fi

# Build the package
echo "Building Arch Linux package..."
cd "$ARCH_BUILD_DIR"

# Check if makepkg is available (we're on Arch)
if command -v makepkg &> /dev/null; then
    # Build package (--nodeps because we may not have all deps on build system)
    makepkg -f --nodeps

    # Find the built package
    PKG_FILE=$(ls -t ${PACKAGE_NAME}-${VERSION}-*.pkg.tar.* 2>/dev/null | head -1)
    if [ -z "$PKG_FILE" ]; then
        echo "Error: Could not find built package"
        exit 1
    fi

    # Move to project root
    mv "$PKG_FILE" "$SCRIPT_DIR/"
    echo "Package built successfully: $PKG_FILE"
else
    echo "Note: makepkg not available (not on Arch Linux)"
    echo "Creating source tarball instead for later building on Arch..."

    # Create a source tarball that can be built on Arch
    cd "$SCRIPT_DIR"
    TARBALL="${PACKAGE_NAME}-${VERSION}-arch-src.tar.gz"
    tar -czf "$TARBALL" -C "$ARCH_BUILD_DIR" \
        PKGBUILD \
        lightscope.install \
        lightscope_core.py \
        lightscope_runner.py \
        lightscope-public.pem \
        lightscope.service \
        config.ini.example

    echo "Source tarball created: $TARBALL"
    echo ""
    echo "To build on Arch Linux:"
    echo "  1. Copy $TARBALL to an Arch system"
    echo "  2. Extract: tar -xzf $TARBALL"
    echo "  3. Build: makepkg -si"
fi

cd "$SCRIPT_DIR"

echo ""
echo "Build complete!"
echo "To install on Arch Linux: sudo pacman -U ${PACKAGE_NAME}-${VERSION}-*.pkg.tar.*"
echo "To remove: sudo pacman -R $PACKAGE_NAME"
