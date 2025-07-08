#!/usr/bin/env python3
"""
LightScope Windows Runner Script with Auto-Update Capability
This script handles version checking, secure updates, and launching the main LightScope core on Windows.
Designed to run as a user-level startup application without requiring administrator privileges.
"""

# Hide console window when running with python.exe (instead of pythonw.exe)
import os
import sys

# Check if we should hide the console window
HIDE_CONSOLE = os.environ.get('LIGHTSCOPE_HIDE_CONSOLE', 'true').lower() == 'true'

if HIDE_CONSOLE and sys.platform.startswith('win'):
    try:
        import ctypes
        import ctypes.wintypes
        
        # Get the console window handle
        kernel32 = ctypes.windll.kernel32
        user32 = ctypes.windll.user32
        
        # Get console window
        console_window = kernel32.GetConsoleWindow()
        
        if console_window != 0:
            # Hide the console window (SW_HIDE = 0)
            user32.ShowWindow(console_window, 0)
            print("Console window hidden successfully")
        else:
            print("No console window found to hide")
            
    except Exception as e:
        print(f"Could not hide console window: {e}")

import time
import json
import hashlib
import logging
import tempfile
import subprocess
import urllib.request
import urllib.error
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.exceptions import InvalidSignature
import psutil

# Test pywintypes import at startup
print("Testing pywintypes import...")
try:
    import pywintypes
    print("✓ SUCCESS: pywintypes imported successfully")
except ImportError as e:
    print(f"✗ FAILED: pywintypes import failed - {e}")
    print("This indicates pywin32 is not properly installed in the current Python environment")
except Exception as e:
    print(f"✗ ERROR: Unexpected error importing pywintypes - {e}")

# Configuration
# Dynamically determine installation directory based on script location
SCRIPT_DIR = Path(__file__).parent.absolute()
# If running from bin subdirectory, parent is LIGHTSCOPE_HOME
if SCRIPT_DIR.name == "bin":
    LIGHTSCOPE_HOME = SCRIPT_DIR.parent
else:
    # If running from root directory, use current directory
    LIGHTSCOPE_HOME = SCRIPT_DIR

CONFIG_DIR = LIGHTSCOPE_HOME / "config"
UPDATES_DIR = LIGHTSCOPE_HOME / "updates"
LOGS_DIR = LIGHTSCOPE_HOME / "logs"
BIN_DIR = LIGHTSCOPE_HOME / "bin"

# If BIN_DIR doesn't exist, we're probably running from the root directory
if not BIN_DIR.exists():
    BIN_DIR = LIGHTSCOPE_HOME

UPDATE_CHECK_URL = "https://thelightscope.com/latest/version"
DOWNLOAD_URL_BASE = "https://thelightscope.com/latest"

# Ensure logs directory exists before setting up logging
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOGS_DIR / "lightscope-runner.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("lightscope-runner")

# Check if we're running in user mode
def is_user_mode():
    """Check if LightScope is configured to run in user mode"""
    try:
        config_file = CONFIG_DIR / "config.ini"
        if config_file.exists():
            with open(config_file, 'r') as f:
                content = f.read()
                # Check if user_mode is explicitly set to false
                if 'user_mode = false' in content.lower():
                    return False
    except Exception:
        pass
    return True  # Default to user mode for user-level operation

USER_MODE = is_user_mode()

