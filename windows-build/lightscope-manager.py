#!/usr/bin/env python3
"""
LightScope Manager Script for Windows
This script provides a user-friendly interface to start, stop, and manage LightScope
without requiring administrator privileges.
"""

import os
import sys
import time
import subprocess
from pathlib import Path
import logging

# Check if we're running in the virtual environment
SCRIPT_DIR = Path(__file__).parent.absolute()
VENV_PYTHON = SCRIPT_DIR / "venv" / "Scripts" / "python.exe"

# If we're not in the virtual environment and it exists, re-run with venv Python
if VENV_PYTHON.exists() and sys.executable != str(VENV_PYTHON):
    print("Switching to virtual environment Python...")
    # Re-run this script with the virtual environment Python
    subprocess.run([str(VENV_PYTHON), __file__] + sys.argv[1:])
    sys.exit(0)

# Now we can safely import psutil (it should be available in the venv)
try:
    import psutil
except ImportError:
    print("ERROR: psutil is not installed.")
    print("This usually means the virtual environment wasn't set up correctly.")
    print("Please run the installer again or install psutil manually:")
    print("  pip install psutil")
    sys.exit(1)

# Configuration
LIGHTSCOPE_HOME = SCRIPT_DIR
LOGS_DIR = LIGHTSCOPE_HOME / "logs"
CONFIG_DIR = LIGHTSCOPE_HOME / "config"

# Setup logging
LOGS_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOGS_DIR / "lightscope-manager.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("lightscope-manager")

def find_lightscope_processes():
    """Find all LightScope-related processes"""
    processes = []
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['cmdline']:
                cmdline = ' '.join(proc.info['cmdline'])
                if 'lightscope' in cmdline.lower():
                    processes.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return processes

def is_lightscope_running():
    """Check if LightScope is currently running"""
    return len(find_lightscope_processes()) > 0

def start_lightscope():
    """Start LightScope"""
    if is_lightscope_running():
        print("LightScope is already running")
        return True
    
    try:
        # Try to find the runner script
        runner_script = LIGHTSCOPE_HOME / "lightscope-runner-windows.py"
        if not runner_script.exists():
            print(f"ERROR: Runner script not found at {runner_script}")
            return False
        
        # Check for virtual environment
        venv_python = LIGHTSCOPE_HOME / "venv" / "Scripts" / "python.exe"
        if venv_python.exists():
            python_exe = str(venv_python)
            print("Using virtual environment Python")
        else:
            python_exe = "python"
            print("Using system Python")
        
        print("Starting LightScope...")
        
        # Start LightScope in the background
        process = subprocess.Popen(
            [python_exe, str(runner_script)],
            cwd=str(LIGHTSCOPE_HOME),
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP
        )
        
        # Wait a moment to see if it starts successfully
        time.sleep(2)
        
        if process.poll() is None:
            print("✓ LightScope started successfully")
            print(f"  Process ID: {process.pid}")
            return True
        else:
            print("✗ LightScope failed to start")
            return False
            
    except Exception as e:
        print(f"Error starting LightScope: {e}")
        return False

def stop_lightscope():
    """Stop LightScope"""
    processes = find_lightscope_processes()
    
    if not processes:
        print("LightScope is not running")
        return True
    
    print(f"Found {len(processes)} LightScope process(es)")
    
    # First, try to terminate gracefully
    for proc in processes:
        try:
            print(f"Stopping process {proc.pid}...")
            proc.terminate()
        except psutil.NoSuchProcess:
            pass
    
    # Wait for processes to terminate
    time.sleep(3)
    
    # Check if any processes are still running
    remaining_processes = find_lightscope_processes()
    
    if remaining_processes:
        print(f"Force killing {len(remaining_processes)} remaining process(es)...")
        for proc in remaining_processes:
            try:
                proc.kill()
            except psutil.NoSuchProcess:
                pass
    
    # Final check
    time.sleep(1)
    if not is_lightscope_running():
        print("✓ LightScope stopped successfully")
        return True
    else:
        print("✗ Some LightScope processes may still be running")
        return False

