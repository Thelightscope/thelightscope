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
echo ""
echo "    Please wait about 10 secods for initial loading..."
echo ""
