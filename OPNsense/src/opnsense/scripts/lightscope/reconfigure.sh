#!/bin/sh
#
# Reconfigure LightScope - regenerate config and restart service
#
# Copyright (c) 2025 Eric Kapitanski <e@alumni.usc.edu>
# University of Southern California Information Sciences Institute
#

# Generate config from OPNsense template system
/usr/local/opnsense/service/configd_ctl.py template reload OPNsense/Lightscope

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
