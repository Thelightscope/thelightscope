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

# Build requirements
BuildRequires:  python3-devel
BuildRequires:  pkgconfig
BuildRequires:  gcc
BuildRequires:  openssl-devel
BuildRequires:  libffi-devel
BuildRequires:  rust


# Runtime requirements
Requires:       python3 >= 3.8
Requires:       systemd
Requires:       python3-cryptography
Requires:       python3-cffi
Requires:       python3-pip
Requires:       python3-devel
Requires:       gcc

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
ExecStart=/opt/lightscope/venv/bin/python /opt/lightscope/bin/lightscope-runner.py
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
# … your user‐add, dir‐setup, config‐gen, etc. …

# 1) Create the virtual environment
print_status "🐍 Creating Python venv at /opt/lightscope/venv…"
python3 -m venv /opt/lightscope/venv || echo "⚠️  Could not create venv"

# 2) Install your modules into it
print_status "📦 Installing Python packages into venv…"
/opt/lightscope/venv/bin/pip install --upgrade pip \
    cryptography \
    cffi \
    dpkt \
    psutil \
    requests \
    python-libpcap \
    || echo "⚠️  pip install failed in venv"

# 3) Fix ownership so the lightscope user can run it
print_status "🔐 Chowning venv to lightscope:lightscope…"
chown -R lightscope:lightscope /opt/lightscope/venv

# 4) (Re)configure your systemd unit to use the venv’s python
print_status "🔧 Pointing service at venv Python…"
mkdir -p /etc/systemd/system/lightscope.service.d
cat > /etc/systemd/system/lightscope.service.d/venv.conf <<-'EOF'
[Service]
# override ExecStart to use our venv
ExecStart=
ExecStart=/opt/lightscope/venv/bin/python /opt/lightscope/bin/lightscope-runner.py
EOF

# … reload, enable, start as you already have it …




exec 1>&2
set -x  # Enable verbose debugging

echo ""
echo "🚀 LIGHTSCOPE POST-INSTALL SCRIPT STARTING" 
echo "============================================" 
echo "📦 LightScope v%{version} files installed successfully!" 
echo "⏰ Starting at: $(date)" 
echo "" 

# Function to print with timestamp and immediate flush
print_status() {
    echo "⏰ $(date) - $1" 
    sync  # Force filesystem sync
}

# Create lightscope user if it doesn't exist
print_status "👤 Creating lightscope system user..."
if ! id -u lightscope; then
    print_status "Creating new system user..."
    useradd --system --home /opt/lightscope --create-home --shell /bin/false lightscope || true
    print_status "✅ System user 'lightscope' created successfully"
else
    print_status "✅ System user 'lightscope' already exists"
fi

# Create directory structure and set permissions
print_status "🔐 Setting up directory structure and permissions..."
mkdir -p /opt/lightscope/{bin,logs,config,updates} || true
chown -R lightscope:lightscope /opt/lightscope || true
chmod 755 /opt/lightscope/bin/lightscope-runner.py || true
chmod 755 /opt/lightscope/updates || true
print_status "✅ Directory structure and file ownership configured"

# Generate unique database name during installation
print_status "🏷️  Generating unique database name..."
TODAY=$(date +%Y%m%d)
RAND_PART=$(cat /dev/urandom | tr -dc 'a-z' | head -c 47)
DB_NAME="${TODAY}_${RAND_PART}"
print_status "✅ Generated database name: $DB_NAME"

# Create configuration file with pre-populated database name
if [ ! -f "/opt/lightscope/config/config.ini" ]; then
    print_status "🔧 Creating configuration file with database name: $DB_NAME"
    
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
    
    chown lightscope:lightscope /opt/lightscope/config/config.ini || true
    chmod 644 /opt/lightscope/config/config.ini || true
    print_status "✅ Configuration file created with database name: $DB_NAME"
else
    print_status "⚙️  Configuration file already exists, updating database name..."
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
    chown lightscope:lightscope /opt/lightscope/config/config.ini || true
    chmod 644 /opt/lightscope/config/config.ini || true
fi

# Update systemd service with database name environment variable
print_status "🔧 Configuring systemd service with database name..."
mkdir -p /etc/systemd/system/lightscope.service.d || true
cat > /etc/systemd/system/lightscope.service.d/database-name.conf << EOF
# LightScope Database Name Override
# This file is automatically generated during installation
[Unit]
Documentation=https://thelightscope.com https://thelightscope.com/tables/$DB_NAME

