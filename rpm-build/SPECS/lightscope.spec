Name:           lightscope
Version: 1.0.2
Release:        1%{?dist}
Summary:        Network security monitoring and honeypot system
License:        Proprietary
URL:            https://thelightscope.com
Source0:        lightscope_core.py
Source1:        lightscope_runner.py
BuildArch:      noarch
# Override OS detection to make it more compatible
%define _build_os linux
%define _target_os linux
Requires:       python3 >= 3.8
Requires:       systemd
Requires:       python3-cryptography

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

# Install runner script
install -m 755 %{SOURCE1} %{buildroot}/opt/lightscope/bin/lightscope-runner.py

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
ExecStart=/opt/lightscope/bin/lightscope-runner.py
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
exec /opt/lightscope/bin/lightscope-runner.py
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
if ! id -u lightscope >&2; then
    useradd --system --home /opt/lightscope --create-home --shell /bin/false lightscope >&2 || true
    echo "✅ System user 'lightscope' created successfully" >&2
else
    echo "✅ System user 'lightscope' already exists" >&2
fi

# Create directory structure and set permissions
echo "🔐 Setting up directory structure and permissions..." >&2
mkdir -p /opt/lightscope/{bin,logs,config,updates} >&2 || true
chown -R lightscope:lightscope /opt/lightscope >&2 || true
chmod 755 /opt/lightscope/bin/lightscope-runner.py >&2 || true
chmod 755 /opt/lightscope/updates >&2 || true
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
    
    chown lightscope:lightscope /opt/lightscope/config/config.ini >&2 || true
    chmod 644 /opt/lightscope/config/config.ini >&2 || true
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
    chown lightscope:lightscope /opt/lightscope/config/config.ini >&2 || true
    chmod 644 /opt/lightscope/config/config.ini >&2 || true
fi

# Update systemd service with database name environment variable
echo "🔧 Configuring systemd service with database name..." >&2
mkdir -p /etc/systemd/system/lightscope.service.d >&2 || true
cat > /etc/systemd/system/lightscope.service.d/database-name.conf << EOF
# LightScope Database Name Override
# This file is automatically generated during installation
[Unit]
Documentation=https://thelightscope.com https://thelightscope.com/tables/$DB_NAME

[Service]
Environment=LIGHTSCOPE_DB_NAME=$DB_NAME
EOF
chmod 644 /etc/systemd/system/lightscope.service.d/database-name.conf >&2 || true
echo "✅ Systemd service configured with database name" >&2

echo "" >&2
echo "📦 INSTALLING SYSTEM DEPENDENCIES" >&2
echo "-----------------------------------" >&2

# Install system dependencies during package installation (when we have root)
echo "🔍 Installing required system packages..." >&2

# Determine package manager
if command -v dnf >&2; then
    PKG_MGR="dnf"
    echo "✅ Using DNF package manager" >&2
elif command -v yum >&2; then
    PKG_MGR="yum"  
    echo "✅ Using YUM package manager" >&2
else
    echo "⚠️  No supported package manager found (dnf/yum)" >&2
    PKG_MGR=""
fi

if [ ! -z "$PKG_MGR" ]; then
    # Install essential packages for LightScope - simplified approach
    PACKAGES="libpcap-devel python3-devel python3-pip pkgconfig gcc python3-cryptography"
    echo "📦 Installing: $PACKAGES" >&2
    
    # Install packages directly without complex timeout handling
    echo "⏱️  Installing packages..." >&2
    if $PKG_MGR install -y $PACKAGES >&2; then
        echo "✅ System packages installed successfully" >&2
    else
        echo "⚠️  Some system packages may have failed to install" >&2
        echo "💡 You may need to install manually later: $PACKAGES" >&2
        echo "💡 Command to run: sudo $PKG_MGR install -y $PACKAGES" >&2
        
        # Try to install critical packages individually
        echo "🔧 Trying to install critical packages individually..." >&2
        for pkg in python3-pip python3-devel python3-cryptography; do
            if $PKG_MGR install -y $pkg >&2; then
                echo "✅ Successfully installed: $pkg" >&2
            else
                echo "⚠️  Failed to install: $pkg" >&2
            fi
        done
    fi
    
    # Verify pip installation
    echo "🔍 Verifying pip installation..." >&2
    if python3 -m pip --version >&2; then
        echo "✅ pip is working correctly" >&2
    else
        echo "⚠️  pip not available via python3 -m pip" >&2
        echo "💡 pip should have been installed with python3-pip package" >&2
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
systemctl daemon-reload >&2 || true
echo "✅ Systemd daemon reloaded" >&2

# Enable service to start on boot
echo "⚙️  Enabling LightScope service for auto-start..." >&2
if systemctl enable lightscope >&2; then
    echo "✅ LightScope service enabled for auto-start" >&2
else
    echo "⚠️  Warning: Could not enable service for auto-start" >&2
fi

# Start the service (it will handle Python dependency installation)
echo "🚀 Starting LightScope service..." >&2
echo "⏱️  This may take a few minutes for first-time Python dependency installation..." >&2
if systemctl start lightscope; then
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
    echo "⚠️  Service start failed" >&2
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
    systemctl stop lightscope >&2 || true
    systemctl disable lightscope >&2 || true
fi

%postun
if [ $1 -eq 0 ]; then
    # Package is being removed
    systemctl daemon-reload >&2 || true
    echo "LightScope has been removed."
    echo "To clean up dependencies, run: pip3 uninstall dpkt psutil requests python-libpcap"
fi

%changelog
* Thu Jun 19 2025 LightScope Team <e@alumni.usc.edu> - 0.0.102-1
- LightScope version 0.0.102
- Network security monitoring and honeypot system
- Automatic dependency installation
- Systemd service integration

