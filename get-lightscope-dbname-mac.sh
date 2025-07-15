#!/bin/bash

# LightScope Database Name Finder - macOS Version
# Simple script to extract database name from LightScope config

set -euo pipefail

echo "🔍 LightScope Database Name Finder (macOS)"
echo "========================================="
echo

# Check if LightScope is installed
if [ ! -d "/Applications/LightScope.app" ]; then
    echo "❌ ERROR: LightScope.app not found in /Applications/"
    echo "   Please install LightScope first from: https://thelightscope.com/installation.html"
    exit 1
fi

# Check if config file exists
CONFIG_FILE="/Applications/LightScope.app/Contents/Resources/config.ini"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: Config file not found at $CONFIG_FILE"
    echo "   Please run LightScope at least once to generate the config file."
    exit 1
fi

# Extract database name from config file
DB_NAME=$(grep '^database = ' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")

if [ -n "$DB_NAME" ]; then
    echo "✅ Found your LightScope database name!"
    echo
    echo "🏷️  Database Name: $DB_NAME"
    echo "🌐 Dashboard URL: https://thelightscope.com/tables/$DB_NAME"
    echo "📋 Web Interface: https://thelightscope.com/tables"
    echo
    echo "🔄 Service Status:"
    if pgrep -f "lightscope-runner" >/dev/null 2>&1; then
        echo "   ✅ LightScope is running"
    else
        echo "   ⚠️  LightScope is not running"
        echo "   💡 Start it from Applications or run: launchctl load ~/Library/LaunchAgents/com.thelightscope.lightscope.plist"
    fi
    echo
    echo "💡 Tip: Bookmark your dashboard URL for easy access!"
    echo "📱 You can also access your dashboard from LightScope notifications"
    echo
else
    echo "⚠️  Database name not found in config file."
    echo "   This might mean:"
    echo "   • LightScope hasn't been run yet"
    echo "   • The config file is corrupted"
    echo
    echo "🔧 Try running LightScope first, then run this script again"
    echo "   You can start LightScope from Applications or Terminal:"
    echo "   launchctl load ~/Library/LaunchAgents/com.thelightscope.lightscope.plist"
    
    exit 1
fi 