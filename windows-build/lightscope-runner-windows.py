#!/usr/bin/env python3
"""
LightScope Windows Runner Script with Auto-Update Capability
This script handles version checking, secure updates, and launching the main LightScope core on Windows.
"""

import os
import sys
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
                logger.error("Bundled public key not found in package installation")
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
            logger.error("No public key available for signature verification")
            return False
        
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
                urllib.request.urlretrieve(signature_url, sig_temp_path)
                
                # Verify signature
                if not self.verify_signature(core_temp_path, sig_temp_path):
                    logger.error("Signature verification failed - update aborted")
                    return False
                
                # Backup current version
                current_core = BIN_DIR / "lightscope_core.py"
                if current_core.exists():
                    backup_path = UPDATES_DIR / f"lightscope_core_backup_{int(time.time())}.py"
                    current_core.rename(backup_path)
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
        
        # Add the directory containing lightscope_core.py to Python path
        core_dir = core_path.parent
        if str(core_dir) not in sys.path:
            sys.path.insert(0, str(core_dir))
        
        # Import the core module
        import lightscope_core
        
        # Run the main function
        logger.info("Starting LightScope core...")
        lightscope_core.lightscope_run()
        
        # If we reach here, it means lightscope_run() exited normally
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
    """Check if Npcap is installed on Windows"""
    try:
        # Check for Npcap installation
        npcap_path = Path("C:/Windows/System32/Npcap")
        if not npcap_path.exists():
            logger.warning("Npcap not found in System32. Checking alternate locations...")
            
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
                logger.error("Npcap not found. Please install Npcap from https://nmap.org/npcap/")
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
    
    # Check for administrator privileges
    if not check_admin_privileges():
        logger.error("Administrator privileges required for packet capture")
        logger.error("Please run as Administrator")
        sys.exit(1)
    
    # Check for Npcap installation
    if not check_npcap_installation():
        logger.error("Npcap is required but not found")
        sys.exit(1)
    
    # Ensure directories exist
    ensure_directories()
    
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
        max_consecutive_failures = 3
        
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
                            # Exit so service will restart us with the new version
                            sys.exit(0)
                except Exception as e:
                    logger.error(f"Error during update check: {e}")
                
                last_update_check = current_time
            
            # Load and run the core
            if load_lightscope_core():
                # Normal shutdown or success
                break
            else:
                consecutive_failures += 1
                logger.error(f"LightScope core failed (attempt {consecutive_failures}/{max_consecutive_failures})")
                
                # If too many consecutive failures, exit and let service handle restart
                if consecutive_failures >= max_consecutive_failures:
                    logger.error("Too many consecutive failures, exiting...")
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