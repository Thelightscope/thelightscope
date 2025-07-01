#!/usr/bin/env python3
"""
LightScope Monitor
Ensures lightscope is installed, up-to-date, and running continuously.
"""
import sys
import time
import signal
import subprocess
import urllib.request
import json
import logging
import os
import threading
import psutil
import traceback
from importlib import metadata
from packaging.version import parse as parse_version
from datetime import datetime, timedelta

# --- Configuration ---
CHECK_INTERVAL = 15 * 60          # Check for updates every 15 minutes
HEALTH_CHECK_INTERVAL = 15        # Check process health every 15 seconds (reduced from 30)
RESTART_DELAY = 3                 # Wait 3 seconds before restarting (reduced from 5)
MAX_RESTART_ATTEMPTS = 10         # Max restarts within window (increased from 5)
RESTART_WINDOW = 10 * 60          # 10-minute window for restarts (increased from 5)
PYPI_JSON_URL = "https://pypi.org/pypi/lightscope/json"
LOG_FILE = os.path.expanduser("~/lightscope_monitor.log")

# Process startup timeout - how long to wait for process to stabilize
STARTUP_STABILIZATION_TIME = 5    # Wait 5 seconds to ensure process doesn't immediately crash

# --- Logging setup ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# --- Handle shutdown signals ---
def _handle_exit(signum, frame):
    logger.info(f"Received signal {signum}, exiting monitor...")
    sys.exit(0)

signal.signal(signal.SIGINT, _handle_exit)
signal.signal(signal.SIGTERM, _handle_exit)

# --- Track restarts to avoid loops ---
class RestartTracker:
    def __init__(self):
        self.attempts = []
        self.max_attempts = MAX_RESTART_ATTEMPTS
        self.window = timedelta(seconds=RESTART_WINDOW)

    def can_restart(self):
        now = datetime.now()
        # purge old attempts
        self.attempts = [t for t in self.attempts if now - t < self.window]
        if len(self.attempts) >= self.max_attempts:
            logger.error(
                f"Too many restarts ({len(self.attempts)}) within {RESTART_WINDOW}s."
            )
            return False
        return True

    def record_restart(self):
        self.attempts.append(datetime.now())
        logger.info(
            f"Recorded restart (" 
            f"{len(self.attempts)}/{self.max_attempts} in window)."
        )

# --- Version checks ---
def get_installed_version():
    try:
        return metadata.version("lightscope")
    except metadata.PackageNotFoundError:
        logger.warning("lightscope not installed")
        return None
    except Exception as e:
        logger.error(f"Error getting installed version: {e}")
        return None


def get_latest_version():
    retries = 3
    for i in range(retries):
        try:
            with urllib.request.urlopen(PYPI_JSON_URL, timeout=30) as r:
                data = json.load(r)
            return data["info"]["version"]
        except Exception as e:
            logger.warning(f"Update check failed (attempt {i+1}): {e}")
            time.sleep(5 * (i+1))
    logger.error("Giving up checking PyPI after retries")
    return None

# --- Install or upgrade ---
def install_or_upgrade():
    retries = 3
    for i in range(retries):
        cmd = [sys.executable, "-m", "pip", "install", "--upgrade", "lightscope"]
        logger.info(f"pip install (attempt {i+1}/{retries}): {' '.join(cmd)}")
        try:
            res = subprocess.run(
                cmd, capture_output=True, text=True, timeout=300
            )
            if res.returncode == 0:
                logger.info("pip install succeeded")
                return True
            logger.error(f"pip install failed: {res.stderr.strip()}")
        except subprocess.TimeoutExpired:
            logger.error("pip install timed out")
        except Exception as e:
            logger.error(f"pip install error: {e}")
        time.sleep(10 * (i+1))
    return False