class SecureUpdater:
    """Handles secure downloading and verification of LightScope updates"""
    
    def __init__(self):
        self.public_key = None
        self.current_version = None
        self.load_current_version()
        self.load_public_key()
    
    def load_current_version(self):
        """Load current version from lightscope_core.py"""
        try:
            core_path = BIN_DIR / "lightscope_core.py"
            if core_path.exists():
                with open(core_path, 'r') as f:
                    content = f.read()
                    # Extract version from ls_version = "x.x.x" line
                    import re
                    match = re.search(r'ls_version\s*=\s*["\']([^"\']+)["\']', content)
                    if match:
                        self.current_version = match.group(1)
                        logger.info(f"Current version: {self.current_version}")
                    else:
                        logger.warning("Could not extract version from lightscope_core.py")
            else:
                logger.warning("lightscope_core.py not found, assuming first run")
        except Exception as e:
            logger.error(f"Error loading current version: {e}")
    
    def load_public_key(self):
        """Load the bundled public key for signature verification"""
        # Try bundled public key first (installed with package)
        bundled_public_key_path = CONFIG_DIR / "lightscope-public.pem"
        
        try:
            if bundled_public_key_path.exists():
                with open(bundled_public_key_path, 'rb') as f:
                    self.public_key = serialization.load_pem_public_key(f.read())
                logger.info("Loaded bundled public key from package")
                return
            else:
                logger.warning("Bundled public key not found in package installation")
                logger.warning("Updates will be downloaded but signature verification may be limited")
                self.public_key = None
                
        except Exception as e:
            logger.error(f"Error loading bundled public key: {e}")
            self.public_key = None
    
    def check_for_updates(self):
        """Check if a newer version is available"""
        try:
            logger.info("Checking for updates...")
            response = urllib.request.urlopen(UPDATE_CHECK_URL, timeout=30)
            version_info = json.loads(response.read().decode('utf-8'))
            
            latest_version = version_info.get('version')
            if not latest_version:
                logger.error("Invalid version response from server")
                return False
            
            logger.info(f"Latest version: {latest_version}")
            
            if self.current_version != latest_version:
                logger.info(f"Update available: {self.current_version} -> {latest_version}")
                return True
            else:
                logger.info("Already running latest version")
                return False
                
        except urllib.error.URLError as e:
            logger.warning(f"Network error checking for updates: {e}")
            return False
        except Exception as e:
            logger.error(f"Error checking for updates: {e}")
            return False
    
    def verify_signature(self, file_path, signature_path):
        """Verify the digital signature of a file"""
        if not self.public_key:
            logger.warning("No public key available for signature verification")
            logger.warning("Proceeding with update but signature verification is skipped")
            return True  # Allow updates without signature verification in user mode
        
        try:
            # Read the file and signature
            with open(file_path, 'rb') as f:
                file_data = f.read()
            
            with open(signature_path, 'rb') as f:
                signature = f.read()
            
            # Verify signature
            self.public_key.verify(
                signature,
                file_data,
                padding.PSS(
                    mgf=padding.MGF1(hashes.SHA256()),
                    salt_length=padding.PSS.MAX_LENGTH
                ),
                hashes.SHA256()
            )
            
            logger.info("Signature verification successful")
            return True
            
        except InvalidSignature:
            logger.error("Invalid signature - file may be corrupted or tampered with")
            return False
        except Exception as e:
            logger.error(f"Error verifying signature: {e}")
            return False
    
    def download_update(self):
        """Download and verify the latest version"""
        try:
            # Create temporary directory for download
            with tempfile.TemporaryDirectory() as temp_dir:
                temp_path = Path(temp_dir)
                
                # Download the new lightscope_core.py
                core_url = f"{DOWNLOAD_URL_BASE}/lightscope_core.py"
                signature_url = f"{DOWNLOAD_URL_BASE}/lightscope_core.py.sig"
                
                logger.info("Downloading new version...")
                
                # Download core file
                core_temp_path = temp_path / "lightscope_core.py"
                urllib.request.urlretrieve(core_url, core_temp_path)
                
                # Download signature
                sig_temp_path = temp_path / "lightscope_core.py.sig"
                try:
                    urllib.request.urlretrieve(signature_url, sig_temp_path)
                    
                    # Verify signature
                    if not self.verify_signature(core_temp_path, sig_temp_path):
                        logger.error("Signature verification failed - update aborted")
                        return False
                except Exception as e:
                    logger.warning(f"Could not download signature file: {e}")
                    if not USER_MODE:
                        logger.error("Signature verification required but signature not available")
                        return False
                    else:
                        logger.warning("Proceeding with update without signature verification (user mode)")
                
                # Backup current version
                current_core = BIN_DIR / "lightscope_core.py"
                if current_core.exists():
                    backup_path = UPDATES_DIR / f"lightscope_core_backup_{int(time.time())}.py"
                    import shutil
                    shutil.copy2(current_core, backup_path)
                    logger.info(f"Backed up current version to {backup_path}")
                
                # Install new version
                import shutil
                shutil.copy2(core_temp_path, current_core)
                
                logger.info("Update installed successfully")
                
                # Update current version
                self.load_current_version()
                return True
                
        except Exception as e:
            logger.error(f"Error downloading update: {e}")
            return False