def restart_lightscope():
    """Restart LightScope"""
    print("Restarting LightScope...")
    stop_lightscope()
    time.sleep(2)
    return start_lightscope()

def status_lightscope():
    """Show LightScope status"""
    processes = find_lightscope_processes()
    
    if not processes:
        print("LightScope Status: NOT RUNNING")
        return
    
    print(f"LightScope Status: RUNNING ({len(processes)} process(es))")
    for proc in processes:
        try:
            print(f"  PID: {proc.pid}, Name: {proc.info['name']}")
        except psutil.NoSuchProcess:
            pass

def enable_startup():
    """Enable LightScope to start automatically at login"""
    try:
        import winreg
        
        # Create startup batch file
        startup_batch = LIGHTSCOPE_HOME / "start-lightscope.bat"
        
        # Check for virtual environment
        venv_python = LIGHTSCOPE_HOME / "venv" / "Scripts" / "python.exe"
        if venv_python.exists():
            python_cmd = f'"{venv_python}" "{LIGHTSCOPE_HOME / "lightscope-runner-windows.py"}"'
        else:
            python_cmd = f'python "{LIGHTSCOPE_HOME / "lightscope-runner-windows.py"}"'
        
        with open(startup_batch, 'w') as f:
            f.write("@echo off\n")
            f.write(f'cd /d "{LIGHTSCOPE_HOME}"\n')
            f.write(f'{python_cmd}\n')
        
        # Add to Windows startup registry
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, 
                           r"Software\Microsoft\Windows\CurrentVersion\Run", 
                           0, winreg.KEY_WRITE)
        winreg.SetValueEx(key, "LightScope", 0, winreg.REG_SZ, str(startup_batch))
        winreg.CloseKey(key)
        
        print("✓ LightScope startup enabled")
        print("  LightScope will start automatically when you log in")
        return True
        
    except Exception as e:
        print(f"Error enabling startup: {e}")
        return False

def disable_startup():
    """Disable LightScope automatic startup"""
    try:
        import winreg
        
        # Remove from Windows startup registry
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, 
                           r"Software\Microsoft\Windows\CurrentVersion\Run", 
                           0, winreg.KEY_WRITE)
        try:
            winreg.DeleteValue(key, "LightScope")
            print("✓ LightScope startup disabled")
        except FileNotFoundError:
            print("LightScope startup was not enabled")
        
        winreg.CloseKey(key)
        return True
        
    except Exception as e:
        print(f"Error disabling startup: {e}")
        return False

def show_logs():
    """Show recent log entries"""
    log_file = LOGS_DIR / "lightscope-runner.log"
    if not log_file.exists():
        print("No log file found")
        return
    
    print("Recent log entries:")
    print("-" * 50)
    
    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()
            # Show last 20 lines
            for line in lines[-20:]:
                print(line.strip())
    except Exception as e:
        print(f"Error reading log file: {e}")

def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("LightScope Manager")
        print("Usage:")
        print("  python lightscope-manager.py start      - Start LightScope")
        print("  python lightscope-manager.py stop       - Stop LightScope")
        print("  python lightscope-manager.py restart    - Restart LightScope")
        print("  python lightscope-manager.py status     - Show status")
        print("  python lightscope-manager.py enable     - Enable startup")
        print("  python lightscope-manager.py disable    - Disable startup")
        print("  python lightscope-manager.py logs       - Show recent logs")
        return
    
    command = sys.argv[1].lower()
    
    if command == "start":
        start_lightscope()
    elif command == "stop":
        stop_lightscope()
    elif command == "restart":
        restart_lightscope()
    elif command == "status":
        status_lightscope()
    elif command == "enable":
        enable_startup()
    elif command == "disable":
        disable_startup()
    elif command == "logs":
        show_logs()
    else:
        print(f"Unknown command: {command}")
        print("Use 'python lightscope-manager.py' for help")

if __name__ == "__main__":
    main() 