#!/bin/sh
#
# Reconfigure LightScope - regenerate config and restart service
#

# Generate config from template
/usr/local/opnsense/scripts/OPNsense/Lightscope/generate.py

# Reload firewall rules (for honeypot ports)
/usr/local/etc/rc.filter_configure

# Restart service if running
if /usr/local/etc/rc.d/os-lightscope status > /dev/null 2>&1; then
    /usr/local/etc/rc.d/os-lightscope restart
fi

exit 0