# --- Spawn or restart the application ---
def spawn_app():
    """
    Spawn the lightscope application as a subprocess.
    Returns the process object or None if spawn failed.
    """
    try:
        logger.info("Launching lightscope...")
        
        # Set up environment
        env = os.environ.copy()
        env['PYTHONUNBUFFERED'] = '1'
        env['PYTHONDONTWRITEBYTECODE'] = '1'  # Prevent .pyc files
        
        # Use explicit command to avoid any PATH issues
        cmd = [sys.executable, "-m", "lightscope"]
        logger.info(f"Executing command: {' '.join(cmd)}")
        
        # Create subprocess with proper error handling
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Merge stderr into stdout
            text=True,
            bufsize=1,  # Line buffered
            env=env,
            universal_newlines=True
        )
        
        # Give process a moment to start and check if it's still alive
        time.sleep(STARTUP_STABILIZATION_TIME)
        
        if proc.poll() is not None:
            # Process already exited
            exit_code = proc.poll()
            logger.error(f"lightscope exited immediately with code {exit_code}")
            
            # Try to capture any error output
            try:
                output = proc.stdout.read()
                if output:
                    logger.error(f"lightscope startup error output: {output}")
            except:
                pass
            
            return None
        
        logger.info(f"lightscope PID={proc.pid}")
        return proc
        
    except FileNotFoundError as e:
        logger.error(f"Failed to launch lightscope - command not found: {e}")
        logger.error("Make sure lightscope is properly installed")
        return None
    except subprocess.SubprocessError as e:
        logger.error(f"Subprocess error launching lightscope: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error launching lightscope: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return None

# --- Health check ---
def is_process_healthy(proc):
    if proc is None:
        return False
    
    # Check if process has exited
    exit_code = proc.poll()
    if exit_code is not None:
        logger.warning(f"Process {proc.pid} exited with code={exit_code}")
        return False
    
    try:
        # Use psutil for more robust process checking
        p = psutil.Process(proc.pid)
        
        # Check if process is still running
        if not p.is_running():
            logger.warning(f"Process {proc.pid} is no longer running")
            return False
            
        # Check process status - zombie processes are not healthy
        status = p.status()
        if status == psutil.STATUS_ZOMBIE:
            logger.warning(f"Process {proc.pid} is zombie")
            return False
            
        # Check if process is actually our lightscope process by examining cmdline
        try:
            cmdline = p.cmdline()
            if not any('lightscope' in arg for arg in cmdline):
                logger.warning(f"Process {proc.pid} cmdline doesn't contain 'lightscope': {cmdline}")
                return False
        except (psutil.AccessDenied, psutil.NoSuchProcess):
            # Process might have died or we don't have permission - treat as unhealthy
            logger.warning(f"Process {proc.pid} access denied or no such process")
            return False
            
        return True
        
    except psutil.NoSuchProcess:
        logger.warning(f"Process {proc.pid} no longer exists")
        return False
    except psutil.AccessDenied:
        logger.warning(f"Access denied to process {proc.pid}")
        return False
    except Exception as e:
        logger.error(f"Error checking process health: {e}")
        # If we can't determine health due to an error, assume it's still healthy
        # to avoid unnecessary restarts from transient errors
        return True

# --- Graceful shutdown ---
def graceful_shutdown(proc, timeout=30):
    """
    Gracefully shutdown a lightscope process.
    First tries SIGTERM, then SIGKILL if needed.
    """
    if not proc:
        return
        
    pid = proc.pid
    logger.info(f"Stopping lightscope PID={pid}")
    
    try:
        # Check if process is already dead
        if proc.poll() is not None:
            logger.info(f"Process {pid} already exited with code {proc.poll()}")
            return
            
        # Try graceful termination first
        logger.info(f"Sending SIGTERM to process {pid}")
        proc.terminate()
        
        try:
            # Wait for graceful shutdown
            proc.wait(timeout=timeout)
            logger.info(f"Process {pid} terminated gracefully")
        except subprocess.TimeoutExpired:
            # Process didn't terminate gracefully, force kill
            logger.warning(f"Process {pid} didn't terminate gracefully, sending SIGKILL")
            proc.kill()
            
            try:
                proc.wait(timeout=10)
                logger.info(f"Process {pid} killed successfully")
            except subprocess.TimeoutExpired:
                logger.error(f"Process {pid} still running after SIGKILL - may be zombie")
                
                # Try to clean up with psutil if available
                try:
                    p = psutil.Process(pid)
                    if p.is_running():
                        logger.warning(f"Force terminating stubborn process {pid}")
                        p.terminate()
                        p.wait(timeout=5)
                except psutil.NoSuchProcess:
                    logger.info(f"Process {pid} finally cleaned up")
                except Exception as e:
                    logger.error(f"Failed to cleanup process {pid}: {e}")
                    
    except ProcessLookupError:
        logger.info(f"Process {pid} already gone")
    except Exception as e:
        logger.error(f"Error stopping process {pid}: {e}")
        logger.error(f"Shutdown traceback: {traceback.format_exc()}")
    
    finally:
        # Ensure stdout is closed to prevent resource leaks
        try:
            if proc.stdout and not proc.stdout.closed:
                proc.stdout.close()
        except:
            pass

# --- Log application output ---
def output_reader(proc):
    """
    Read and log output from the lightscope process.
    This function runs in a separate thread and helps detect crashes
    by monitoring the output stream.
    """
    try:
        logger.info(f"Starting output reader for PID {proc.pid}")
        
        for line in iter(proc.stdout.readline, ''):
            if line:
                line = line.strip()
                if line:  # Only log non-empty lines
                    # Check for error patterns that indicate crashes
                    if any(pattern in line.lower() for pattern in [
                        'traceback', 'exception', 'error:', 'fatal', 'crash', 'failed'
                    ]):
                        logger.error(f"[lightscope] {line}")
                    else:
                        logger.info(f"[lightscope] {line}")
            
            # Check if process has terminated
            if proc.poll() is not None:
                logger.warning(f"Process {proc.pid} terminated while reading output")
                break
                
    except Exception as e:
        logger.error(f"Output reader error for PID {proc.pid}: {e}")
        logger.error(f"Output reader traceback: {traceback.format_exc()}")
    finally:
        logger.info(f"Output reader finished for PID {proc.pid}")
        
        # Try to capture any remaining output
        try:
            remaining = proc.stdout.read()
            if remaining:
                logger.info(f"[lightscope] Final output: {remaining.strip()}")
        except:
            pass

# --- Main loop ---
def main():
    logger.info("=== LightScope Monitor Started ===")
    tracker = RestartTracker()

    # ensure install
    current = get_installed_version()
    if not current:
        if not install_or_upgrade():
            logger.critical("Initial install failed")
            sys.exit(1)
        current = get_installed_version() or current

    proc = None
    out_thr = None
    last_update = 0
    last_health = 0

    try:
        while True:
            now = time.time()

            # health check with more detailed logging
            if now - last_health >= HEALTH_CHECK_INTERVAL:
                is_healthy = is_process_healthy(proc)
                
                if not is_healthy:
                    if proc is not None:
                        exit_code = proc.poll()
                        logger.warning(f"Health check failed for PID {proc.pid}, exit_code={exit_code}")
                        
                        # Try to capture any final output before shutdown
                        try:
                            if proc.stdout and not proc.stdout.closed:
                                remaining_output = proc.stdout.read()
                                if remaining_output:
                                    logger.info(f"[lightscope] Final output: {remaining_output.strip()}")
                        except:
                            pass
                    else:
                        logger.warning("Health check failed - no process running")
                    
                    # Graceful shutdown of the failed process
                    graceful_shutdown(proc)
                    proc = None
                    
                    # Wait for output thread to finish
                    if out_thr and out_thr.is_alive():
                        logger.info("Waiting for output thread to finish...")
                        out_thr.join(timeout=5)
                        if out_thr.is_alive():
                            logger.warning("Output thread did not finish in time")
                    
                    # Attempt restart if allowed
                    if tracker.can_restart():
                        logger.info(f"Attempting restart after {RESTART_DELAY} second delay...")
                        tracker.record_restart()
                        time.sleep(RESTART_DELAY)
                        
                        proc = spawn_app()
                        if proc:
                            logger.info(f"Successfully restarted lightscope with PID {proc.pid}")
                            out_thr = threading.Thread(
                                target=output_reader, args=(proc,), daemon=True
                            )
                            out_thr.start()
                        else:
                            logger.error("Failed to restart lightscope")
                    else:
                        logger.critical("Too many restart attempts - giving up")
                        break
                        
                last_health = now

            # update check (existing logic)
            if now - last_update >= CHECK_INTERVAL:
                try:
                    latest = get_latest_version()
                    if latest and current and parse_version(latest) > parse_version(current):
                        logger.info(f"Upgrading: {current} -> {latest}")
                        graceful_shutdown(proc)
                        proc = None
                        
                        # Wait for output thread to finish
                        if out_thr and out_thr.is_alive():
                            out_thr.join(timeout=10)
                        
                        if install_or_upgrade():
                            current = get_installed_version() or current
                            logger.info(f"Upgrade completed to version {current}")
                        else:
                            logger.error("Upgrade failed")
                            
                        proc = spawn_app()
                        if proc:
                            out_thr = threading.Thread(
                                target=output_reader, args=(proc,), daemon=True
                            )
                            out_thr.start()
                except Exception as e:
                    logger.error(f"Error during update check: {e}")
                    
                last_update = now

            # ensure process is running
            if not proc and tracker.can_restart():
                logger.info("No process running, starting lightscope...")
                tracker.record_restart()
                proc = spawn_app()
                if proc:
                    out_thr = threading.Thread(
                        target=output_reader, args=(proc,), daemon=True
                    )
                    out_thr.start()
                else:
                    logger.error("Failed to start lightscope")

            time.sleep(1)

    except KeyboardInterrupt:
        logger.info("Interrupted, shutting down")
    except Exception:
        logger.error("Unexpected error", exc_info=True)
    finally:
        graceful_shutdown(proc, timeout=60)
        logger.info("Monitor exiting")

if __name__ == "__main__":
    main()
