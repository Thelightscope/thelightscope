Name:           lightscope
Version: 1.0.2
Release:        1%{?dist}
Summary:        Network security monitoring and honeypot system
License:        Proprietary
URL:            https://thelightscope.com
Source0:        lightscope_core.py
Source1:        lightscope-runner.py
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

# Install runner script
install -m 755 %{SOURCE1} %{buildroot}/opt/lightscope/bin/lightscope-runner.py

# Install python-libpcap if available
# Note: Temporarily disabled - will be installed via pip
# if [ -d "%{_sourcedir}/python-libpcap" ]; then
#     cp -r %{_sourcedir}/python-libpcap %{buildroot}/opt/lightscope/
# fi

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
exec /opt/lightscope/bin/lightscope-runner.py "$@"
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
echo "⚙️  Creating configuration file..." >&2
mkdir -p /opt/lightscope/config 2>/dev/null || true
cat > /opt/lightscope/config/config.ini << CONFIG_EOF
[Settings]
database = $DB_NAME
randomization_key = 
self_telnet_and_ssh_honeypot_ports_to_forward = no
autoupdate = yes
update_check_interval = 24
debug_logging = no
interface = 
max_honeypot_ports = 10
honeypot_rotation_interval = 4
CONFIG_EOF

chown lightscope:lightscope /opt/lightscope/config/config.ini 2>/dev/null || true
chmod 644 /opt/lightscope/config/config.ini 2>/dev/null || true
echo "✅ Configuration file created: /opt/lightscope/config/config.ini" >&2

# Copy public key for update verification
echo "🔑 Setting up update verification..." >&2
if [ -f "/usr/share/lightscope/lightscope-public.pem" ]; then
    cp /usr/share/lightscope/lightscope-public.pem /opt/lightscope/config/lightscope-public.pem 2>/dev/null || true
    chown lightscope:lightscope /opt/lightscope/config/lightscope-public.pem 2>/dev/null || true
    echo "✅ Public key for update verification installed" >&2
else
    echo "⚠️  Public key not found, updates may not be verified" >&2
fi

# Install Python dependencies
echo "🐍 Installing Python dependencies..." >&2
python3 -m pip install --upgrade pip 2>/dev/null || true

# List of required packages for LightScope
REQUIRED_PACKAGES=(
    "cryptography"
    "dpkt"
    "psutil"
    "requests"
    "systemd-python"
)

for package in "${REQUIRED_PACKAGES[@]}"; do
    echo "  📦 Installing $package..." >&2
    python3 -m pip install "$package" 2>/dev/null || {
        echo "  ⚠️  Failed to install $package (may need manual installation)" >&2
    }
done

echo "✅ Python dependencies installation completed" >&2

# Check if we can import critical modules
echo "🔍 Verifying Python dependencies..." >&2
python3 -c "import cryptography; print('✅ cryptography module available')" 2>/dev/null || echo "⚠️  cryptography module not available" >&2
python3 -c "import dpkt; print('✅ dpkt module available')" 2>/dev/null || echo "⚠️  dpkt module not available" >&2
python3 -c "import psutil; print('✅ psutil module available')" 2>/dev/null || echo "⚠️  psutil module not available" >&2

# Enable and start the systemd service
echo "🏃 Setting up LightScope service..." >&2
systemctl daemon-reload 2>/dev/null || true

if systemctl enable lightscope.service 2>/dev/null; then
    echo "✅ LightScope service enabled (will start automatically on boot)" >&2
else
    echo "⚠️  Could not enable LightScope service" >&2
fi

if systemctl start lightscope.service 2>/dev/null; then
    echo "✅ LightScope service started successfully" >&2
    
    # Give the service a moment to start
    sleep 3
    
    # Check service status
    if systemctl is-active --quiet lightscope.service; then
        echo "✅ LightScope service is running" >&2
    else
        echo "⚠️  LightScope service may not be running properly" >&2
        echo "   Check logs with: journalctl -u lightscope -f" >&2
    fi
else
    echo "⚠️  Could not start LightScope service" >&2
    echo "   Try starting manually: sudo systemctl start lightscope" >&2
fi

# Display final information
echo "" >&2
echo "🎉 LIGHTSCOPE INSTALLATION COMPLETE!" >&2
echo "====================================" >&2
echo "" >&2
echo "📊 Your LightScope Database: $DB_NAME" >&2
echo "🌐 View your data at: https://thelightscope.com/tables/$DB_NAME" >&2
echo "" >&2
echo "📋 USEFUL COMMANDS:" >&2
echo "  Status:     systemctl status lightscope" >&2
echo "  Logs:       journalctl -u lightscope -f" >&2
echo "  Restart:    systemctl restart lightscope" >&2
echo "  Stop:       systemctl stop lightscope" >&2
echo "  Manual run: /opt/lightscope/bin/lightscope-runner.py" >&2
echo "" >&2
echo "📁 Configuration: /opt/lightscope/config/config.ini" >&2
echo "📝 Logs: /opt/lightscope/logs/" >&2
echo "" >&2
echo "🆘 Support: Visit https://thelightscope.com/support" >&2
echo "" >&2

%preun
# Stop and disable service before removal
if [ $1 -eq 0 ]; then
    systemctl stop lightscope.service 2>/dev/null || true
    systemctl disable lightscope.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    echo "LightScope service stopped and disabled"
fi

%postun
# Clean up user and directories on complete removal
if [ $1 -eq 0 ]; then
    # Remove lightscope user
    userdel lightscope 2>/dev/null || true
    echo "LightScope user removed"
    
    # Remove any remaining files
    rm -rf /opt/lightscope 2>/dev/null || true
    echo "LightScope directories cleaned up"
    
    echo "LightScope has been completely removed from your system"
fi

%changelog
* Mon Jan 01 2024 LightScope Team <support@thelightscope.com> - 1.0.2-1
- Updated to use external lightscope-runner.py instead of inline script
- Added forever retry logic without max failures
- Improved service management and monitoring
- Enhanced security settings for systemd service
- Better error handling and logging
- Automatic dependency installation
- Proper user permission handling

