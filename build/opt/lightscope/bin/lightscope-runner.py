#!/usr/bin/env python3
"""
LightScope Runner Script with Auto-Update Capability
This script handles version checking, secure updates, and launching the main LightScope core.
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
import threading
import signal
import configparser
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.exceptions import InvalidSignature
from packaging import version as pkg_version


# Import systemd watchdog support
try:
    import systemd.daemon
    SYSTEMD_AVAILABLE = True
except ImportError:
    SYSTEMD_AVAILABLE = False
    # Note: logger not yet defined, will log this later

# Configuration
# Detect if running on macOS in app bundle or Linux
if Path("/Applications/LightScope.app/Contents/Resources").exists():
    # macOS app bundle
    LIGHTSCOPE_HOME = Path("/Applications/LightScope.app/Contents/Resources")
    CONFIG_DIR = LIGHTSCOPE_HOME / "config"
    UPDATES_DIR = LIGHTSCOPE_HOME / "updates"
    LOGS_DIR = LIGHTSCOPE_HOME / "logs"
    BIN_DIR = LIGHTSCOPE_HOME / "bin"
else:
    # Linux/standard installation
    LIGHTSCOPE_HOME = Path("/opt/lightscope")
    CONFIG_DIR = LIGHTSCOPE_HOME / "config"
    UPDATES_DIR = LIGHTSCOPE_HOME / "updates"
    LOGS_DIR = LIGHTSCOPE_HOME / "logs"
    BIN_DIR = LIGHTSCOPE_HOME / "bin"

runner_version = "1.2.0"

print(f"runner_version: {runner_version}")

UPDATE_CHECK_URL = "https://thelightscope.com/latest/version"
DOWNLOAD_URL_BASE = "https://thelightscope.com/latest"

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

# Log systemd availability warning if needed
if not SYSTEMD_AVAILABLE:
    logger.warning("systemd module not available, watchdog notifications disabled")

# Global variables for thread coordination
shutdown_event = threading.Event()
update_available_event = threading.Event()
lightscope_process = None

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
                        logger.info(f"Current version: {self.current_version} (from {core_path})")
                        # Additional debug info
                        file_stat = core_path.stat()
                        logger.debug(f"Core file modified: {time.ctime(file_stat.st_mtime)}")
                        logger.debug(f"Core file size: {file_stat.st_size} bytes")
                    else:
                        logger.warning("Could not extract version from lightscope_core.py")
                        # Debug: show first few lines of file for troubleshooting
                        lines = content.splitlines()[:50]
                        logger.debug("First 50 lines of core file:")
                        for i, line in enumerate(lines, 1):
                            if 'version' in line.lower() or 'ls_version' in line:
                                logger.debug(f"Line {i}: {line}")
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
            logger.info(f"Checking for updates from: {UPDATE_CHECK_URL}")
            response = urllib.request.urlopen(UPDATE_CHECK_URL, timeout=30)
            response_data = response.read().decode('utf-8')
            logger.info(f"Server response received from {UPDATE_CHECK_URL}")
            logger.debug(f"Server response content: {response_data}")
            
            version_info = json.loads(response_data)
            
            latest_version = version_info.get('version')
            if not latest_version:
                logger.error("Invalid version response from server")
                logger.error(f"Response data: {response_data}")
                return False
            
            logger.info(f"Latest version: {latest_version}")
            logger.info(f"Current version: {self.current_version}")

            # Only update if server version is newer (prevent downgrades)
            try:
                current_ver = pkg_version.parse(self.current_version)
                latest_ver = pkg_version.parse(latest_version)

                if latest_ver > current_ver:
                    logger.info(f"Update available: {self.current_version} -> {latest_version}")
                    return True
                elif latest_ver < current_ver:
                    logger.warning(f"Server version {latest_version} is older than current {self.current_version} - skipping downgrade")
                    return False
                else:
                    logger.info("Already running latest version")
                    return False
            except Exception as e:
                logger.error(f"Error comparing versions: {e}")
                # Fall back to simple string comparison if version parsing fails
                if self.current_version != latest_version:
                    logger.warning(f"Version parsing failed, using string comparison")
                    return True
                return False
                
        except urllib.error.URLError as e:
            logger.warning(f"Network error checking for updates: {e}")
            return False
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON response from server: {e}")
            logger.error(f"Response data: {response_data if 'response_data' in locals() else 'N/A'}")
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
                
                # Install new version using atomic swap for safety
                import shutil
                current_core = BIN_DIR / "lightscope_core.py"
                temp_target = current_core.with_suffix('.py.new')

                # Step 1: Copy new file to same directory with temp name
                shutil.copy2(core_temp_path, temp_target)
                os.chmod(temp_target, 0o644)

                try:
                    # Step 2: Backup old file (copy, not move - original stays in place)
                    if current_core.exists():
                        backup_path = UPDATES_DIR / f"lightscope_core_backup_{int(time.time())}.py"
                        shutil.copy2(current_core, backup_path)
                        logger.info(f"Backed up current version to {backup_path}")

                    # Step 3: Atomic rename (same filesystem guarantees atomicity)
                    temp_target.rename(current_core)
                except Exception as e:
                    # Clean up temp file if something went wrong
                    if temp_target.exists():
                        temp_target.unlink()
                    raise
                
                logger.info("Update installed successfully")
                
                # Update current version
                self.load_current_version()
                return True
                
        except Exception as e:
            logger.error(f"Error downloading update: {e}")
            return False

def notify_systemd_watchdog():
    """Send watchdog notification to systemd"""
    if SYSTEMD_AVAILABLE:
        try:
            systemd.daemon.notify('WATCHDOG=1')
            logger.debug("Sent watchdog notification to systemd")
        except Exception as e:
            logger.warning(f"Failed to send watchdog notification: {e}")

def notify_systemd_ready():
    """Notify systemd that the service is ready"""
    if SYSTEMD_AVAILABLE:
        try:
            systemd.daemon.notify('READY=1')
            logger.info("Notified systemd that service is ready")
        except Exception as e:
            logger.warning(f"Failed to notify systemd ready: {e}")

def ensure_directories():
    """Ensure all required directories exist"""
    for directory in [CONFIG_DIR, UPDATES_DIR, LOGS_DIR, BIN_DIR]:
        directory.mkdir(parents=True, exist_ok=True)

def is_autoupdate_disabled():
    """Check if autoupdate is explicitly disabled in config.ini. Returns True if disabled, False otherwise."""
    config_path = Path("/opt/lightscope/config.ini")
    try:
        if config_path.exists():
            config = configparser.ConfigParser()
            config.read(config_path)
            if 'Settings' in config:
                autoupdate = config.get('Settings', 'autoupdate', fallback='').lower().strip()
                return autoupdate in ['no', 'false']
    except Exception as e:
        logger.debug(f"Could not read autoupdate config: {e}")
    return False  # Default to updates enabled

def update_checker_thread(updater):
    """Background thread that periodically checks for updates"""
    logger.info("Update checker thread started")
    last_update_check = time.time()
    update_interval = 60 * 5  # Every 5 minutes
    
    while not shutdown_event.is_set():
        try:
            current_time = time.time()
            
            # Check for updates periodically
            if current_time - last_update_check > update_interval:
                if is_autoupdate_disabled():
                    logger.info("Auto-updates disabled in config, skipping update check")
                    last_update_check = current_time
                else:
                    logger.info("Performing periodic update check...")
                    if updater.check_for_updates():
                        logger.info("Update available! Downloading...")
                        if updater.download_update():
                            logger.info("Update downloaded successfully, signaling restart...")
                            update_available_event.set()
                            break
                        else:
                            logger.error("Update download failed")
                    
                    last_update_check = current_time
            
            # Sleep for 60 seconds before next check (or until shutdown)
            shutdown_event.wait(60)

        except Exception as e:
            logger.error(f"Error in update checker thread: {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            # Sleep before retrying to prevent rapid failures from consuming CPU
            logger.info("Update checker sleeping 5 minutes after error before retry...")
            shutdown_event.wait(300)  # 5 minutes
    
    logger.info("Update checker thread exiting")

def watchdog_thread():
    """Background thread that sends systemd watchdog notifications"""
    logger.info("Watchdog thread started")

    while not shutdown_event.is_set():
        try:
            notify_systemd_watchdog()
            # Sleep for 15 seconds before next watchdog
            shutdown_event.wait(15)
        except Exception as e:
            logger.error(f"Error in watchdog thread: {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            # Sleep to prevent rapid failures from consuming CPU
            shutdown_event.wait(15)

    logger.info("Watchdog thread exiting")

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    shutdown_event.set()

def load_lightscope_core():
    """Dynamically load and execute lightscope_core.py with proper threading support"""
    global lightscope_process
    
    try:
        core_path = BIN_DIR / "lightscope_core.py"
        
        if not core_path.exists():
            logger.error("lightscope_core.py not found!")
            return False
        
        # Add the bin directory to Python path
        if str(BIN_DIR) not in sys.path:
            sys.path.insert(0, str(BIN_DIR))
        
        # Import the core module (fresh import to get any updates)
        import importlib
        if 'lightscope_core' in sys.modules:
            lightscope_core = importlib.reload(sys.modules['lightscope_core'])
        else:
            import lightscope_core
        
        # Set global references for the core
        if SYSTEMD_AVAILABLE:
            lightscope_core.systemd_watchdog_notify = notify_systemd_watchdog
        
        # Set shutdown event reference so core can check for shutdown
        lightscope_core.runner_shutdown_event = shutdown_event
        lightscope_core.runner_update_event = update_available_event
        
        # Run the main function in a way that can be interrupted
        logger.info("Starting LightScope core...")
        
        def run_core():
            try:
                lightscope_core.lightscope_run()
            except Exception as e:
                logger.error(f"LightScope core crashed with exception: {e}")
                import traceback
                logger.error(f"Traceback: {traceback.format_exc()}")
                # DO NOT set shutdown_event - let the runner detect the crash and retry
                # Sleep to prevent rapid CPU consumption if crashes happen immediately
                logger.info("Sleeping 30 seconds before runner can retry...")
                time.sleep(30)
        
        # Start LightScope in a separate thread so we can monitor for updates
        core_thread = threading.Thread(target=run_core, name="LightScope-Core")
        core_thread.daemon = True
        core_thread.start()
        lightscope_process = core_thread

        # Track why we're stopping - to distinguish shutdown vs crash vs update
        shutdown_requested = False
        update_requested = False

        # Wait for either shutdown or update signal
        while core_thread.is_alive():
            if shutdown_event.is_set():
                logger.info("Shutdown requested, stopping LightScope core...")
                shutdown_requested = True
                break
            elif update_available_event.is_set():
                logger.info("Update available, stopping LightScope core for restart...")
                shutdown_event.set()
                update_requested = True
                break

            # Check every second
            time.sleep(1)

        # Wait for core thread to finish (with timeout)
        core_thread.join(timeout=30)

        if update_requested or update_available_event.is_set():
            logger.info("LightScope core stopped for update, will restart with new version")
            return "restart"  # Special return value for restart
        elif shutdown_requested:
            logger.info("LightScope core stopped due to shutdown request")
            return True  # Normal shutdown
        else:
            # Thread died unexpectedly - this is a failure that needs retry
            logger.error("LightScope core thread died unexpectedly - treating as failure")
            return False  # Trigger retry with backoff
        
    except KeyboardInterrupt:
        logger.info("Received interrupt signal, shutting down...")
        shutdown_event.set()
        return True
    except Exception as e:
        logger.error(f"Error running lightscope_core: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return False

def main():
    """Main runner function with proper threading architecture"""
    logger.info("LightScope Runner starting...")

    # Setup signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Outer loop to handle fatal errors - runner should NEVER exit on its own
    fatal_error_count = 0
    while not shutdown_event.is_set():
        try:
            # Ensure directories exist
            ensure_directories()

            # Initialize updater
            updater = SecureUpdater()

            # Notify systemd that we're ready to start
            notify_systemd_ready()

            # Reset fatal error count on successful start
            fatal_error_count = 0

            # Check for updates on startup
            if is_autoupdate_disabled():
                logger.info("Auto-updates disabled in config, skipping startup update check")
            else:
                if updater.check_for_updates():
                    logger.info("Update available on startup, downloading...")
                    if updater.download_update():
                        logger.info("Startup update installed successfully")
                    else:
                        logger.error("Startup update failed, continuing with current version")

            # Start background threads
            update_thread = threading.Thread(target=update_checker_thread, args=(updater,), name="Update-Checker")
            update_thread.daemon = True
            update_thread.start()

            watchdog_bg_thread = threading.Thread(target=watchdog_thread, name="Watchdog")
            watchdog_bg_thread.daemon = True
            watchdog_bg_thread.start()

            consecutive_failures = 0

            # Main execution loop
            while not shutdown_event.is_set():
                result = load_lightscope_core()

                if result == "restart":
                    # Update was installed, restart with new version
                    logger.info("Restarting with updated version...")
                    consecutive_failures = 0
                    # Clear the update event and continue
                    update_available_event.clear()
                    shutdown_event.clear()

                    # Restart threads if they died during the update process
                    # (update_checker exits after finding update, watchdog exits when shutdown_event was set)
                    if not update_thread.is_alive():
                        logger.info("Restarting update checker thread...")
                        update_thread = threading.Thread(target=update_checker_thread, args=(updater,), name="Update-Checker")
                        update_thread.daemon = True
                        update_thread.start()

                    if not watchdog_bg_thread.is_alive():
                        logger.info("Restarting watchdog thread...")
                        watchdog_bg_thread = threading.Thread(target=watchdog_thread, name="Watchdog")
                        watchdog_bg_thread.daemon = True
                        watchdog_bg_thread.start()

                    continue
                elif result:
                    # Normal shutdown
                    break
                else:
                    # Failure - retry forever with exponential backoff
                    consecutive_failures += 1
                    logger.error(f"LightScope core failed (attempt {consecutive_failures})")
                    logger.info("Will retry indefinitely until successful or shutdown requested")

                    # Wait before retry with exponential backoff (min 30s, max 5 minutes)
                    sleep_time = min(max(30, 10 * (2 ** (consecutive_failures - 1))), 300)
                    logger.info(f"Waiting {sleep_time} seconds before retry to prevent CPU overload...")

                    for _ in range(sleep_time):
                        if shutdown_event.is_set():
                            break
                        time.sleep(1)

            logger.info("Main loop exiting, shutting down threads...")
            shutdown_event.set()

            # Wait for threads to finish
            update_thread.join(timeout=5)
            watchdog_bg_thread.join(timeout=5)

            # If we get here normally, break out of the outer fatal error retry loop
            break

        except KeyboardInterrupt:
            logger.info("Received interrupt, shutting down...")
            shutdown_event.set()
            break
        except Exception as e:
            # Fatal error in runner setup or main loop - retry with backoff
            fatal_error_count += 1
            logger.error(f"Fatal error in runner (attempt {fatal_error_count}): {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")

            if shutdown_event.is_set():
                logger.info("Shutdown requested, exiting despite fatal error")
                break

            # Wait before retrying with exponential backoff (min 30s, max 5 minutes)
            sleep_time = min(max(30, 10 * (2 ** (fatal_error_count - 1))), 300)
            logger.info(f"Fatal error recovery: waiting {sleep_time} seconds before retry...")

            for _ in range(sleep_time):
                if shutdown_event.is_set():
                    break
                time.sleep(1)

    logger.info("LightScope Runner exiting")

if __name__ == "__main__":
    main() 