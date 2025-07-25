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
import webbrowser
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.exceptions import InvalidSignature
import rumps


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

runner_version = "1.0.0"

print(f"runner_version: {runner_version}")

UPDATE_CHECK_URL = "https://thelightscope.com/latest/version_mac"
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

# Log systemd availability info if needed
if not SYSTEMD_AVAILABLE:
    logger.info("Running on macOS - using LaunchAgent for process monitoring")

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
        """Load current version from lightscope_core_mac.py"""
        try:
            core_path = BIN_DIR / "lightscope_core_mac.py"
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
                        logger.warning("Could not extract version from lightscope_core_mac.py")
                        # Debug: show first few lines of file for troubleshooting
                        lines = content.splitlines()[:50]
                        logger.debug("First 50 lines of core file:")
                        for i, line in enumerate(lines, 1):
                            if 'version' in line.lower() or 'ls_version' in line:
                                logger.debug(f"Line {i}: {line}")
            else:
                logger.warning("lightscope_core_mac.py not found, assuming first run")
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
            
            # Configure SSL context for LibreSSL compatibility on macOS
            import ssl
            import platform
            
            # Use certifi for CA certificates to fix SSL verification on macOS
            try:
                import certifi
                ssl_context = ssl.create_default_context(cafile=certifi.where())
                logger.info("Using certifi CA certificates for SSL verification")
            except ImportError:
                logger.warning("certifi not available, using default SSL context")
                ssl_context = ssl.create_default_context()
            
            # Handle LibreSSL on macOS by setting appropriate TLS version and ciphers
            if platform.system() == "Darwin":
                # Force TLS 1.2+ for LibreSSL compatibility
                ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
                ssl_context.maximum_version = ssl.TLSVersion.TLSv1_3
                # Set ciphers that work well with LibreSSL
                ssl_context.set_ciphers('ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS')
            
            response = urllib.request.urlopen(UPDATE_CHECK_URL, context=ssl_context, timeout=30)
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
            
            if self.current_version != latest_version:
                logger.info(f"Update available: {self.current_version} -> {latest_version}")
                return True
            else:
                logger.info("Already running latest version")
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
                
                # Download the new lightscope_core_mac.py
                core_url = f"{DOWNLOAD_URL_BASE}/lightscope_core_mac.py"
                signature_url = f"{DOWNLOAD_URL_BASE}/lightscope_core_mac.py.sig"
                
                logger.info("Downloading new version...")
                
                # Configure SSL context for LibreSSL compatibility on macOS
                import ssl
                import platform
                
                # Helper function to create SSL context with certifi
                def create_ssl_context_with_certifi():
                    try:
                        import certifi
                        return ssl.create_default_context(cafile=certifi.where())
                    except ImportError:
                        logger.warning("certifi not available, using default SSL context")
                        return ssl.create_default_context()
                
                # Try multiple SSL configurations for better compatibility
                ssl_configs = []
                
                # Config 1: Default context with certifi
                try:
                    ssl_context1 = create_ssl_context_with_certifi()
                    ssl_configs.append(("Default SSL with certifi", ssl_context1))
                except Exception as e:
                    logger.warning(f"Default SSL context failed: {e}")
                
                # Config 2: TLS 1.2 specifically (good compatibility)
                try:
                    ssl_context2 = create_ssl_context_with_certifi()
                    ssl_context2.minimum_version = ssl.TLSVersion.TLSv1_2
                    ssl_context2.maximum_version = ssl.TLSVersion.TLSv1_2
                    ssl_configs.append(("TLS 1.2 with certifi", ssl_context2))
                except Exception as e:
                    logger.warning(f"TLS 1.2 context failed: {e}")
                
                # Config 3: LibreSSL optimized for macOS
                if platform.system() == "Darwin":
                    try:
                        ssl_context3 = create_ssl_context_with_certifi()
                        ssl_context3.minimum_version = ssl.TLSVersion.TLSv1_2
                        ssl_context3.maximum_version = ssl.TLSVersion.TLSv1_3
                        # Set ciphers that work well with LibreSSL
                        ssl_context3.set_ciphers('ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:ECDHE+AES256:DHE+AES256:!aNULL:!MD5:!DSS')
                        ssl_configs.append(("LibreSSL Optimized with certifi", ssl_context3))
                    except Exception as e:
                        logger.warning(f"LibreSSL optimized context failed: {e}")
                
                # Config 4: Broad TLS range
                try:
                    ssl_context4 = create_ssl_context_with_certifi()
                    ssl_context4.minimum_version = ssl.TLSVersion.TLSv1_2
                    # Don't set maximum to allow negotiation
                    ssl_configs.append(("TLS 1.2+ Range with certifi", ssl_context4))
                except Exception as e:
                    logger.warning(f"TLS 1.2+ range context failed: {e}")
                
                # Try each SSL configuration
                download_success = False
                for config_name, ssl_context in ssl_configs:
                    try:
                        logger.info(f"Trying download with {config_name}")
                        
                        # Install SSL context for urllib
                        https_handler = urllib.request.HTTPSHandler(context=ssl_context)
                        opener = urllib.request.build_opener(https_handler)
                        urllib.request.install_opener(opener)
                        
                        # Download core file
                        core_temp_path = temp_path / "lightscope_core_mac.py"
                        urllib.request.urlretrieve(core_url, core_temp_path)
                        
                        # Download signature
                        sig_temp_path = temp_path / "lightscope_core_mac.py.sig"
                        urllib.request.urlretrieve(signature_url, sig_temp_path)
                        
                        logger.info(f"Successfully downloaded files using {config_name}")
                        download_success = True
                        break
                        
                    except urllib.error.URLError as e:
                        if hasattr(e, 'reason') and 'SSL' in str(e.reason):
                            logger.warning(f"SSL download failed with {config_name}: {e}")
                            continue
                        else:
                            logger.error(f"URL error with {config_name}: {e}")
                            continue
                    except Exception as e:
                        logger.warning(f"Download failed with {config_name}: {e}")
                        continue
                
                # If all SSL configs failed, try basic urllib without custom SSL
                if not download_success:
                    logger.info("All SSL configurations failed, trying basic urllib")
                    try:
                        # Reset to default opener
                        urllib.request.install_opener(urllib.request.build_opener())
                        
                        # Download core file
                        core_temp_path = temp_path / "lightscope_core_mac.py"
                        urllib.request.urlretrieve(core_url, core_temp_path)
                        
                        # Download signature
                        sig_temp_path = temp_path / "lightscope_core_mac.py.sig"
                        urllib.request.urlretrieve(signature_url, sig_temp_path)
                        
                        logger.info("Successfully downloaded files using basic urllib")
                        download_success = True
                        
                    except Exception as e:
                        logger.error(f"Basic urllib download also failed: {e}")
                        return False
                
                if not download_success:
                    logger.error("All download attempts failed")
                    return False
                
                # Verify signature
                if not self.verify_signature(core_temp_path, sig_temp_path):
                    logger.error("Signature verification failed - update aborted")
                    return False
                
                # Backup current version
                current_core = BIN_DIR / "lightscope_core_mac.py"
                if current_core.exists():
                    backup_path = UPDATES_DIR / f"lightscope_core_backup_{int(time.time())}.py"
                    current_core.rename(backup_path)
                    logger.info(f"Backed up current version to {backup_path}")
                
                # Install new version
                import shutil
                shutil.copy2(core_temp_path, current_core)
                os.chmod(current_core, 0o644)
                
                logger.info("Update installed successfully")
                
                # Update current version
                self.load_current_version()
                return True
                
        except Exception as e:
            logger.error(f"Error downloading update: {e}")
            return False

    
    def view_dashboard(self, icon=None, item=None):
        """Open the LightScope dashboard in the default web browser"""
        try:
            # Update database name in case it has changed
            self.update_db_name_if_needed()
            
            # Construct dashboard URL
            dashboard_url = f"https://thelightscope.com/tables/{self.db_name}"
            
            logger.info(f"Opening dashboard: {dashboard_url}")
            webbrowser.open(dashboard_url)
            
        except Exception as e:
            logger.error(f"Error opening dashboard: {e}")
    
    def quit_lightscope(self, icon=None, item=None):
        """Quit LightScope application"""
        try:
            logger.info("Quit requested from notification")
            
            # Set shutdown event to signal all threads to stop
            shutdown_event.set()
            
            # Exit the main process
            os._exit(0)
            
        except Exception as e:
            logger.error(f"Error during quit: {e}")
            # Force exit if there's an error
            os._exit(1)
    
    def schedule_status_notification(self):
        """Schedule periodic status notifications"""
        def status_notification_thread():
            """Background thread to send periodic status notifications"""
            while not shutdown_event.is_set():
                try:
                    # Wait 4 hours before sending status notification
                    shutdown_event.wait(4 * 60 * 60)
                    
                    if not shutdown_event.is_set():
                        self.send_status_notification()
                        
                except Exception as e:
                    logger.error(f"Error in status notification thread: {e}")
                    # Sleep before retrying
                    shutdown_event.wait(60)
        
        # Start the background thread
        import threading
        thread = threading.Thread(target=status_notification_thread, daemon=True)
        thread.start()
        logger.info("Status notification thread started")
        return thread

