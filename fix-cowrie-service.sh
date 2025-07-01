#!/bin/bash

# Fix the cowrie service configuration

set -e

echo "Stopping cowrie service..."
sudo systemctl stop cowrie

echo "Updating cowrie service file..."
sudo cp cowrie.service /etc/systemd/system/

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Ensuring proper ownership of cowrie directory..."
sudo chown -R ekapitanski:nsnam /mnt/raid/ekapitanski/cowrie

echo "Starting cowrie service..."
sudo systemctl start cowrie

echo "Checking cowrie service status..."
sudo systemctl status cowrie 