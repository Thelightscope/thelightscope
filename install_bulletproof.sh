#!/bin/bash

# LightScope Bulletproof Installation Script
# This script sets up LightScope with automatic crash recovery and updates

set -euo pipefail

echo "=========================================="
echo "LightScope Bulletproof Installation"
echo "=========================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

# Get the real user (in case of sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

echo "Installing for user: $REAL_USER"
echo "Home directory: $REAL_HOME"

# Update system packages
echo "Updating system packages..."
apt-get update -qq

# Install required system packages
echo "Installing system dependencies..."
apt-get install -y python3 python3-pip python3-venv libpcap-dev

# Install/upgrade LightScope
echo "Installing/upgrading LightScope..."
python3 -m pip install --upgrade lightscope

# Copy systemd service file
echo "Installing systemd service..."
cp lightscope-monitor.service /etc/systemd/system/
systemctl daemon-reload

# Create log directory
mkdir -p /var/log/lightscope
chown $REAL_USER:$REAL_USER /var/log/lightscope

# Enable and start service
echo "Enabling LightScope service..."
systemctl enable lightscope-monitor.service

# Check if service is already running and stop it
if systemctl is-active --quiet lightscope-monitor.service; then
    echo "Stopping existing service..."
    systemctl stop lightscope-monitor.service
    sleep 2
fi

# Start the service
echo "Starting LightScope service..."
systemctl start lightscope-monitor.service

# Wait a moment and check status
sleep 3
if systemctl is-active --quiet lightscope-monitor.service; then
    echo "✓ LightScope service started successfully"
    
    echo ""
    echo "Service Status:"
    systemctl status lightscope-monitor.service --no-pager -l
    
    echo ""
    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    echo ""
    echo "The LightScope monitor is now running with:"
    echo "• Automatic crash recovery"
    echo "• Automatic updates from PyPI"
    echo "• Comprehensive logging"
    echo "• Systemd integration"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status lightscope-monitor   # Check status"
    echo "  systemctl restart lightscope-monitor  # Restart service"
    echo "  systemctl stop lightscope-monitor     # Stop service"
    echo "  journalctl -u lightscope-monitor -f   # View live logs"
    echo "  tail -f $REAL_HOME/lightscope_monitor.log # View monitor logs"
    echo ""
    echo "The service will automatically:"
    echo "• Start on system boot"
    echo "• Restart if LightScope crashes"
    echo "• Update to new versions hourly"
    echo "• Log all activity to systemd journal and file"
    
else
    echo "✗ ERROR: Service failed to start"
    echo "Check logs with: journalctl -u lightscope-monitor -n 20"
    exit 1
fi 