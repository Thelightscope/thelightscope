#!/usr/bin/env python3
"""
Install missing dependencies for LightScope on Windows
Handles Windows-specific packages and pywin32 post-install registration using direct script approach
"""

import subprocess
import sys
import os
import glob

def run_command(cmd, description):
    """Run a command and handle errors gracefully"""
    print(f"→ {' '.join(cmd)}")
    try:
        result = subprocess.check_call(cmd)
        print(f"✅ {description} - SUCCESS")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {description} - FAILED (exit code: {e.returncode})")
        return False
    except Exception as e:
        print(f"❌ {description} - ERROR: {e}")
        return False

def install_packages(packages):
    """Install a list of packages with pip"""
    print("=" * 60)
    print("Installing Python packages...")
    print("=" * 60)
    
    failed_packages = []
    for pkg in packages:
        cmd = [sys.executable, "-m", "pip", "install", "--upgrade", "--force-reinstall", pkg]
        success = run_command(cmd, f"Installing {pkg}")
        if not success:
            failed_packages.append(pkg)
    
    return failed_packages

def register_pywin32():
    """Register pywin32 using the direct script approach"""
    print("\n" + "=" * 60)
    print("Registering pywin32 COM components...")
    print("=" * 60)
    
    # Find the Scripts directory relative to the current Python executable
    scripts_dir = os.path.join(os.path.dirname(sys.executable), "Scripts")
    print(f"Looking for pywin32_postinstall script in: {scripts_dir}")
    
    # Look for the postinstall script (it often has a version suffix)
    candidates = glob.glob(os.path.join(scripts_dir, "pywin32_postinstall*.py"))
    
    if not candidates:
        print(f"❌ Could not find pywin32_postinstall.py in {scripts_dir}")
        print("Available files in Scripts directory:")
        try:
            for f in os.listdir(scripts_dir):
                if 'pywin32' in f.lower():
                    print(f"  - {f}")
        except:
            print("  (could not list directory)")
        
        # Fallback: try the module approach anyway
        print("⚠️  Trying fallback module approach...")
        try:
            cmd = [sys.executable, "-m", "pywin32_postinstall", "-install"]
            success = run_command(cmd, "pywin32_postinstall (module fallback)")
            if success:
                print("✅ pywin32_postinstall complete (via module)")
                return True
        except Exception as e:
            print(f"❌ Module fallback also failed: {e}")
        
        raise RuntimeError("Could not find or run pywin32_postinstall script")
    
    # Use the first candidate script found
    script = candidates[0]
    print(f"Found pywin32_postinstall script: {script}")
    
    # Run the postinstall script directly
    cmd = [sys.executable, script, "-install"]
    success = run_command(cmd, "pywin32_postinstall (direct script)")
    
    if success:
        print("✅ pywin32_postinstall complete")
        return True
    else:
        raise RuntimeError("pywin32_postinstall script execution failed")

def test_imports():
    """Test that pywin32 modules can be imported successfully"""
    print("\n" + "=" * 60)
    print("Testing pywin32 imports...")
    print("=" * 60)
    
    test_modules = ['pywintypes', 'pythoncom', 'win32api', 'win32com.client']
    failed_imports = []
    
    for module in test_modules:
        try:
            __import__(module)
            print(f"✅ {module} - OK")
        except ImportError as e:
            print(f"❌ {module} - FAILED: {e}")
            failed_imports.append(module)
    
    return len(failed_imports) == 0

def main():
    """Main installation function"""
    print("=" * 60)
    print("LightScope Windows Dependencies Installer")
    print("Direct Script Approach for pywin32 Registration")
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
    
    try:
        # Step 1: Install all packages
        failed_packages = install_packages(required_packages)
        
        if failed_packages:
            print(f"\n❌ {len(failed_packages)} packages failed to install:")
            for pkg in failed_packages:
                print(f"   - {pkg}")
            
            # If pywin32 failed, we can't continue
            if "pywin32" in failed_packages:
                print("\n❌ pywin32 installation failed - cannot continue with registration")
                return 1
        
        # Step 2: Register pywin32 (only if pywin32 was installed successfully)
        if "pywin32" not in failed_packages:
            try:
                register_pywin32()
            except Exception as e:
                print(f"❌ pywin32 registration failed: {e}")
                print("⚠️  pywin32 is installed but may not work correctly")
                # Don't return failure here - try the import test first
        
        # Step 3: Test imports to verify everything works
        imports_ok = test_imports()
        
        # Final summary
        print("\n" + "=" * 60)
        print("Installation Summary")
        print("=" * 60)
        
        if failed_packages:
            print(f"⚠️  {len(failed_packages)} packages had installation issues:")
            for pkg in failed_packages:
                print(f"   - {pkg}")
        
        if imports_ok:
            print("✅ All critical imports working correctly!")
            print("✅ pywin32 registration successful")
            print("✅ LightScope should now work correctly on this system")
            return 0
        else:
            print("❌ Some imports still failing")
            print("⚠️  LightScope may not work correctly")
            return 1
            
    except Exception as e:
        print(f"\n❌ Fatal error during installation: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code) 