def ensure_directories():
    """Ensure all required directories exist"""
    for directory in [CONFIG_DIR, UPDATES_DIR, LOGS_DIR, BIN_DIR]:
        directory.mkdir(parents=True, exist_ok=True)

def get_python_executable():
    """Get the appropriate Python executable - prefer virtual environment if available"""
    # Check if we're in a virtual environment
    venv_python = None
    
    # Method 1: Check if we're already in an activated virtual environment
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        logger.info("Already running in virtual environment")
        return sys.executable
    
    # Method 2: Check for virtual environment in the LightScope installation directory
    try:
        # Try to find the virtual environment created by the installer
        venv_paths = [
            LIGHTSCOPE_HOME / "venv" / "Scripts" / "python.exe",
            LIGHTSCOPE_HOME.parent / "venv" / "Scripts" / "python.exe",  # In case we're in bin/
            Path(os.environ.get('LOCALAPPDATA', '')) / "LightScope" / "venv" / "Scripts" / "python.exe"
        ]
        
        for venv_path in venv_paths:
            if venv_path.exists():
                logger.info(f"Found virtual environment Python at: {venv_path}")
                # Test if the virtual environment Python works
                try:
                    result = subprocess.run([str(venv_path), "--version"], 
                                          capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        logger.info(f"Virtual environment Python verified: {result.stdout.strip()}")
                        return str(venv_path)
                except Exception as e:
                    logger.warning(f"Virtual environment Python not working: {e}")
                    continue
    except Exception as e:
        logger.warning(f"Error checking for virtual environment: {e}")
    
    # Method 3: Fall back to system Python
    logger.info("Using system Python")
    return sys.executable

def check_and_install_dependencies():
    """Check for required Python packages and install them if missing"""
    # Get the appropriate Python executable
    python_exe = get_python_executable()
    pip_cmd = [python_exe, "-m", "pip"]
    
    logger.info(f"Using Python executable: {python_exe}")
    
    # Check packages in order - some have special dependencies
    package_checks = [
        ("cryptography", "cryptography"),
        ("psutil", "psutil"), 
        ("requests", "requests"),
        ("dpkt", "dpkt"),
        ("pywin32", "pywintypes"),  # Check pywintypes instead of pywin32 as it's the actual import
        ("wmi", "wmi")
    ]
    
    missing_packages = []
    
    logger.info("Checking Python dependencies...")
    
    for install_name, import_name in package_checks:
        try:
            __import__(import_name)
            logger.info(f"OK {install_name}: available")
        except ImportError:
            logger.warning(f"MISSING {install_name}: missing")
            missing_packages.append(install_name)
    
    if missing_packages:
        logger.info(f"Installing missing packages: {', '.join(missing_packages)}")
        for package in missing_packages:
            try:
                logger.info(f"Installing {package}...")
                
                # Special handling for pywin32
                if package == "pywin32":
                    # Install pywin32 with force-reinstall to ensure proper registration
                    result = subprocess.run(
                        pip_cmd + ["install", "--force-reinstall", "pywin32"],
                        capture_output=True, text=True, timeout=300
                    )
                    
                    if result.returncode == 0:
                        logger.info("OK pywin32 package installed")
                        
                        # Try alternative pywin32 post-install methods
                        try:
                            logger.info("Running pywin32 post-install setup...")
                            
                            # Method 1: Try pywin32_postinstall module
                            post_install_result = subprocess.run([
                                python_exe, "-m", "pywin32_postinstall", "-install"
                            ], capture_output=True, text=True, timeout=60)
                            
                            if post_install_result.returncode == 0:
                                logger.info("OK pywin32 post-install completed successfully")
                            else:
                                logger.warning(f"pywin32_postinstall not available, trying alternative method...")
                                
                                # Method 2: Try to import and test the modules directly
                                try:
                                    # Force reload the sys.path and try importing
                                    import importlib
                                    if hasattr(importlib, 'invalidate_caches'):
                                        importlib.invalidate_caches()
                                    
                                    # Test import of critical modules
                                    import pywintypes
                                    import pythoncom
                                    logger.info("OK pywin32 modules imported successfully after installation")
                                except ImportError as import_error:
                                    logger.warning(f"pywin32 modules still not available: {import_error}")
                                    logger.warning("pywin32 installation may need manual intervention")
                        except Exception as e:
                            logger.warning(f"pywin32 post-install error: {e}")
                    else:
                        logger.error(f"ERROR Failed to install pywin32: {result.stderr}")
                else:
                    # Regular package installation
                    result = subprocess.run(
                        pip_cmd + ["install", package],
                        capture_output=True, text=True, timeout=300
                    )
                    
                    if result.returncode == 0:
                        logger.info(f"OK Successfully installed {package}")
                    else:
                        logger.error(f"ERROR Failed to install {package}: {result.stderr}")
                        
            except subprocess.TimeoutExpired:
                logger.error(f"ERROR Timeout installing {package}")
            except Exception as e:
                logger.error(f"ERROR Error installing {package}: {e}")
    else:
        logger.info("All required Python packages are available")

def load_lightscope_core():
    """Dynamically load and execute lightscope_core.py"""
    try:
        # Try to find lightscope_core.py in multiple locations
        possible_paths = [
            BIN_DIR / "lightscope_core.py",
            LIGHTSCOPE_HOME / "lightscope_core.py",
            SCRIPT_DIR / "lightscope_core.py",
        ]
        
        core_path = None
        for path in possible_paths:
            if path.exists():
                core_path = path
                logger.info(f"Found lightscope_core.py at: {core_path}")
                break
        
        if not core_path:
            logger.error(f"lightscope_core.py not found! Searched in:")
            for path in possible_paths:
                logger.error(f"  - {path}")
            return False
        
        # Log core file details
        try:
            import stat
            core_stat = core_path.stat()
            logger.info(f"Core file size: {core_stat.st_size} bytes")
            logger.info(f"Core file modified: {time.ctime(core_stat.st_mtime)}")
        except Exception as stat_error:
            logger.warning(f"Could not get core file stats: {stat_error}")
        
        # Add the directory containing lightscope_core.py to Python path
        core_dir = core_path.parent
        if str(core_dir) not in sys.path:
            sys.path.insert(0, str(core_dir))
            logger.info(f"Added to Python path: {core_dir}")
        
        # Preserve current logging configuration
        current_logger = logger
        current_handlers = logger.handlers.copy()
        current_level = logger.level
        logger.info("Preserved current logging configuration")
        
        # Import the core module
        logger.info("Importing lightscope_core module...")
        try:
            import lightscope_core
            logger.info("Successfully imported lightscope_core module")
            
            # Check if lightscope_core has the expected function
            if hasattr(lightscope_core, 'lightscope_run'):
                logger.info("Found lightscope_run function in core module")
            else:
                logger.error("lightscope_run function not found in core module!")
                available_functions = [attr for attr in dir(lightscope_core) if callable(getattr(lightscope_core, attr)) and not attr.startswith('_')]
                logger.error(f"Available functions: {available_functions}")
                return False
                
        except ImportError as import_error:
            logger.error(f"Failed to import lightscope_core: {import_error}")
            return False
        except Exception as import_exception:
            logger.error(f"Unexpected error importing lightscope_core: {import_exception}")
            return False
        
        # Capture stdout/stderr to catch any prints from lightscope_core
        import io
        import contextlib
        
        # Create string buffers to capture output
        stdout_buffer = io.StringIO()
        stderr_buffer = io.StringIO()
        
        logger.info("Starting LightScope core...")
        logger.info("=" * 50)
        
        # Run the main function with output capture
        try:
            with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
                lightscope_core.lightscope_run()
        except Exception as core_error:
            # Log any captured output before handling the error
            stdout_content = stdout_buffer.getvalue()
            stderr_content = stderr_buffer.getvalue()
            
            if stdout_content:
                logger.info("Captured stdout from lightscope_core:")
                for line in stdout_content.splitlines():
                    logger.info(f"  STDOUT: {line}")
            
            if stderr_content:
                logger.error("Captured stderr from lightscope_core:")
                for line in stderr_content.splitlines():
                    logger.error(f"  STDERR: {line}")
            
            raise core_error
        
        # Log any captured output from successful run
        stdout_content = stdout_buffer.getvalue()
        stderr_content = stderr_buffer.getvalue()
        
        if stdout_content:
            logger.info("Captured stdout from lightscope_core:")
            for line in stdout_content.splitlines():
                logger.info(f"  STDOUT: {line}")
        
        if stderr_content:
            logger.warning("Captured stderr from lightscope_core:")
            for line in stderr_content.splitlines():
                logger.warning(f"  STDERR: {line}")
        
        # Restore logging configuration if it was changed
        if logger.handlers != current_handlers or logger.level != current_level:
            logger.warning("Logging configuration was modified by lightscope_core, restoring...")
            logger.handlers = current_handlers
            logger.level = current_level
        
        logger.info("=" * 50)
        logger.info("LightScope core exited normally")
        return True
        
    except KeyboardInterrupt:
        logger.info("Received interrupt signal, shutting down...")
        return True
    except Exception as e:
        logger.error(f"Error running lightscope_core: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Force cleanup of any remaining processes
        try:
            import signal
            import psutil
            
            # Get current process and all its children
            current_process = psutil.Process()
            children = current_process.children(recursive=True)
            
            if children:
                logger.warning(f"Cleaning up {len(children)} child processes...")
                for child in children:
                    try:
                        child.terminate()
                    except psutil.NoSuchProcess:
                        pass
                
                # Wait for children to terminate
                psutil.wait_procs(children, timeout=5)
                
                # Force kill any remaining children
                for child in children:
                    try:
                        if child.is_running():
                            child.kill()
                    except psutil.NoSuchProcess:
                        pass
                        
        except Exception as cleanup_error:
            logger.error(f"Error during process cleanup: {cleanup_error}")
        
        return False

def check_npcap_installation():
    """Check if Npcap is installed on Windows (REQUIRED)"""
    try:
        # Check for Npcap installation
        npcap_path = Path("C:/Windows/System32/Npcap")
        if not npcap_path.exists():
            logger.error("Npcap not found in System32. Checking alternate locations...")
            
            # Check alternate locations
            alt_paths = [
                Path("C:/Windows/System32/wpcap.dll"),
                Path("C:/Windows/System32/Packet.dll")
            ]
            
            found = False
            for path in alt_paths:
                if path.exists():
                    found = True
                    break
            
            if not found:
                logger.error("CRITICAL: Npcap not found!")
                logger.error("Npcap is REQUIRED for LightScope to function")
                logger.error("Please install Npcap from https://nmap.org/npcap/")
                logger.error("Make sure to enable 'WinPcap compatibility' during installation")
                return False
        
        logger.info("Npcap installation detected")
        return True
        
    except Exception as e:
        logger.error(f"Error checking Npcap installation: {e}")
        return False

def check_admin_privileges():
    """Check if running with administrator privileges"""
    try:
        import ctypes
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def main():
    """Main runner function"""
    logger.info("LightScope Windows Runner starting...")
    
    # Log detected paths for debugging
    logger.info(f"Script directory: {SCRIPT_DIR}")
    logger.info(f"LightScope home: {LIGHTSCOPE_HOME}")
    logger.info(f"Config directory: {CONFIG_DIR}")
    logger.info(f"Bin directory: {BIN_DIR}")
    logger.info(f"Logs directory: {LOGS_DIR}")
    logger.info(f"User mode: {USER_MODE}")
    
    # Check for administrator privileges
    has_admin = check_admin_privileges()
    logger.info(f"Administrator privileges: {has_admin}")
    
    # LightScope runs in user mode by default - no administrator privileges required
    if not has_admin:
        logger.info("Running in user mode (no administrator privileges)")
    else:
        logger.info("Running with administrator privileges")
    
    # Check for Npcap installation (REQUIRED)
    npcap_available = check_npcap_installation()
    if not npcap_available:
        logger.error("Npcap is REQUIRED but not found")
        logger.error("LightScope cannot function without Npcap")
        logger.error("Please install Npcap from https://nmap.org/npcap/ and restart LightScope")
        sys.exit(1)
    
    # Ensure directories exist
    ensure_directories()
    
    # Check and install Python dependencies
    check_and_install_dependencies()
    
    # Initialize updater
    updater = SecureUpdater()
    
    # Check for updates on startup
    try:
        if updater.check_for_updates():
            logger.info("Downloading and installing update...")
            if updater.download_update():
                logger.info("Update installed successfully, starting new version...")
            else:
                logger.error("Update failed, continuing with current version...")
        
        # Schedule next update check (every 24 hours)
        last_update_check = time.time()
        update_interval = 24 * 60 * 60  # 24 hours
        consecutive_failures = 0
        max_consecutive_failures = 5  # Increased from 3 to 5 for better recovery
        
        # Main execution loop with periodic update checks
        while True:
            current_time = time.time()
            
            # Check for updates periodically
            if current_time - last_update_check > update_interval:
                try:
                    if updater.check_for_updates():
                        logger.info("Update available, downloading...")
                        if updater.download_update():
                            logger.info("Update installed, restarting...")
                            # Exit so the startup system will restart us with the new version
                            sys.exit(0)
                except Exception as e:
                    logger.error(f"Error during update check: {e}")
                
                last_update_check = current_time
            
            # Load and run the core
            if load_lightscope_core():
                # Normal shutdown or success
                logger.info("LightScope core completed successfully")
                break
            else:
                consecutive_failures += 1
                logger.error(f"LightScope core failed (attempt {consecutive_failures}/{max_consecutive_failures})")
                
                # If this is a dependency-related failure, try to fix it
                if consecutive_failures <= 3:  # Only try dependency fixes for first few attempts
                    logger.info("Checking if dependency issues can be resolved...")
                    check_and_install_dependencies()
                
                # If too many consecutive failures, exit and let startup system handle restart
                if consecutive_failures >= max_consecutive_failures:
                    logger.error("Too many consecutive failures, exiting...")
                    logger.error("This might indicate a persistent configuration or system issue")
                    logger.error("Please check the installation and system requirements")
                    sys.exit(1)
                
                # Wait before retry, with exponential backoff
                sleep_time = min(10 * (2 ** (consecutive_failures - 1)), 60)
                logger.info(f"Retrying in {sleep_time} seconds...")
                time.sleep(sleep_time)
                
    except KeyboardInterrupt:
        logger.info("Received interrupt, shutting down...")
    except Exception as e:
        logger.error(f"Fatal error in runner: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 