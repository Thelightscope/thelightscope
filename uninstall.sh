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