[Service]
Environment=LIGHTSCOPE_DB_NAME=$DB_NAME
EOF
chmod 644 /etc/systemd/system/lightscope.service.d/database-name.conf || true
print_status "✅ Systemd service configured with database name"

# Dependencies are now handled by RPM Requires: declarations
# No need to install packages manually in %post

# Verify that required dependencies are available
print_status "🔍 Verifying dependencies installed by RPM..."
if python3 -c "import cryptography"; then
    print_status "✅ python3-cryptography is available"
else
    print_status "⚠️  python3-cryptography not available"
fi

if python3 -m pip --version >/dev/null 2>&1; then
    print_status "✅ pip is available"
else
    print_status "⚠️  pip not available - trying ensurepip..."
    if python3 -m ensurepip --upgrade >/dev/null 2>&1; then
        print_status "✅ pip enabled via ensurepip"
    else
        print_status "⚠️  pip still not available"
    fi
fi

echo "" 
print_status "🔧 CONFIGURING SYSTEMD SERVICE"
echo "------------------------------" 

# Reload systemd to recognize the service
print_status "🔄 Reloading systemd daemon..."
systemctl daemon-reload || true
print_status "✅ Systemd daemon reloaded"

# Enable service to start on boot
print_status "⚙️  Enabling LightScope service for auto-start..."
if systemctl enable lightscope; then
    print_status "✅ LightScope service enabled for auto-start"
else
    print_status "⚠️  Warning: Could not enable service for auto-start"
fi

# Start the service with SHORT timeout (no package installation needed)
print_status "🚀 Starting LightScope service..."
print_status "⏱️  Using 30 second timeout for service start..."
if timeout 30 systemctl start lightscope; then
    print_status "✅ LightScope service started successfully"
    print_status "📋 Service is running and monitoring network traffic"
    
    # Give the service a moment to initialize
    print_status "Waiting 3 seconds for service to initialize..."
    sleep 3
    
    # Check if service is actually running
    if systemctl is-active --quiet lightscope; then
        print_status "✅ Service is running properly"
    else
        print_status "⚠️  Service may be initializing - check with: systemctl status lightscope"
    fi
else
    print_status "⚠️  Service start failed or timed out (30 seconds)"
    print_status "💡 You can start it manually later with: sudo systemctl start lightscope"
    print_status "💡 Monitor startup with: sudo journalctl -fu lightscope"
fi

echo "" 
echo "============================================" 
print_status "✅ LIGHTSCOPE INSTALLATION COMPLETED!"
echo "============================================" 
echo "" 
print_status "📊 DASHBOARD ACCESS INFORMATION:"
echo "🏷️  Database Name: $DB_NAME" 
echo "🌐 Dashboard URL: https://lightscope.isi.edu/tables/$DB_NAME" 
echo "📋 Web Interface: https://lightscope.isi.edu/tables" 
echo "" 
echo "💡 To find your database name later:" 
echo "   sudo systemctl status lightscope" 
echo "   (Look for LIGHTSCOPE_DB_NAME in the environment)" 
echo "" 
echo "🔒 SECURITY FEATURES ENABLED:" 
echo "   👤 Service runs as unprivileged 'lightscope' system user (not root)" 
echo "   🛡️  Uses Linux capabilities for network access only" 
echo "   🔒 Filesystem protections and security restrictions active" 
echo "" 
echo "📊 MONITORING COMMANDS:" 
echo "   systemctl status lightscope    # Check service status" 
echo "   journalctl -fu lightscope      # View live logs" 
echo "   journalctl -u lightscope       # View all logs" 
echo "" 
echo "📁 Configuration: /opt/lightscope/config/config.ini" 
echo "============================================" 

# Add completion timestamp
print_status "🎉 Installation completed successfully!"

# Add a small delay to ensure output is visible
sleep 1

%preun
if [ $1 -eq 0 ]; then
    # Package is being removed
    systemctl stop lightscope || true
    systemctl disable lightscope || true
fi

%postun
if [ $1 -eq 0 ]; then
    # Package is being removed
    systemctl daemon-reload || true
    echo "LightScope has been removed."
    echo "To clean up dependencies, run: pip3 uninstall dpkt psutil requests python-libpcap"
fi

%changelog
* Thu Jun 19 2025 LightScope Team <e@alumni.usc.edu> - 0.0.102-1
- LightScope version 0.0.102
- Network security monitoring and honeypot system
- Automatic dependency installation
- Systemd service integration

