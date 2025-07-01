#!/bin/bash

# LightScope Database Name Finder
# Simple script to extract database name from systemctl status

set -euo pipefail

echo "🔍 LightScope Database Name Finder"
echo "=================================="
echo

# Check if lightscope service exists
if ! systemctl list-unit-files | grep -q "lightscope.service"; then
    echo "❌ ERROR: LightScope service not found!"
    echo "   Please install LightScope first."
    exit 1
fi

# Get database name from systemctl environment
echo "📋 Checking systemctl status..."
DB_NAME=$(systemctl show lightscope --property=Environment | grep -o 'LIGHTSCOPE_DB_NAME=[^[:space:]]*' | cut -d'=' -f2 2>/dev/null || echo "")

if [ -n "$DB_NAME" ]; then
    echo "✅ Found database name in systemd environment!"
    echo
    echo "🏷️  Database Name: $DB_NAME"
    echo "🌐 Dashboard URL: https://lightscope.isi.edu/tables/$DB_NAME"
    echo "📋 Web Interface: https://lightscope.isi.edu/tables"
    echo
    echo "🔄 Service Status:"
    systemctl is-active lightscope >/dev/null 2>&1 && echo "   ✅ Running" || echo "   ⚠️  Not running"
    echo
    echo "💡 Tip: Bookmark your dashboard URL for easy access!"
else
    echo "⚠️  Database name not found in systemd environment."
    echo "   This might mean:"
    echo "   • LightScope was installed with an older version"
    echo "   • The service hasn't been restarted since upgrade"
    echo
    echo "🔧 Try restarting the service:"
    echo "   sudo systemctl restart lightscope"
    echo "   Then run this script again"
    echo
    echo "📖 Alternative: Check the config file directly:"
    echo "   sudo grep '^database' /opt/lightscope/config/config.ini"
    
    # Try to read from config file as fallback
    if [ -f "/opt/lightscope/config/config.ini" ]; then
        CONFIG_DB_NAME=$(sudo grep '^database' /opt/lightscope/config/config.ini 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        if [ -n "$CONFIG_DB_NAME" ]; then
            echo
            echo "📁 Found database name in config file:"
            echo "🏷️  Database Name: $CONFIG_DB_NAME"
            echo "🌐 Dashboard URL: https://lightscope.isi.edu/tables/$CONFIG_DB_NAME"
        fi
    fi
    
    exit 1
fi 