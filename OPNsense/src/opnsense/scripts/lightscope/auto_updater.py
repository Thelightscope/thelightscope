#!/usr/local/bin/python3
"""
auto_updater.py - Automatic update module for LightScope OPNsense plugin

Checks for updates every 15 minutes, downloads FreeBSD packages from thelightscope.com,
verifies GPG signatures, and installs updates automatically.
"""

import os
import sys
import time
import hashlib
import shutil
import subprocess
import tempfile
import re

try:
    import requests
    from requests.adapters import HTTPAdapter
except ImportError:
    print("Error: requests not found", file=sys.stderr)
    sys.exit(1)

# Update Configuration
VERSION_URL = "https://thelightscope.com/opnsense/version.json"
PUBLIC_KEY_URL = "https://thelightscope.com/opnsense/keys/lightscope-release.pub"
PUBLIC_KEY_PATH = "/usr/local/share/lightscope/lightscope-release.pub"
DOWNLOAD_DIR = "/tmp/lightscope_update"
LOCK_FILE = "/var/run/lightscope_update.lock"
UPDATE_CHECK_INTERVAL = 15 * 60  # 15 minutes
EXTENDED_CHECK_INTERVAL = 60 * 60  # 1 hour (after failures)

# Current version (imported from daemon, but fallback here)
try:
    from lightscope_daemon import LS_VERSION
except ImportError:
    LS_VERSION = "opnsense-1.0"


class UpdateError(Exception):
    """Base exception for update errors."""
    pass


class NetworkError(UpdateError):
    """Network-related errors."""
    pass


class SignatureVerificationError(UpdateError):
    """GPG signature verification failed."""
    pass


class ChecksumError(UpdateError):
    """SHA256 checksum mismatch."""
    pass


class InstallationError(UpdateError):
    """Package installation failed."""
    pass


def log_update(message, level="INFO"):
    """Log update-related message to stdout (captured by daemon)."""
    print(f"[auto_updater] [{level}] {message}", flush=True)


def parse_version(version_string):
    """
    Parse version string into comparable tuple.
    Handles formats like "1.0", "1.1.2", "opnsense-1.0"
    """
    # Remove prefix like "opnsense-"
    clean = re.sub(r'^[a-zA-Z-]+', '', version_string)
    # Split into numeric parts
    parts = re.split(r'[.\-]', clean)
    # Convert to integers, default to 0
    return tuple(int(p) if p.isdigit() else 0 for p in parts if p)


def version_gt(v1, v2):
    """Return True if v1 > v2."""
    return parse_version(v1) > parse_version(v2)


def fetch_with_retry(url, max_retries=3, backoff_base=5, timeout=30):
    """Fetch URL with exponential backoff retry."""
    session = requests.Session()
    adapter = HTTPAdapter(pool_connections=2, pool_maxsize=2)
    session.mount("https://", adapter)

    last_error = None
    for attempt in range(max_retries):
        try:
            response = session.get(url, timeout=timeout)
            response.raise_for_status()
            return response
        except requests.RequestException as e:
            last_error = e
            if attempt < max_retries - 1:
                sleep_time = backoff_base * (2 ** attempt)
                log_update(f"Fetch failed (attempt {attempt + 1}), retrying in {sleep_time}s: {e}", "WARNING")
                time.sleep(sleep_time)

    raise NetworkError(f"Failed after {max_retries} attempts: {last_error}")


def download_file(url, dest_path, timeout=300):
    """Download file from URL to destination path."""
    log_update(f"Downloading {url}")

    try:
        response = fetch_with_retry(url, timeout=timeout)
        with open(dest_path, 'wb') as f:
            f.write(response.content)
        log_update(f"Downloaded to {dest_path}")
        return True
    except Exception as e:
        raise NetworkError(f"Download failed: {e}")


def ensure_public_key():
    """
    Ensure the GPG public key is available.
    Downloads from server if missing or is a placeholder.
    """
    need_download = False

    if not os.path.exists(PUBLIC_KEY_PATH):
        log_update("Public key not found, downloading...")
        need_download = True
    else:
        # Check if it's a placeholder
        try:
            with open(PUBLIC_KEY_PATH, 'r') as f:
                content = f.read()
                if 'PLACEHOLDER' in content or 'Replace with actual' in content:
                    log_update("Public key is placeholder, downloading real key...")
                    need_download = True
        except Exception:
            need_download = True

    if need_download:
        try:
            # Ensure directory exists
            key_dir = os.path.dirname(PUBLIC_KEY_PATH)
            if not os.path.exists(key_dir):
                os.makedirs(key_dir, mode=0o755)

            # Download the key
            response = fetch_with_retry(PUBLIC_KEY_URL)
            with open(PUBLIC_KEY_PATH, 'wb') as f:
                f.write(response.content)
            os.chmod(PUBLIC_KEY_PATH, 0o644)
            log_update("Public key downloaded successfully")
            return True
        except Exception as e:
            raise SignatureVerificationError(f"Failed to download public key: {e}")

    return True


