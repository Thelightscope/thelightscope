Name:           lightscope
Version: 1.0.2
Release:        1%{?dist}
Summary:        Network security monitoring and honeypot system
License:        Proprietary
URL:            https://thelightscope.com
Source0:        lightscope_core.py
BuildArch:      noarch
# Override OS detection to make it more compatible
%define _build_os linux
%define _target_os linux
Requires:       python3 >= 3.8
Requires:       systemd

%description
LightScope is a comprehensive network security monitoring solution that
detects unwanted network traffic and provides honeypot capabilities.
It monitors network interfaces for suspicious activity and reports
findings to the LightScope cloud platform.

%prep
# No prep needed for single file

%build
# No build needed for Python script

%install
rm -rf %{buildroot}

# Create directory structure
mkdir -p %{buildroot}/opt/lightscope/bin
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/usr/share/lightscope
mkdir -p %{buildroot}/usr/bin

# Install main script
install -m 644 %{SOURCE0} %{buildroot}/opt/lightscope/bin/lightscope_core.py

# Install python-libpcap if available
# Note: Temporarily disabled - will be installed via pip
# if [ -d "%{_sourcedir}/python-libpcap" ]; then
#     cp -r %{_sourcedir}/python-libpcap %{buildroot}/opt/lightscope/
# fi

# Create runner script
cat > %{buildroot}/opt/lightscope/bin/lightscope-runner.py << 'RUNNER_EOF'
#!/usr/bin/env python3
"""
LightScope Runner Script for RPM Package
Handles service management and core execution
"""

import os
import sys
import subprocess
import re
import json
import time
import signal
from pathlib import Path

# Service management
def setup_service():
    """Setup systemd service"""
    service_content = '''[Unit]
Description=LightScope Network Security Monitor
After=network.target
Wants=network.target

[Service]
Type=notify
ExecStart=/opt/lightscope/bin/lightscope-runner.py --service
Restart=always
RestartSec=10
User=root
Group=root
WorkingDirectory=/opt/lightscope
Environment=PYTHONPATH=/opt/lightscope

# Watchdog configuration
WatchdogSec=30
NotifyAccess=all

[Install]
WantedBy=multi-user.target
'''
    
    service_path = Path('/usr/lib/systemd/system/lightscope.service')
    try:
        service_path.write_text(service_content)
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        print("✓ Service installed successfully")
    except Exception as e:
        print(f"✗ Service installation failed: {e}")