def notify_systemd_watchdog():
    """Send watchdog notification to systemd (Linux) or no-op on macOS"""
    if SYSTEMD_AVAILABLE:
        try:
            systemd.daemon.notify('WATCHDOG=1')
            logger.debug("Sent watchdog notification to systemd")
        except Exception as e:
            logger.warning(f"Failed to send watchdog notification: {e}")
    # On macOS, this is a no-op since LaunchAgent handles process monitoring

def notify_systemd_ready():
    """Notify systemd that the service is ready (Linux) or no-op on macOS"""
    if SYSTEMD_AVAILABLE:
        try:
            systemd.daemon.notify('READY=1')
            logger.info("Notified systemd that service is ready")
        except Exception as e:
            logger.warning(f"Failed to notify systemd ready: {e}")
    # On macOS, this is a no-op since LaunchAgent handles service readiness

def ensure_directories():
    """Ensure all required directories exist"""
    for directory in [CONFIG_DIR, UPDATES_DIR, LOGS_DIR, BIN_DIR]:
        directory.mkdir(parents=True, exist_ok=True)

def update_checker_thread(updater):
    """Background thread that periodically checks for updates"""
    logger.info("Update checker thread started")
    last_update_check = time.time()
    update_interval = 60 * 60  # Every hour
    
    while not shutdown_event.is_set():
        try:
            current_time = time.time()
            
            # Check for updates periodically
            if current_time - last_update_check > update_interval:
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
            # Sleep before retrying
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
            shutdown_event.wait(15)
    
    logger.info("Watchdog thread exiting")

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    shutdown_event.set()

