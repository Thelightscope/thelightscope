#!/usr/local/bin/python3
"""
status.py - Returns LightScope status as JSON for API/widget
"""

import json
import os
import configparser
import subprocess

CONFIG_FILE = "/usr/local/etc/lightscope.conf"
DASHBOARD_URL = "https://thelightscope.com/light_table"

def get_status():
    """Get LightScope status information."""
    result = {
        "status": "stopped",
        "database": "",
        "dashboard_url": "",
        "honeypot_ports": "",
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

    # Check if service is running
    try:
        proc = subprocess.run(
            ["/usr/local/etc/rc.d/os-lightscope", "status"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if proc.returncode == 0 and "running" in proc.stdout.lower():
            result["status"] = "running"
        else:
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

    return result

if __name__ == "__main__":
    print(json.dumps(get_status()))
