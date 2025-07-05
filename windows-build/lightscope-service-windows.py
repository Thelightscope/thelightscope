#!/usr/bin/env python3
"""
LightScope Windows Service
This script creates a Windows service that runs LightScope with automatic restart and update capabilities.
"""

import os
import sys
import time
import json
import logging
import tempfile
import subprocess
import urllib.request
import urllib.error
from pathlib import Path
import servicemanager
import win32event
import win32service
import win32serviceutil

# Add the current directory to Python path for imports
current_dir = Path(__file__).parent
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))

# Configuration
# Dynamically determine installation directory based on script location
SCRIPT_DIR = Path(__file__).parent.absolute()
# If running from bin subdirectory, parent is LIGHTSCOPE_HOME
if SCRIPT_DIR.name == "bin":
    LIGHTSCOPE_HOME = SCRIPT_DIR.parent
else:
    # If running from root directory, use current directory
    LIGHTSCOPE_HOME = SCRIPT_DIR

# Check for virtual environment and use it if available
VENV_DIR = LIGHTSCOPE_HOME / "venv"
if VENV_DIR.exists():
    VENV_PYTHON = VENV_DIR / "Scripts" / "python.exe"
    if VENV_PYTHON.exists():
        # Update sys.path to use virtual environment
        venv_site_packages = VENV_DIR / "Lib" / "site-packages"
        if str(venv_site_packages) not in sys.path:
            sys.path.insert(0, str(venv_site_packages))
        logger.info(f"Using virtual environment: {VENV_DIR}")
    else:
        VENV_PYTHON = None
        logger.warning("Virtual environment directory found but python.exe missing")
else:
    VENV_PYTHON = None
    logger.info("No virtual environment found, using system Python")

CONFIG_DIR = LIGHTSCOPE_HOME / "config"
UPDATES_DIR = LIGHTSCOPE_HOME / "updates"
LOGS_DIR = LIGHTSCOPE_HOME / "logs"
BIN_DIR = LIGHTSCOPE_HOME / "bin"

# If BIN_DIR doesn't exist, we're probably running from the root directory
if not BIN_DIR.exists():
    BIN_DIR = LIGHTSCOPE_HOME

# Setup logging
LOGS_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOGS_DIR / "lightscope-service.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("lightscope-service")


class LightScopeService(win32serviceutil.ServiceFramework):
    """Windows Service for LightScope"""
    
    _svc_name_ = "LightScope"
    _svc_display_name_ = "LightScope Network Security Monitor"
    _svc_description_ = "LightScope monitors network traffic for security threats and provides real-time threat intelligence."
    
    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.hWaitStop = win32event.CreateEvent(None, 0, 0, None)
        self.is_alive = True
        self.runner_process = None
        
    def SvcStop(self):
        """Stop the service"""
        logger.info("LightScope Service stopping...")
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        self.is_alive = False
        
        # Stop the runner process
        if self.runner_process and self.runner_process.poll() is None:
            try:
                self.runner_process.terminate()
                self.runner_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.runner_process.kill()
            except Exception as e:
                logger.error(f"Error stopping runner process: {e}")
        
        win32event.SetEvent(self.hWaitStop)
        
    def SvcDoRun(self):
        """Main service execution"""
        logger.info("LightScope Service starting...")
        servicemanager.LogMsg(
            servicemanager.EVENTLOG_INFORMATION_TYPE,
            servicemanager.PYS_SERVICE_STARTED,
            (self._svc_name_, '')
        )
        
        # Ensure all directories exist
        self.ensure_directories()
        
        # Main service loop
        consecutive_failures = 0
        max_consecutive_failures = 3
        
        while self.is_alive:
            try:
                # Start the runner process - try multiple locations
                possible_runner_paths = [
                    BIN_DIR / "lightscope-runner-windows.py",
                    LIGHTSCOPE_HOME / "lightscope-runner-windows.py",
                    SCRIPT_DIR / "lightscope-runner-windows.py",
                ]
                
                runner_script = None
                for path in possible_runner_paths:
                    if path.exists():
                        runner_script = path
                        break
                
                if not runner_script:
                    logger.error(f"Runner script not found! Searched in:")
                    for path in possible_runner_paths:
                        logger.error(f"  - {path}")
                    time.sleep(30)
                    continue
                
                logger.info("Starting LightScope runner...")
                
                # Use virtual environment Python if available, otherwise use current Python
                python_executable = str(VENV_PYTHON) if VENV_PYTHON else sys.executable
                logger.info(f"Using Python executable: {python_executable}")
                
                self.runner_process = subprocess.Popen([
                    python_executable, str(runner_script)
                ], cwd=str(LIGHTSCOPE_HOME))
                
                # Wait for process to finish or service to stop
                while self.is_alive and self.runner_process.poll() is None:
                    # Check every 5 seconds
                    if win32event.WaitForSingleObject(self.hWaitStop, 5000) == win32event.WAIT_OBJECT_0:
                        break
                
                if not self.is_alive:
                    break
                
                # Process exited
                exit_code = self.runner_process.returncode
                if exit_code == 0:
                    logger.info("LightScope runner exited normally")
                    consecutive_failures = 0
                    break
                else:
                    consecutive_failures += 1
                    logger.error(f"LightScope runner failed with exit code {exit_code} (attempt {consecutive_failures}/{max_consecutive_failures})")
                    
                    if consecutive_failures >= max_consecutive_failures:
                        logger.error("Too many consecutive failures, stopping service")
                        break
                    
                    # Wait before retry with exponential backoff
                    sleep_time = min(10 * (2 ** (consecutive_failures - 1)), 60)
                    logger.info(f"Retrying in {sleep_time} seconds...")
                    
                    if win32event.WaitForSingleObject(self.hWaitStop, sleep_time * 1000) == win32event.WAIT_OBJECT_0:
                        break
                    
            except Exception as e:
                logger.error(f"Error in service main loop: {e}")
                consecutive_failures += 1
                
                if consecutive_failures >= max_consecutive_failures:
                    logger.error("Too many consecutive failures, stopping service")
                    break
                
                time.sleep(30)
        
        logger.info("LightScope Service stopped")
        servicemanager.LogMsg(
            servicemanager.EVENTLOG_INFORMATION_TYPE,
            servicemanager.PYS_SERVICE_STOPPED,
            (self._svc_name_, '')
        )
    
    def ensure_directories(self):
        """Ensure all required directories exist"""
        for directory in [CONFIG_DIR, UPDATES_DIR, LOGS_DIR, BIN_DIR]:
            directory.mkdir(parents=True, exist_ok=True)


