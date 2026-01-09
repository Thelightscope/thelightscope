#!/bin/sh
#
# Reconfigure LightScope - regenerate config and restart service
#
# Copyright (c) 2025 Eric Kapitanski <e@alumni.usc.edu>
# University of Southern California Information Sciences Institute
#

CONFIG_FILE="/usr/local/etc/lightscope.conf"

# Update honeypot_ports from OPNsense model (preserves database ID)
# Note: pluginctl returns empty string if not set, which is valid (no honeypot ports)
HONEYPOT_PORTS=$(/usr/local/sbin/pluginctl -g OPNsense.Lightscope.general.honeypot_ports 2>/dev/null)
if [ -f "$CONFIG_FILE" ]; then
    # Check if line exists
    if grep -q "^honeypot_ports" "$CONFIG_FILE"; then
        sed -i '' "s/^honeypot_ports.*/honeypot_ports = $HONEYPOT_PORTS/" "$CONFIG_FILE"
    else
        # Add the line if it doesn't exist
        echo "honeypot_ports = $HONEYPOT_PORTS" >> "$CONFIG_FILE"
    fi
    echo "Updated honeypot_ports to: $HONEYPOT_PORTS"
fi

# Update auto_update_enabled from OPNsense model
AUTO_UPDATE=$(/usr/local/sbin/pluginctl -g OPNsense.Lightscope.general.auto_update_enabled 2>/dev/null)
# Convert 1/0 to true/false for config file
if [ "$AUTO_UPDATE" = "1" ]; then
    AUTO_UPDATE_VAL="true"
else
    AUTO_UPDATE_VAL="false"
fi
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "^auto_update_enabled" "$CONFIG_FILE"; then
        sed -i '' "s/^auto_update_enabled.*/auto_update_enabled = $AUTO_UPDATE_VAL/" "$CONFIG_FILE"
    else
        echo "auto_update_enabled = $AUTO_UPDATE_VAL" >> "$CONFIG_FILE"
    fi
    echo "Updated auto_update_enabled to: $AUTO_UPDATE_VAL"
fi

# Reload firewall rules (for honeypot ports)
/usr/local/etc/rc.filter_configure

# Check if service should be enabled
ENABLED=$(/usr/local/sbin/pluginctl -g OPNsense.Lightscope.general.enabled 2>/dev/null)

if [ "$ENABLED" = "1" ]; then
    # Restart service if enabled
    /usr/local/etc/rc.d/os-lightscope onerestart
else
    # Stop service if disabled
    /usr/local/etc/rc.d/os-lightscope onestop 2>/dev/null
fi

exit 0
