#!/usr/local/bin/python3
"""
status.py - Returns LightScope status as JSON for API/widget
"""

import json
import os
import re
import configparser
import subprocess

CONFIG_FILE = "/usr/local/etc/lightscope.conf"
DASHBOARD_URL = "https://thelightscope.com/light_table"


def get_firewall_allowed_ports():
    """
    Get list of ports that have PASS/ALLOW rules in the firewall.
    These are ports where legitimate services may be running.
    """
    allowed_ports = set()

    try:
        # Get active pf rules
        result = subprocess.run(
            ["pfctl", "-sr"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                # Look for pass rules with port specifications
                # Example: pass in on em0 proto tcp from any to any port = 22
                if line.startswith('pass') and 'proto tcp' in line:
                    # Extract port number(s)
                    # Match patterns like "port = 22" or "port 22" or "port { 22 80 443 }"
                    port_match = re.search(r'port\s*[=]?\s*(\d+)', line)
                    if port_match:
                        allowed_ports.add(int(port_match.group(1)))

                    # Match port ranges or lists in braces
                    brace_match = re.search(r'port\s*[=]?\s*\{([^}]+)\}', line)
                    if brace_match:
                        ports_str = brace_match.group(1)
                        for p in re.findall(r'\d+', ports_str):
                            allowed_ports.add(int(p))
    except Exception as e:
        pass

    return allowed_ports


def get_port_status(ports_string):
    """
    Check status of honeypot ports against firewall rules.
    Returns dict with port status info.
    """
    port_status = {}

    if not ports_string:
        return port_status

    allowed_ports = get_firewall_allowed_ports()

    for p in ports_string.split(','):
        p = p.strip()
        if p.isdigit():
            port = int(p)
            if 1 <= port <= 65535:
                if port in allowed_ports:
                    # Port has a firewall ALLOW rule - potential conflict
                    port_status[port] = "firewall_conflict"
                else:
                    # Port is safe for honeypot
                    port_status[port] = "ok"

    return port_status


def get_status():
    """Get LightScope status information."""
    result = {
        "status": "stopped",
        "database": "",
        "dashboard_url": "",
        "honeypot_ports": "",
        "port_status": {},
        "config_exists": False
    }

    # Check if config exists
    if os.path.exists(CONFIG_FILE):
        result["config_exists"] = True
        try:
            config = configparser.ConfigParser()
            config.read(CONFIG_FILE)

            database = config.get('Settings', 'database', fallback='').strip()
            if database:
                result["database"] = database
                result["dashboard_url"] = f"{DASHBOARD_URL}/{database}"

            result["honeypot_ports"] = config.get('Settings', 'honeypot_ports', fallback='')
        except Exception as e:
            result["config_error"] = str(e)

    # Check if service is running via pid file
    pidfile = "/var/run/lightscope.pid"
    try:
        if os.path.exists(pidfile):
            with open(pidfile, 'r') as f:
                pid = int(f.read().strip())
            # Check if process is actually running
            os.kill(pid, 0)  # Signal 0 just checks if process exists
            result["status"] = "running"
        else:
            result["status"] = "stopped"
    except (ProcessLookupError, ValueError, PermissionError):
        result["status"] = "stopped"
    except Exception:
        result["status"] = "unknown"

    # Check process count
    try:
        proc = subprocess.run(
            ["pgrep", "-f", "lightscope_daemon"],
            capture_output=True,
            text=True,
            timeout=5
        )
        pids = proc.stdout.strip().split('\n')
        result["process_count"] = len([p for p in pids if p])
    except Exception:
        result["process_count"] = 0

    # Check port status against firewall rules
    result["port_status"] = get_port_status(result["honeypot_ports"])

    return result

if __name__ == "__main__":
    print(json.dumps(get_status()))