def install_dependencies():
    """Install Python dependencies with detailed logging"""
    try:
        print("🔧 Starting dependency installation...")
        print("⚠️  Note: System packages (libpcap-devel, etc.) must be installed by root")
        print("ℹ️  This service runs as 'lightscope' user for security")
        
        # Check if system dependencies are available
        print("🔍 Checking system dependencies...")
        missing_deps = check_system_deps()
        if missing_deps:
            print("⚠️  Missing system dependencies:")
            for dep in missing_deps:
                print(f"    - {dep}")
            print("💡 Install with: sudo dnf/yum install " + " ".join(missing_deps))
        
        # Install Python packages (this works as lightscope user)
        print("🐍 Installing Python packages...")
        install_python_packages()
            
        print("✅ Dependencies installation completed!")
        return True
        
    except Exception as e:
        print(f"❌ Dependency installation failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def check_system_deps():
    """Check if system dependencies are available (read-only check)"""
    missing_deps = []
    
    # Check for libpcap development files
    if not os.path.exists('/usr/include/pcap.h') and not os.path.exists('/usr/include/pcap/pcap.h'):
        missing_deps.append('libpcap-devel')
    
    # Check for pkg-config
    if subprocess.run(['which', 'pkg-config'], capture_output=True).returncode != 0:
        missing_deps.append('pkgconfig')
    
    # Check for Python development headers
    if not os.path.exists('/usr/include/python3.8') and not os.path.exists('/usr/include/python3.9') and not os.path.exists('/usr/include/python3.10') and not os.path.exists('/usr/include/python3.11'):
        missing_deps.append('python3-devel')
    
    # Check for GCC compiler
    if subprocess.run(['which', 'gcc'], capture_output=True).returncode != 0:
        missing_deps.append('gcc')
    
    return missing_deps

def install_libpcap_devel():
    """Install libpcap-devel with proper repository configuration"""
    print("🔍 Detecting package manager...")
    
    # Detect package manager
    if subprocess.run(['which', 'dnf'], capture_output=True).returncode == 0:
        pkg_mgr = 'dnf'
        print("✅ Found DNF package manager")
    elif subprocess.run(['which', 'yum'], capture_output=True).returncode == 0:
        pkg_mgr = 'yum' 
        print("✅ Found YUM package manager")
    else:
        print("❌ Neither dnf nor yum found. Cannot install libpcap-devel.")
        return False
    
    # Load OS info from /etc/os-release
    print("🔍 Detecting operating system...")
    try:
        with open('/etc/os-release', 'r') as f:
            os_release = f.read()
        
        os_info = {}
        for line in os_release.split('\n'):
            if '=' in line:
                key, value = line.split('=', 1)
                os_info[key] = value.strip('"')
        
        os_id = os_info.get('ID', 'unknown')
        version_id = os_info.get('VERSION_ID', 'unknown')
        name = os_info.get('NAME', 'unknown')
        
        print(f"✅ Detected: {name} {version_id} (ID: {os_id})")
        
    except Exception as e:
        print(f"❌ Failed to read /etc/os-release: {e}")
        return False
    
    # Enable necessary repos for EL derivatives
    print("🔧 Configuring repositories...")
    major = version_id.split('.')[0]
    
    if os_id in ['rhel', 'centos', 'rocky', 'almalinux']:
        print(f"🔧 Configuring repositories for EL{major}...")
        
        if major == '7':
            print("📦 Enabling Optional repo for EL7...")
            subprocess.run([pkg_mgr, 'install', '-y', 'yum-utils'], capture_output=True)
            subprocess.run(['yum-config-manager', '--enable', 'rhel-7-server-optional-rpms'], capture_output=True)
            
        elif major == '8':
            print("📦 Enabling PowerTools (EL8 CodeReady)...")
            subprocess.run([pkg_mgr, 'install', '-y', 'dnf-plugins-core'], capture_output=True)
            result1 = subprocess.run(['dnf', 'config-manager', '--set-enabled', 'powertools'], capture_output=True)
            if result1.returncode != 0:
                print("🔄 Trying PowerTools with capital P...")
                subprocess.run(['dnf', 'config-manager', '--set-enabled', 'PowerTools'], capture_output=True)
            
        elif major == '9' or major == '10':
            print(f"📦 Enabling CRB (EL{major} CodeReady)...")
            subprocess.run([pkg_mgr, 'install', '-y', 'dnf-plugins-core'], capture_output=True)
            result1 = subprocess.run(['dnf', 'config-manager', '--set-enabled', 'crb'], capture_output=True)
            if result1.returncode != 0:
                print("🔄 Trying CRB with capitals...")
                subprocess.run(['dnf', 'config-manager', '--set-enabled', 'CRB'], capture_output=True)
                
        else:
            print(f"⚠️  Detected EL derivative version {version_id} — attempting without extra repos.")
            
    elif os_id == 'fedora':
        print("✅ Fedora detected; no extra repos needed.")
    else:
        print(f"⚠️  Unrecognized RPM distro '{os_id}'; attempting install anyway.")
    
    # Install libpcap-devel
    print("=" * 60)
    print("📦 Installing libpcap-devel...")
    print(f"🔧 Command: {pkg_mgr} install -y libpcap-devel")
    print("=" * 60)
    
    result = subprocess.run([pkg_mgr, 'install', '-y', 'libpcap-devel'], capture_output=True, text=True)
    
    if result.returncode == 0:
        print("✅ SUCCESS: libpcap-devel installed successfully")
        if result.stdout.strip():
            print(f"📄 Output: {result.stdout.strip()}")
        return True
    else:
        print("❌ ERROR: libpcap-devel installation failed")
        print(f"💥 Error details: {result.stderr.strip()}")
        if result.stdout.strip():
            print(f"📄 Output: {result.stdout.strip()}")
        return False

def install_system_deps():
    """Install other system dependencies with explicit status reporting"""
    print("\n" + "=" * 80)
    print("🔧 INSTALLING SYSTEM DEPENDENCIES")
    print("=" * 80)
    
    # Determine package manager
    if subprocess.run(['which', 'dnf'], capture_output=True).returncode == 0:
        pkg_mgr = 'dnf'
        print(f"✅ Using DNF package manager")
    elif subprocess.run(['which', 'yum'], capture_output=True).returncode == 0:
        pkg_mgr = 'yum'
        print(f"✅ Using YUM package manager")
        # Install EPEL first for older systems
        install_package_with_status(pkg_mgr, 'epel-release', 'EPEL repository')
    else:
        print("❌ ERROR: No supported package manager found")
        return False
    
    # Define the packages we need to install
    packages = [
        ('python3-pip', 'Python package installer'),
        ('python3-devel', 'Python development headers'),  
        ('pkgconfig', 'Package configuration utility'),
        ('gcc', 'GCC compiler')
    ]
    
    success_count = 0
    total_count = len(packages)
    
    for package, description in packages:
        if install_package_with_status(pkg_mgr, package, description):
            success_count += 1
    
    print("\n" + "=" * 80)
    print(f"📊 SYSTEM DEPENDENCIES SUMMARY: {success_count}/{total_count} packages installed successfully")
    if success_count == total_count:
        print("✅ ALL system dependencies installed successfully!")
    else:
        print(f"⚠️  {total_count - success_count} packages failed to install")
    print("=" * 80)
    
    return success_count > 0  # Return True if at least some packages installed

def install_package_with_status(pkg_mgr, package, description):
    """Install a single package with detailed status reporting"""
    print(f"\n📦 Installing {package} ({description})...")
    print(f"🔧 Command: {pkg_mgr} install -y {package}")
    print("-" * 60)
    
    result = subprocess.run([pkg_mgr, 'install', '-y', package], capture_output=True, text=True)
    
    if result.returncode == 0:
        print(f"✅ SUCCESS: {package} installed successfully")
        if result.stdout.strip():
            # Show relevant output lines (skip empty lines and common noise)
            output_lines = [line for line in result.stdout.split('\n') if line.strip() and 'metadata' not in line.lower()]
            if output_lines:
                print(f"📄 Output: {output_lines[-1]}")  # Show the last relevant line
        return True
    else:
        print(f"❌ ERROR: {package} installation failed")
        print(f"💥 Error details: {result.stderr.strip()}")
        if result.stdout.strip():
            print(f"📄 Output: {result.stdout.strip()}")
        return False

def install_python_packages():
    """Install Python packages with explicit status reporting"""
    print("\n" + "=" * 80)
    print("🐍 INSTALLING PYTHON PACKAGES")
    print("=" * 80)
    
    # Basic Python packages
    basic_packages = ['dpkt', 'psutil', 'requests']
    success_count = 0
    
    for package in basic_packages:
        if install_pip_package_with_status(package):
            success_count += 1
    
    print(f"\n📊 Basic packages: {success_count}/{len(basic_packages)} installed successfully")
    
    # LibPCAP Python bindings - try multiple approaches
    print("\n" + "-" * 80)
    print("📦 INSTALLING LIBPCAP PYTHON BINDINGS")
    print("-" * 80)
    
    libpcap_installed = False
    
    # Strategy 1: pylibpcap (provides pylibpcap.base)
    print("\n🎯 Strategy 1: Installing pylibpcap (primary choice)...")
    if install_pip_package_with_status('pylibpcap'):
        libpcap_installed = True
        print("✅ SUCCESS: pylibpcap provides the required pylibpcap.base module")
    else:
        # Strategy 2: python-libpcap (fallback)
        print("\n🎯 Strategy 2: Installing python-libpcap (fallback)...")
        if install_pip_package_with_status('python-libpcap'):
            libpcap_installed = True
            print("✅ SUCCESS: python-libpcap installed as fallback")
        else:
            # Strategy 3: Try with --no-cache-dir
            print("\n🎯 Strategy 3: Trying with --no-cache-dir flag...")
            if install_pip_package_with_status('pylibpcap', extra_flags=['--no-cache-dir']):
                libpcap_installed = True
                print("✅ SUCCESS: pylibpcap installed with --no-cache-dir")
    
    print("\n" + "=" * 80)
    if libpcap_installed:
        print("✅ PYTHON PACKAGES: All critical packages installed successfully!")
        print("🎯 LightScope should have full packet capture capabilities")
    else:
        print("⚠️  PYTHON PACKAGES: Basic packages installed, but libpcap bindings failed")
        print("💡 This may be due to missing system dependencies (libpcap-devel, pkgconfig)")
        print("🔧 LightScope may have limited packet capture functionality")
    print("=" * 80)

def install_pip_package_with_status(package, extra_flags=None):
    """Install a single pip package with detailed status reporting"""
    flags = extra_flags or []
    cmd = [sys.executable, '-m', 'pip', 'install'] + flags + [package]
    cmd_str = ' '.join(cmd)
    
    print(f"\n📦 Installing Python package: {package}")
    print(f"🔧 Command: {cmd_str}")
    print("-" * 60)
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print(f"✅ SUCCESS: {package} installed successfully")
        # Show installation confirmation from pip output
        if 'Successfully installed' in result.stdout:
            success_line = [line for line in result.stdout.split('\n') if 'Successfully installed' in line]
            if success_line:
                print(f"📄 {success_line[0].strip()}")
        return True
    else:
        print(f"❌ ERROR: {package} installation failed")
        # Show the most relevant error information
        if result.stderr.strip():
            error_lines = result.stderr.strip().split('\n')
            # Show the last few error lines (usually most informative)
            for line in error_lines[-3:]:
                if line.strip():
                    print(f"💥 {line.strip()}")
        return False

def get_version():
    """Extract version from lightscope_core.py"""
    try:
        core_path = Path('/opt/lightscope/bin/lightscope_core.py')
        content = core_path.read_text()
        match = re.search(r'ls_version\s*=\s*["\']([^"\']+)["\']', content)
        if match:
            return match.group(1)
    except Exception as e:
        print(f"Error extracting version: {e}")
    return "unknown"

def run_core():
    """Run the main lightscope core"""
    try:
        core_path = Path('/opt/lightscope/bin/lightscope_core.py')
        if not core_path.exists():
            print(f"✗ Core file not found: {core_path}")
            return False
            
        # Set up environment
        env = os.environ.copy()
        env['PYTHONPATH'] = '/opt/lightscope'
        
        # Run the core
        subprocess.run([sys.executable, str(core_path)], env=env, check=True)
        return True
        
    except KeyboardInterrupt:
        print("✓ LightScope stopped by user")
        return True
    except Exception as e:
        print(f"✗ Core execution failed: {e}")
        return False

def run_core_with_retry():
    """Run lightscope core with retry logic and exponential backoff"""
    attempt = 0
    max_delay = 300  # Maximum delay of 5 minutes (300 seconds)
    base_delay = 5   # Start with 5 seconds
    
    while True:
        attempt += 1
        try:
            print(f"🚀 Starting LightScope core (attempt {attempt})...")
            
            core_path = Path('/opt/lightscope/bin/lightscope_core.py')
            if not core_path.exists():
                print(f"✗ Core file not found: {core_path}")
                raise FileNotFoundError(f"Core file not found: {core_path}")
                
            # Set up environment
            env = os.environ.copy()
            env['PYTHONPATH'] = '/opt/lightscope'
            
            # Run the core - this will block until it exits
            result = subprocess.run([sys.executable, str(core_path)], env=env)
            
            # If we get here, the process exited
            if result.returncode == 0:
                print("✓ LightScope core exited normally")
                # Normal exit - reset attempt counter for next restart
                attempt = 0
            else:
                print(f"✗ LightScope core exited with code {result.returncode}")
                raise subprocess.CalledProcessError(result.returncode, "lightscope_core.py")
                
        except KeyboardInterrupt:
            print("✓ LightScope stopped by user (Ctrl+C)")
            break
        except SystemExit:
            print("✓ LightScope stopped by system exit")
            break
        except Exception as e:
            print(f"✗ LightScope core failed: {e}")
            
            # Calculate delay with exponential backoff (capped at max_delay)
            delay = min(base_delay * (2 ** (attempt - 1)), max_delay)
            
            print(f"⏱️  Retrying in {delay} seconds (attempt {attempt}, max delay: {max_delay}s)...")
            
            # Wait before retrying, but allow interruption
            try:
                time.sleep(delay)
            except KeyboardInterrupt:
                print("✓ LightScope retry interrupted by user")
                break
            
            # Continue the while loop to retry
            continue

def main():
    if len(sys.argv) > 1:
        if sys.argv[1] == '--install':
            print("Installing LightScope dependencies...")
            if install_dependencies():
                setup_service()
                print("✓ Installation complete!")
                print("  Start service: sudo systemctl start lightscope")
                print("  Enable service: sudo systemctl enable lightscope")
            else:
                sys.exit(1)
                
        elif sys.argv[1] == '--service':
            # Running as systemd service
            print(f"🚀 Starting LightScope v{get_version()} service...")
            
            # Check if dependencies are installed, install if needed
            print("🔍 Checking dependencies...")
            try:
                import dpkt, psutil, requests
                print("✅ Basic dependencies available")
            except ImportError as e:
                print(f"⚠️  Missing dependencies: {e}")
                print("🔧 Installing dependencies automatically...")
                if install_dependencies():
                    print("✅ Dependencies installed successfully, restarting service...")
                    # Restart the service to pick up new dependencies
                    subprocess.run(['systemctl', 'restart', 'lightscope'], capture_output=True)
                    return
                else:
                    print("❌ Dependency installation failed, starting with limited functionality...")
            
            # Set up systemd watchdog
            print("🔧 Setting up systemd watchdog...")
            try:
                import systemd.daemon
                systemd.daemon.notify('READY=1')
                print("✅ Systemd ready notification sent")
                
                # Set up continuous watchdog pinging in a separate thread
                import threading
                import time
                
                def watchdog_thread():
                    while True:
                        try:
                            systemd.daemon.notify('WATCHDOG=1')
                            time.sleep(15)  # Ping every 15 seconds (well under 60s timeout)
                        except Exception as e:
                            print(f"⚠️  Watchdog ping failed: {e}")
                            break
                
                # Start watchdog thread as daemon so it doesn't prevent shutdown
                watchdog = threading.Thread(target=watchdog_thread, daemon=True)
                watchdog.start()
                print("✅ Systemd watchdog thread started (pinging every 15s)")
                
            except ImportError:
                print("⚠️  Warning: systemd python module not available - no watchdog")
            
            print("🎯 Starting LightScope core with retry logic...")
            run_core_with_retry()
            
        elif sys.argv[1] == '--version':
            print(f"LightScope v{get_version()}")
            
        else:
            print("Usage: lightscope-runner.py [--install|--service|--version]")
            sys.exit(1)
    else:
        # Interactive mode
        print(f"LightScope v{get_version()}")
        print("Run with --install to set up dependencies and service")
        run_core()

if __name__ == '__main__':
    main()
RUNNER_EOF

chmod +x %{buildroot}/opt/lightscope/bin/lightscope-runner.py

# Create systemd service file
cat > %{buildroot}/usr/lib/systemd/system/lightscope.service << 'SERVICE_EOF'
[Unit]
Description=LightScope Network Security Monitor
Documentation=https://thelightscope.com/docs
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=notify
User=lightscope
Group=lightscope
ExecStart=/opt/lightscope/bin/lightscope-runner.py --service
ExecReload=/bin/kill -HUP $MAINPID
WorkingDirectory=/opt/lightscope
Environment=PYTHONPATH=/opt/lightscope
Environment=LIGHTSCOPE_CONFIG=/opt/lightscope/config/config.ini

# Network capabilities for packet capture and port binding
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

# Restart configuration
Restart=always
RestartSec=10
StartLimitInterval=300
StartLimitBurst=5

# Watchdog configuration
WatchdogSec=30
NotifyAccess=all

# Security settings
NoNewPrivileges=false
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/lightscope
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lightscope

# Process limits
LimitNOFILE=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Create config example
cat > %{buildroot}/usr/share/lightscope/config.ini.example << 'CONFIG_EOF'
[Settings]
# Database name for storing LightScope data (auto-generated during installation)
database = 

# Randomization key for IP address anonymization (auto-generated if empty)
randomization_key = 

# Enable automatic SSH/Telnet honeypot port forwarding (yes/no)
self_telnet_and_ssh_honeypot_ports_to_forward = no

# Enable automatic updates (yes/no)
autoupdate = yes

# Update check interval in hours (minimum 1 hour)
update_check_interval = 24

# Enable debug logging (yes/no)
debug_logging = no

# Custom interface to monitor (leave empty for auto-detection)
interface = 

# Maximum number of concurrent honeypot ports
max_honeypot_ports = 10

# Honeypot rotation interval in hours
honeypot_rotation_interval = 4 
CONFIG_EOF

# Create command line wrapper
cat > %{buildroot}/usr/bin/lightscope << 'WRAPPER_EOF'
#!/bin/bash
exec /opt/lightscope/bin/lightscope-runner.py ""
WRAPPER_EOF

chmod +x %{buildroot}/usr/bin/lightscope

%files
%defattr(-,root,root,-)
/opt/lightscope/
/usr/lib/systemd/system/lightscope.service
/usr/share/lightscope/config.ini.example
/usr/bin/lightscope

%post
# Force output to be visible during RPM installation
exec 1>&2

echo ""
echo "🚀 LIGHTSCOPE POST-INSTALL SCRIPT STARTING" >&2
echo "============================================" >&2
echo "📦 LightScope v%{version} files installed successfully!" >&2
echo "" >&2

# Create lightscope user if it doesn't exist
echo "👤 Creating lightscope system user..." >&2
if ! id -u lightscope >/dev/null 2>&1; then
    useradd --system --home /opt/lightscope --create-home --shell /bin/false lightscope 2>/dev/null || true
    echo "✅ System user 'lightscope' created successfully" >&2
else
    echo "✅ System user 'lightscope' already exists" >&2
fi

# Create directory structure and set permissions
echo "🔐 Setting up directory structure and permissions..." >&2
mkdir -p /opt/lightscope/{bin,logs,config,updates} 2>/dev/null || true
chown -R lightscope:lightscope /opt/lightscope 2>/dev/null || true
chmod 755 /opt/lightscope/bin/lightscope-runner.py 2>/dev/null || true
chmod 755 /opt/lightscope/updates 2>/dev/null || true
echo "✅ Directory structure and file ownership configured" >&2

# Generate unique database name during installation
echo "🏷️  Generating unique database name..." >&2
TODAY=$(date +%Y%m%d)
RAND_PART=$(cat /dev/urandom | tr -dc 'a-z' | head -c 47)
DB_NAME="${TODAY}_${RAND_PART}"
echo "✅ Generated database name: $DB_NAME" >&2

# Create configuration file with pre-populated database name
if [ ! -f "/opt/lightscope/config/config.ini" ]; then
    echo "🔧 Creating configuration file with database name: $DB_NAME" >&2
    
    # Create config file with proper database name directly
    cat > /opt/lightscope/config/config.ini << EOF
[Settings]
# Database name for storing LightScope data (auto-generated during installation)
database = $DB_NAME

# Randomization key for IP address anonymization (auto-generated if empty)
randomization_key = 

# Enable automatic SSH/Telnet honeypot port forwarding (yes/no)
self_telnet_and_ssh_honeypot_ports_to_forward = no

# Enable automatic updates (yes/no)
autoupdate = yes

# Update check interval in hours (minimum 1 hour)
update_check_interval = 24

# Enable debug logging (yes/no)
debug_logging = no

# Custom interface to monitor (leave empty for auto-detection)
interface = 

# Maximum number of concurrent honeypot ports
max_honeypot_ports = 10

# Honeypot rotation interval in hours
honeypot_rotation_interval = 4 
EOF
    
    chown lightscope:lightscope /opt/lightscope/config/config.ini 2>/dev/null || true
    chmod 644 /opt/lightscope/config/config.ini 2>/dev/null || true
    echo "✅ Configuration file created with database name: $DB_NAME" >&2
else
    echo "⚙️  Configuration file already exists, updating database name..." >&2
    # Update existing config file with the generated database name
    # Use a more robust approach with Python to ensure correct parsing
    python3 << EOF
import configparser
import os

config_file = "/opt/lightscope/config/config.ini"
db_name = "$DB_NAME"

try:
    config = configparser.ConfigParser()
    config.read(config_file)
    
    if not config.has_section('Settings'):
        config.add_section('Settings')
    
    # Set the database name
    config.set('Settings', 'database', db_name)
    
    # Write back to file
    with open(config_file, 'w') as f:
        config.write(f)
    
    print(f"Updated existing config file with database name: {db_name}")
except Exception as e:
    print(f"Error updating config file: {e}")
    # Fallback to sed approach
    os.system(f"sed -i 's/^database = .*/database = {db_name}/' {config_file}")
EOF
    chown lightscope:lightscope /opt/lightscope/config/config.ini 2>/dev/null || true
    chmod 644 /opt/lightscope/config/config.ini 2>/dev/null || true
fi

# Update systemd service with database name environment variable
echo "🔧 Configuring systemd service with database name..." >&2
mkdir -p /etc/systemd/system/lightscope.service.d 2>/dev/null || true
cat > /etc/systemd/system/lightscope.service.d/database-name.conf << EOF
# LightScope Database Name Override
# This file is automatically generated during installation
[Unit]
Documentation=https://thelightscope.com https://thelightscope.com/tables/$DB_NAME

[Service]
Environment=LIGHTSCOPE_DB_NAME=$DB_NAME
EOF
chmod 644 /etc/systemd/system/lightscope.service.d/database-name.conf 2>/dev/null || true
echo "✅ Systemd service configured with database name" >&2

echo "" >&2
echo "📦 INSTALLING SYSTEM DEPENDENCIES" >&2
echo "-----------------------------------" >&2

# Install system dependencies during package installation (when we have root)
echo "🔍 Installing required system packages..." >&2

# Determine package manager
if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    echo "✅ Using DNF package manager" >&2
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"  
    echo "✅ Using YUM package manager" >&2
else
    echo "⚠️  No supported package manager found (dnf/yum)" >&2
    PKG_MGR=""
fi

if [ ! -z "$PKG_MGR" ]; then
    # Install essential packages for LightScope
    PACKAGES="libpcap-devel python3-devel python3-pip pkgconfig gcc"
    echo "📦 Installing: $PACKAGES" >&2
    
    # Try to install packages with timeout and better error handling  
    echo "⏱️  This may take a few minutes..." >&2
    if timeout 300 $PKG_MGR install -y $PACKAGES; then
        echo "✅ System packages installed successfully" >&2
    else
        echo "⚠️  Some system packages may have failed to install or timed out" >&2
        echo "💡 You may need to install manually later: $PACKAGES" >&2
        echo "💡 Command to run: sudo $PKG_MGR install -y $PACKAGES" >&2
    fi
else
    echo "⚠️  Cannot install system packages automatically" >&2
    echo "💡 Please install manually: libpcap-devel python3-devel python3-pip pkgconfig gcc" >&2
fi

echo "" >&2
echo "🔧 CONFIGURING SYSTEMD SERVICE" >&2
echo "------------------------------" >&2

# Reload systemd to recognize the service
echo "🔄 Reloading systemd daemon..." >&2
systemctl daemon-reload 2>/dev/null || true
echo "✅ Systemd daemon reloaded" >&2

# Enable service to start on boot
echo "⚙️  Enabling LightScope service for auto-start..." >&2
if systemctl enable lightscope 2>/dev/null; then
    echo "✅ LightScope service enabled for auto-start" >&2
else
    echo "⚠️  Warning: Could not enable service for auto-start" >&2
fi

# Start the service (it will handle Python dependency installation)
echo "🚀 Starting LightScope service..." >&2
echo "⏱️  This may take a few minutes for first-time Python dependency installation..." >&2
if timeout 180 systemctl start lightscope; then
    echo "✅ LightScope service started successfully" >&2
    echo "📋 Service is running and monitoring network traffic" >&2
    
    # Give the service a moment to initialize
    sleep 3
    
    # Check if service is actually running
    if systemctl is-active --quiet lightscope; then
        echo "✅ Service is running properly" >&2
    else
        echo "⚠️  Service may be initializing - check with: systemctl status lightscope" >&2
    fi
else
    echo "⚠️  Service start timed out or failed" >&2
    echo "💡 You can start it manually later with: sudo systemctl start lightscope" >&2
    echo "💡 Monitor startup with: sudo journalctl -fu lightscope" >&2
fi

echo "" >&2
echo "============================================" >&2
echo "✅ LIGHTSCOPE INSTALLATION COMPLETED!" >&2
echo "============================================" >&2
echo "" >&2
echo "📊 DASHBOARD ACCESS INFORMATION:" >&2
echo "🏷️  Database Name: $DB_NAME" >&2
echo "🌐 Dashboard URL: https://lightscope.isi.edu/tables/$DB_NAME" >&2
echo "📋 Web Interface: https://lightscope.isi.edu/tables" >&2
echo "" >&2
echo "💡 To find your database name later:" >&2
echo "   sudo systemctl status lightscope" >&2
echo "   (Look for LIGHTSCOPE_DB_NAME in the environment)" >&2
echo "" >&2
echo "🔒 SECURITY FEATURES ENABLED:" >&2
echo "   👤 Service runs as unprivileged 'lightscope' system user (not root)" >&2
echo "   🛡️  Uses Linux capabilities for network access only" >&2
echo "   🔒 Filesystem protections and security restrictions active" >&2
echo "" >&2
echo "📊 MONITORING COMMANDS:" >&2
echo "   systemctl status lightscope    # Check service status" >&2
echo "   journalctl -fu lightscope      # View live logs" >&2
echo "   journalctl -u lightscope       # View all logs" >&2
echo "" >&2
echo "📁 Configuration: /opt/lightscope/config/config.ini" >&2
echo "============================================" >&2

# Add a small delay to ensure output is visible
sleep 1

%preun
if [ $1 -eq 0 ]; then
    # Package is being removed
    systemctl stop lightscope 2>/dev/null || true
    systemctl disable lightscope 2>/dev/null || true
fi

%postun
if [ $1 -eq 0 ]; then
    # Package is being removed
    systemctl daemon-reload 2>/dev/null || true
    echo "LightScope has been removed."
    echo "To clean up dependencies, run: pip3 uninstall dpkt psutil requests python-libpcap"
fi

%changelog
* Thu Jun 19 2025 LightScope Team <e@alumni.usc.edu> - 0.0.102-1
- LightScope version 0.0.102
- Network security monitoring and honeypot system
- Automatic dependency installation
- Systemd service integration