def load_lightscope_core():
    """Dynamically load and execute lightscope_core_mac.py with proper threading support"""
    global lightscope_process
    
    try:
        core_path = BIN_DIR / "lightscope_core_mac.py"
        
        if not core_path.exists():
            logger.error("lightscope_core_mac.py not found!")
            return False
        
        # Add the bin directory to Python path
        if str(BIN_DIR) not in sys.path:
            sys.path.insert(0, str(BIN_DIR))
        
               # Import (or reload) the core module so we always have a local name
        import importlib
        if 'lightscope_core' in sys.modules:
            lightscope_core_mac = importlib.reload(sys.modules['lightscope_core_mac'])
        else:
            import lightscope_core_mac  # binds the name in this scope

        # Set global references for the core
        # Always set watchdog function (will be no-op on macOS)
        lightscope_core_mac.systemd_watchdog_notify = notify_systemd_watchdog

        
        # Set shutdown event reference so core can check for shutdown
        lightscope_core_mac.runner_shutdown_event = shutdown_event
        lightscope_core_mac.runner_update_event = update_available_event
        
        # Run the main function in a way that can be interrupted
        logger.info("Starting LightScope core...")
        
        def run_core():
            try:
                lightscope_core_mac.lightscope_run()
            except Exception as e:
                logger.error(f"LightScope core error: {e}")
                import traceback
                logger.error(f"Traceback: {traceback.format_exc()}")
                shutdown_event.set()
        
        # Start LightScope in a separate thread so we can monitor for updates
        core_thread = threading.Thread(target=run_core, name="LightScope-Core")
        core_thread.daemon = True
        core_thread.start()
        lightscope_process = core_thread
        
        # Wait for either shutdown or update signal
        while core_thread.is_alive():
            if shutdown_event.is_set():
                logger.info("Shutdown requested, stopping LightScope core...")
                break
            elif update_available_event.is_set():
                logger.info("Update available, stopping LightScope core for restart...")
                shutdown_event.set()
                break
            
            # Check every second
            time.sleep(1)
        
        # Wait for core thread to finish (with timeout)
        core_thread.join(timeout=30)
        
        if update_available_event.is_set():
            logger.info("LightScope core stopped for update, will restart with new version")
            return "restart"  # Special return value for restart
        else:
            logger.info("LightScope core exited normally")
            return True
        
    except KeyboardInterrupt:
        logger.info("Received interrupt signal, shutting down...")
        shutdown_event.set()
        return True
    except Exception as e:
        logger.error(f"Error running lightscope_core: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return False


"""
# Create a tiny status‑bar app to host the icon
class _MenuBarIcon(rumps.App):
    def __init__(self):
        super().__init__(
            name="LightScope",
            icon=str(Path(__file__).parent.parent  / "ls.png"),
            menu=None  # no menu or you can add ["Quit"]
        )
        # Start your main runner logic on a background thread so the menu loop doesn't block
        threading.Thread(target=self._start_runner, daemon=True).start()

    def _start_runner(self):
        # import and call your existing main() here
        runner_main()

# Instantiate before anything else
_menu_app = _MenuBarIcon()

if __name__ == "__main__":
    _menu_app.run()  # this starts the status‑bar app + your runner in the background
"""

import subprocess
import webbrowser
from pathlib import Path

class _MenuBarIcon(rumps.App):
    def __init__(self):
        script = '''display dialog "Welcome to LightScope! There is now a menu bar icon in the top right corner of your screen. You can click it to view detailed information about your unwanted traffic and who's targeting you.

        If you receive ANY unwanted traffic, we will pop an alert.
        If you see one of these while you're connected to a sketchy Wi‑Fi hotspot, you should disconnect right away.

        If you see one of these while you're at home, one of your devices (router, Fire Stick, etc.) may be compromised, and you should investigate based on the information in your dashboard.

        Thank you for using LightScope!" buttons {"OK"} default button "OK" with title "LightScope"'''


        subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            check=False
        )

        # Configuration
        if Path("/Applications/LightScope.app/Contents/Resources").exists():
            LIGHTSCOPE_HOME = Path("/Applications/LightScope.app/Contents/Resources")
        else:
            LIGHTSCOPE_HOME = Path("/opt/lightscope")

        CONFIG_DIR  = LIGHTSCOPE_HOME / "config"
        UPDATES_DIR = LIGHTSCOPE_HOME / "updates"
        LOGS_DIR    = LIGHTSCOPE_HOME / "logs"
        BIN_DIR     = LIGHTSCOPE_HOME / "bin"

        #  ─── Ensure they all exist ─────────────────────────────────────────────
        for d in (CONFIG_DIR, UPDATES_DIR, LOGS_DIR, BIN_DIR):
            d.mkdir(parents=True, exist_ok=True)

        #  ─── Now it’s safe to set up logging ─────────────────────────────────
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(LOGS_DIR / "lightscope-runner.log"),
                logging.StreamHandler()
            ]
        )
        logger = logging.getLogger("lightscope-runner")

        logger.info("Starting LightScope‑Runner (menu‑bar edition)")

        #  ─── Set up the menu ──────────────────────────────────────────────────


        super().__init__(
            name="LightScope",
            icon=str(Path(__file__).parent.parent / "ls.png"),
            menu=["View Dashboard"],
            quit_button=None,
        )
        # Start your main runner logic on a background thread so the menu loop doesn't block
        self.runner_thread=threading.Thread(target=self._start_runner, daemon=True).start()

    def _start_runner(self):
        try:
            runner_main()
        except Exception as e:
            logger.error(f"Error in _start_runner: {e}")


    @rumps.clicked("View Dashboard")
    def _view_dashboard(self, _):
        """Read database_id and open the dashboard URL in the browser."""
        cmd = (
            "grep '^database = ' "
            "/Applications/LightScope.app/Contents/Resources/config.ini "
            "| cut -d'=' -f2 | tr -d ' '"
        )
        try:
            database_id = subprocess.check_output(cmd, shell=True, text=True).strip()
            url = f"https://thelightscope.com/light_table/{database_id}"
            webbrowser.open(url)
        except subprocess.CalledProcessError as e:
            logger.error("Error", f"Could not read database ID:\n{e}")

    @rumps.clicked("Quit")
    def _quit(self, _):

        plist_path = os.path.expanduser(
            "~/Library/LaunchAgents/com.thelightscope.lightscope.plist"
        )

        try:
            subprocess.run(
                ["launchctl", "unload", plist_path],
                check=True,
            )
            print(f"Successfully unloaded {plist_path}")
        except subprocess.CalledProcessError as e:
            print(f"Error unloading plist: {e}")




        self.runner_thread.join(timeout=1)
        # Tell every background loop to break out
        shutdown_event.set()

        # Give things a moment to unwind (optional)
        time.sleep(1)


        # Now quit the status‑bar app
        rumps.quit_application()

        # As a belt‑and‑suspenders, kill the process outright
        os._exit(0)