def install_service():
    """Install the Windows service"""
    try:
        # Check if running as administrator
        import ctypes
        if not ctypes.windll.shell32.IsUserAnAdmin():
            print("Error: Administrator privileges required to install service")
            print("Please run this script as Administrator")
            return False
        
        # Use HandleCommandLine for proper service installation
        sys.argv = [sys.argv[0], '--startup', 'auto', 'install']
        win32serviceutil.HandleCommandLine(LightScopeService)
        print(f"Service '{LightScopeService._svc_display_name_}' installed successfully")
        print("The service is set to start automatically at boot")
        return True
    except Exception as e:
        print(f"Error installing service: {e}")
        return False


def uninstall_service():
    """Uninstall the Windows service"""
    try:
        # Check if running as administrator
        import ctypes
        if not ctypes.windll.shell32.IsUserAnAdmin():
            print("Error: Administrator privileges required to uninstall service")
            print("Please run this script as Administrator")
            return False
        
        # Use HandleCommandLine for proper service removal
        sys.argv = [sys.argv[0], 'remove']
        win32serviceutil.HandleCommandLine(LightScopeService)
        print(f"Service '{LightScopeService._svc_display_name_}' uninstalled successfully")
        return True
    except Exception as e:
        print(f"Error uninstalling service: {e}")
        return False


def start_service():
    """Start the service"""
    try:
        # Use HandleCommandLine for service start
        sys.argv = [sys.argv[0], 'start']
        win32serviceutil.HandleCommandLine(LightScopeService)
        print(f"Service '{LightScopeService._svc_display_name_}' started successfully")
        return True
    except Exception as e:
        print(f"Error starting service: {e}")
        return False


def stop_service():
    """Stop the service"""  
    try:
        # Use HandleCommandLine for service stop
        sys.argv = [sys.argv[0], 'stop']
        win32serviceutil.HandleCommandLine(LightScopeService)
        print(f"Service '{LightScopeService._svc_display_name_}' stopped successfully")
        return True
    except Exception as e:
        print(f"Error stopping service: {e}")
        return False


def main():
    if len(sys.argv) == 1:
        # No arguments - run as service
        servicemanager.Initialize()
        servicemanager.PrepareToHostSingle(LightScopeService)
        servicemanager.StartServiceCtrlDispatcher()
    else:
        # Handle command line arguments
        if sys.argv[1].lower() == 'install':
            install_service()
        elif sys.argv[1].lower() == 'uninstall' or sys.argv[1].lower() == 'remove':
            uninstall_service()
        elif sys.argv[1].lower() == 'start':
            start_service()
        elif sys.argv[1].lower() == 'stop':
            stop_service()
        elif sys.argv[1].lower() == 'restart':
            stop_service()
            time.sleep(2)
            start_service()
        elif sys.argv[1].lower() == 'status':
            # Check service status
            try:
                import win32service
                scm = win32service.OpenSCManager(None, None, win32service.SC_MANAGER_ENUMERATE_SERVICE)
                try:
                    service = win32service.OpenService(scm, LightScopeService._svc_name_, win32service.SERVICE_QUERY_STATUS)
                    status = win32service.QueryServiceStatus(service)
                    if status[1] == win32service.SERVICE_RUNNING:
                        print(f"Service '{LightScopeService._svc_display_name_}' is RUNNING")
                    elif status[1] == win32service.SERVICE_STOPPED:
                        print(f"Service '{LightScopeService._svc_display_name_}' is STOPPED")
                    else:
                        print(f"Service '{LightScopeService._svc_display_name_}' status: {status[1]}")
                    win32service.CloseServiceHandle(service)
                except:
                    print(f"Service '{LightScopeService._svc_display_name_}' is NOT INSTALLED")
                finally:
                    win32service.CloseServiceHandle(scm)
            except Exception as e:
                print(f"Error checking service status: {e}")
        else:
            print("Usage:")
            print("  python lightscope-service-windows.py install   - Install service")
            print("  python lightscope-service-windows.py uninstall - Uninstall service")
            print("  python lightscope-service-windows.py start     - Start service")
            print("  python lightscope-service-windows.py stop      - Stop service")
            print("  python lightscope-service-windows.py restart   - Restart service")
            print("  python lightscope-service-windows.py status    - Check service status")


if __name__ == '__main__':
    main() 