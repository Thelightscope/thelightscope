#!/bin/sh
#
# Reconfigure LightScope - regenerate config and restart service
#
# Copyright (c) 2025 Eric Kapitanski <e@alumni.usc.edu>
# University of Southern California Information Sciences Institute
#

CONFIG_FILE="/usr/local/etc/lightscope.conf"

# Update honeypot_ports from OPNsense model (preserves database ID)
HONEYPOT_PORTS=$(/usr/local/sbin/pluginctl -g OPNsense.Lightscope.general.honeypot_ports 2>/dev/null)
if [ -n "$HONEYPOT_PORTS" ] && [ -f "$CONFIG_FILE" ]; then
    sed -i '' "s/^honeypot_ports.*/honeypot_ports = $HONEYPOT_PORTS/" "$CONFIG_FILE"
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