def runner_main():
    """Main runner function with proper threading architecture"""


    logger.info("LightScope Runner starting...")
    
    # Setup signal handlers
    try:
            signal.signal(signal.SIGTERM, signal_handler)
            signal.signal(signal.SIGINT,  signal_handler)
            logger.info("Signal handlers installed")
    except (ValueError, OSError) as e:
        # ValueError: “signal only works in main thread…”
        logger.info(f"Skipping signal installation in thread: {e}")
    
    # Ensure directories exist
    ensure_directories()
    
    # Initialize updater
    updater = SecureUpdater()
    

    
    # Log notification availability warning if needed

    
    # Notify systemd that we're ready to start
    notify_systemd_ready()
    
    try:
        # Check for updates on startup
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
                continue
            elif result:
                # Normal shutdown
                break
            else:
                # Failure
                consecutive_failures += 1
                logger.error(f"LightScope core failed (attempt {consecutive_failures})")
                
                
                # Wait before retry with exponential backoff
                sleep_time = min(10 * (2 ** (consecutive_failures - 1)), 60)
                logger.info(f"Retrying in {sleep_time} seconds...")
                
                for _ in range(sleep_time):
                    if shutdown_event.is_set():
                        break
                    time.sleep(1)
        
        logger.info("Main loop exiting, shutting down threads...")
        shutdown_event.set()
        
        # Wait for threads to finish
        update_thread.join(timeout=5)
        watchdog_bg_thread.join(timeout=5)
        
    except KeyboardInterrupt:
        logger.info("Received interrupt, shutting down...")
        shutdown_event.set()
    except Exception as e:
        logger.error(f"Fatal error in runner: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        sys.exit(1)

# Instantiate before anything else


if __name__ == "__main__":
    _menu_app = _MenuBarIcon()
    _menu_app.run()