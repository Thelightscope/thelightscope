#!/bin/bash

# Install and enable systemd services for proxy-shim and cowrie

set -e

echo "Installing systemd services..."

# Copy service files to systemd directory
sudo cp proxy-shim.service /etc/systemd/system/
sudo cp cowrie.service /etc/systemd/system/

# Set proper permissions
sudo chmod 644 /etc/systemd/system/proxy-shim.service
sudo chmod 644 /etc/systemd/system/cowrie.service

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable proxy-shim.service
sudo systemctl enable cowrie.service

echo "Services installed and enabled!"
echo ""
echo "To start the services now:"
echo "  sudo systemctl start proxy-shim"
echo "  sudo systemctl start cowrie"
echo ""
echo "To check service status:"
echo "  sudo systemctl status proxy-shim"
echo "  sudo systemctl status cowrie"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u proxy-shim -f"
echo "  sudo journalctl -u cowrie -f" 