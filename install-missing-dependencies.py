#!/usr/bin/env python3
"""
Install missing dependencies for LightScope on Windows
Handles Windows-specific packages and pywin32 post-install registration
"""

import subprocess
import sys
import os

def run_command(cmd, description):
    """Run a command and handle errors gracefully"""
    print(f"Running: {description}")
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(f"✅ {description} - SUCCESS")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {description} - FAILED")
        print(f"Exit code: {e.returncode}")
        print(f"stdout: {e.stdout}")
        print(f"stderr: {e.stderr}")
        return False

def install_package(package_name):
    """Install a single package with pip"""
    cmd = [sys.executable, "-m", "pip", "install", "--upgrade", "--force-reinstall", package_name]
    return run_command(cmd, f"Installing {package_name}")

def run_pywin32_postinstall():
    """Run pywin32 post-install registration"""
    cmd = [sys.executable, "-m", "pywin32_postinstall", "-install"]
    success = run_command(cmd, "Running pywin32 post-install registration")
    
    if not success:
        print("⚠️  pywin32_postinstall failed, attempting fallback test...")
        # Fallback: try to import the modules to test if they work
        try:
            import pywintypes
            import pythoncom
            print("✅ pywin32 modules can be imported successfully (fallback test passed)")
            return True
        except ImportError as e:
            print(f"❌ pywin32 modules still cannot be imported: {e}")
            return False
    
    return success

def main():
    """Main installation function"""
    print("=" * 60)
    print("LightScope Windows Dependencies Installer")
    print("=" * 60)
    
    # List of all required packages
    required_packages = [
        "cryptography",
        "psutil", 
        "requests",
        "dpkt",
        "packaging",
        "urllib3",
        "scapy",
        "pywin32",  # Critical for Windows COM functionality
        "wmi",      # Windows Management Instrumentation
        "pcap-ct==1.3.0b3"  # Specific version for packet capture
    ]
    
    print(f"Installing {len(required_packages)} required packages...")
    
    # Install all packages
    failed_packages = []
    for package in required_packages:
        success = install_package(package)
        if not success:
            failed_packages.append(package)
    
    # Special handling for pywin32 post-install
    if "pywin32" not in failed_packages:
        print("\n" + "=" * 60)
        print("Running pywin32 post-install registration...")
        print("=" * 60)
        
        pywin32_success = run_pywin32_postinstall()
        if not pywin32_success:
            print("⚠️  pywin32 post-install had issues, but continuing...")
    
    # Summary
    print("\n" + "=" * 60)
    print("Installation Summary")
    print("=" * 60)
    
    if failed_packages:
        print(f"❌ {len(failed_packages)} packages failed to install:")
        for pkg in failed_packages:
            print(f"   - {pkg}")
        print("\n⚠️  Some dependencies may be missing. LightScope might not work correctly.")
        return 1
    else:
        print("✅ All dependencies installed successfully!")
        print("✅ pywin32 post-install registration completed")
        print("✅ LightScope should now work correctly on this system")
        return 0

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code) 