def verify_sha256(file_path, expected_hash):
    """Verify SHA256 checksum of file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)

    actual_hash = sha256_hash.hexdigest()
    if actual_hash.lower() != expected_hash.lower():
        raise ChecksumError(f"SHA256 mismatch: expected {expected_hash}, got {actual_hash}")

    log_update("SHA256 checksum verified")
    return True


def verify_signature(pkg_path, sig_path):
    """
    Verify GPG signature using embedded public key.
    Uses a temporary GPG home to avoid polluting system keyring.
    """
    # Ensure we have the public key (download if missing/placeholder)
    ensure_public_key()

    if not os.path.exists(PUBLIC_KEY_PATH):
        raise SignatureVerificationError(f"Public key not found: {PUBLIC_KEY_PATH}")

    if not os.path.exists(sig_path):
        raise SignatureVerificationError(f"Signature file not found: {sig_path}")

    # Create temporary GPG home directory
    with tempfile.TemporaryDirectory() as gpg_home:
        env = os.environ.copy()
        env['GNUPGHOME'] = gpg_home

        # Import the public key
        import_result = subprocess.run(
            ['gpg', '--batch', '--yes', '--import', PUBLIC_KEY_PATH],
            env=env,
            capture_output=True,
            timeout=30
        )

        if import_result.returncode != 0:
            raise SignatureVerificationError(
                f"Failed to import public key: {import_result.stderr.decode()}"
            )

        # Verify the signature
        verify_result = subprocess.run(
            ['gpg', '--batch', '--verify', sig_path, pkg_path],
            env=env,
            capture_output=True,
            timeout=60
        )

        if verify_result.returncode != 0:
            raise SignatureVerificationError(
                f"Signature verification failed: {verify_result.stderr.decode()}"
            )

        log_update("GPG signature verified successfully")
        return True


def check_for_updates(current_version):
    """
    Check if update is available.
    Returns: (needs_update: bool, manifest: dict or None)
    """
    try:
        response = fetch_with_retry(VERSION_URL)
        manifest = response.json()

        latest = manifest.get('current_version', '0.0')

        # Check if newer version available
        if version_gt(latest, current_version):
            log_update(f"Update available: {current_version} -> {latest}")
            return True, manifest

        log_update(f"No update available (current: {current_version}, latest: {latest})", "DEBUG")
        return False, None

    except Exception as e:
        raise NetworkError(f"Update check failed: {e}")


def acquire_lock():
    """Acquire update lock to prevent concurrent updates."""
    if os.path.exists(LOCK_FILE):
        # Check if lock is stale (older than 30 minutes)
        try:
            lock_age = time.time() - os.path.getmtime(LOCK_FILE)
            if lock_age > 1800:  # 30 minutes
                log_update("Removing stale lock file", "WARNING")
                os.remove(LOCK_FILE)
            else:
                raise UpdateError("Another update is in progress")
        except OSError:
            pass

    try:
        with open(LOCK_FILE, 'w') as f:
            f.write(str(os.getpid()))
        return True
    except Exception as e:
        raise UpdateError(f"Failed to acquire lock: {e}")


def release_lock():
    """Release update lock."""
    try:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    except Exception as e:
        log_update(f"Warning: Could not remove lock file: {e}", "WARNING")


def cleanup_download_dir():
    """Clean up the download directory."""
    try:
        if os.path.exists(DOWNLOAD_DIR):
            shutil.rmtree(DOWNLOAD_DIR)
    except Exception as e:
        log_update(f"Warning: Could not clean up download dir: {e}", "WARNING")


def perform_update(manifest):
    """
    Perform the update with verification.
    """
    pkg_url = manifest.get('package_url')
    sig_url = manifest.get('signature_url')
    expected_sha256 = manifest.get('sha256')
    new_version = manifest.get('current_version')

    if not pkg_url or not sig_url:
        raise UpdateError("Invalid manifest: missing package_url or signature_url")

    try:
        # Acquire lock
        acquire_lock()

        # Create clean download directory
        cleanup_download_dir()
        os.makedirs(DOWNLOAD_DIR, mode=0o700)

        pkg_path = os.path.join(DOWNLOAD_DIR, "update.pkg")
        sig_path = os.path.join(DOWNLOAD_DIR, "update.pkg.sig")

        # Download package and signature
        download_file(pkg_url, pkg_path)
        download_file(sig_url, sig_path)

        # Verify signature FIRST (security critical)
        verify_signature(pkg_path, sig_path)

        # Verify SHA256 checksum
        if expected_sha256:
            verify_sha256(pkg_path, expected_sha256)
        else:
            log_update("Warning: No SHA256 checksum in manifest", "WARNING")

        # Install package
        log_update(f"Installing update to version {new_version}...")
        result = subprocess.run(
            ['pkg', 'add', '-f', pkg_path],
            capture_output=True,
            timeout=300  # 5 minute timeout
        )

        if result.returncode != 0:
            raise InstallationError(
                f"Package installation failed: {result.stderr.decode()}"
            )

        log_update(f"Package installed successfully: version {new_version}")

        # Restart service
        log_update("Restarting service...")
        subprocess.run(
            ['/usr/local/etc/rc.d/os-lightscope', 'restart'],
            timeout=60,
            capture_output=True
        )

        log_update(f"Update complete: now running version {new_version}")
        return True

    except SignatureVerificationError:
        # Re-raise signature errors - these are critical security failures
        raise
    except Exception as e:
        log_update(f"Update failed: {e}", "ERROR")
        raise
    finally:
        # Always clean up
        cleanup_download_dir()
        release_lock()


def run_update_loop(config_dict, stop_event=None):
    """
    Main update checking loop.
    Runs every 15 minutes, checks for updates, and applies them if available.

    Args:
        config_dict: Configuration dictionary from daemon
        stop_event: Optional threading.Event to signal shutdown
    """
    log_update("Auto-updater started")

    consecutive_failures = 0
    max_consecutive_failures = 5
    current_version = LS_VERSION

    # Initial delay to let other services start
    time.sleep(30)

    while True:
        if stop_event and stop_event.is_set():
            break

        try:
            # Check if auto-update is still enabled (config might have changed)
            auto_update = config_dict.get('auto_update_enabled', True)

            # Handle string values from config file
            if isinstance(auto_update, str):
                auto_update = auto_update.lower() in ('true', '1', 'yes')

            if not auto_update:
                log_update("Auto-update disabled, skipping check", "DEBUG")
            else:
                needs_update, manifest = check_for_updates(current_version)

                if needs_update:
                    perform_update(manifest)
                    # After successful update, the service will restart
                    # This process will be replaced
                    return

            consecutive_failures = 0

        except SignatureVerificationError as e:
            # Critical security error - do NOT retry frequently
            log_update(f"SECURITY: Signature verification failed: {e}", "CRITICAL")
            consecutive_failures = max_consecutive_failures  # Force extended backoff

        except NetworkError as e:
            consecutive_failures += 1
            log_update(f"Network error (attempt {consecutive_failures}): {e}", "WARNING")

        except UpdateError as e:
            consecutive_failures += 1
            log_update(f"Update error (attempt {consecutive_failures}): {e}", "ERROR")

        except Exception as e:
            consecutive_failures += 1
            log_update(f"Unexpected error (attempt {consecutive_failures}): {e}", "ERROR")

        # Adaptive sleep based on failure count
        if consecutive_failures >= max_consecutive_failures:
            sleep_time = EXTENDED_CHECK_INTERVAL  # 1 hour backoff
            log_update(f"Too many failures, backing off for {sleep_time // 60} minutes", "WARNING")
        elif consecutive_failures > 0:
            sleep_time = UPDATE_CHECK_INTERVAL * 2  # 30 min backoff
        else:
            sleep_time = UPDATE_CHECK_INTERVAL  # Normal 15 min

        # Sleep in small increments to allow for clean shutdown
        for _ in range(int(sleep_time / 10)):
            if stop_event and stop_event.is_set():
                break
            time.sleep(10)

    log_update("Auto-updater stopped")


if __name__ == "__main__":
    # For testing - run standalone
    print("Auto-updater module - run as part of lightscope_daemon.py")
    print(f"Current version: {LS_VERSION}")
    print(f"Version URL: {VERSION_URL}")

    # Quick test of version parsing
    test_versions = ["1.0", "1.1", "opnsense-1.0", "opnsense-1.1"]
    for v in test_versions:
        print(f"  {v} -> {parse_version(v)}")
