#!/bin/bash
set -e

# Add common package manager paths
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

echo "=== LightScope RPM Package Build ==="
echo ""
echo "Requirements for RPM building:"
echo "  - rpmbuild (install with: yum/dnf install rpm-build)"
echo "  - Required for signing: python3-cryptography"
echo ""

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf upload/
rm -f lightscope_v*_upload.*
rm -f *.rpm

# Check if we're in the right directory
if [ ! -f "lightscope/lightscope_core.py" ]; then
    echo "Error: Please run this script from the thelightscope directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Check for rpmbuild
if ! command -v rpmbuild &> /dev/null; then
    echo "Error: rpmbuild not found. Install with:"
    echo "  RHEL/CentOS/Fedora: sudo yum/dnf install rpm-build"
    echo "  openSUSE: sudo zypper install rpm-build"
    exit 1
fi

echo "=== Code Signing Keys Setup ==="

# Check if cryptography is installed
if ! python3 -c "import cryptography" 2>/dev/null; then
    echo "Installing cryptography for signing..."
    
    # Try different methods to install cryptography
    if command -v pip3 &> /dev/null; then
        pip3 install cryptography
    elif command -v pip &> /dev/null; then
        pip install cryptography
    elif command -v dnf &> /dev/null; then
        echo "Using DNF to install python3-cryptography..."
        sudo dnf install -y python3-cryptography
    elif command -v yum &> /dev/null; then
        echo "Using YUM to install python3-cryptography..."
        sudo yum install -y python3-cryptography
    elif command -v zypper &> /dev/null; then
        echo "Using Zypper to install python3-cryptography..."
        sudo zypper install -y python3-cryptography
    elif command -v apt-get &> /dev/null; then
        echo "Using APT to install python3-cryptography..."
        sudo apt-get update && sudo apt-get install -y python3-cryptography
    else
        echo "Error: Cannot install cryptography. Please install manually:"
        echo "  RHEL/CentOS/Fedora: sudo dnf install python3-cryptography"
        echo "  Debian/Ubuntu: sudo apt-get install python3-cryptography" 
        echo "  openSUSE: sudo zypper install python3-cryptography"
        echo "  Or with pip: python3 -m pip install cryptography"
        exit 1
    fi
    
    # Verify installation worked
    if ! python3 -c "import cryptography" 2>/dev/null; then
        echo "Error: Failed to install cryptography module"
        echo "Please install manually and run the script again"
        exit 1
    fi
    echo "✓ Cryptography installed successfully"
fi

echo "1. Checking for signing keys..."
if [ ! -f "lightscope-private.pem" ] || [ ! -f "lightscope-public.pem" ]; then
    echo "Generating new RSA key pair..."
    python3 sign-and-upload.py --generate-keys
else
    echo "Using existing key pair:"
    echo "  - lightscope-private.pem"
    echo "  - lightscope-public.pem"
fi

echo ""
echo "2. Building standard RPM package (honeypots=yes)..."
./build-rpm.sh

echo ""
echo "3. Building no-honeypot RPM package (honeypots=no)..."
LIGHTSCOPE_NO_HONEYPOT=1 ./build-rpm.sh

echo ""
echo "4. Packages built successfully!"
echo "RPM packages:"
ls -la *.rpm 2>/dev/null || echo "No .rpm packages found"

# Get the actual RPM filenames for use in deployment
STD_RPM=$(ls lightscope-[0-9]*-*.noarch.rpm 2>/dev/null | head -1)
NOHP_RPM=$(ls lightscope-nohoneypot-*-*.noarch.rpm 2>/dev/null | head -1)
if [ -z "$STD_RPM" ]; then
    echo "Error: No standard RPM package found"
    exit 1
fi
if [ -z "$NOHP_RPM" ]; then
    echo "Error: No no-honeypot RPM package found"
    exit 1
fi
echo "Standard RPM: $STD_RPM"
echo "No-honeypot RPM: $NOHP_RPM"

echo ""
echo "5. RPM Package information (standard):"
rpm -qip "$STD_RPM" 2>/dev/null || echo "RPM tools not available on this system"

echo ""
echo "6. RPM Package information (no-honeypot):"
rpm -qip "$NOHP_RPM" 2>/dev/null || echo "RPM tools not available on this system"

echo ""
echo "7. Signing the code..."
python3 sign-and-upload.py --verify --package-type rpm

echo ""
echo "8. Upload directory created:"
ls -la upload/

echo "9. Archive files created:"
ls -la lightscope_v*_upload.*

VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')

echo ""
echo "=== Test Complete ==="
echo ""
echo "📦 DEPLOYMENT INSTRUCTIONS 📦"
echo "=============================================="
echo ""
echo "Files created for distribution:"
echo "  1. upload/ directory - Contains all distribution files"
echo "  2. lightscope_v${VERSION}_upload.tar.gz - Complete package archive"
echo "  3. $STD_RPM - RPM installer (honeypots enabled)"
echo "  4. $NOHP_RPM - RPM installer (honeypots disabled)"
echo ""
echo "🚀 SERVER UPLOAD LOCATIONS:"
echo "=============================================="
echo ""
echo "ALL FILES GO TO: 📁 /var/www/lightscope/latest/"
echo ""
echo "   ├── lightscope_core.py                → https://thelightscope.com/latest/lightscope_core.py"
echo "   ├── lightscope_core.py.sig            → https://thelightscope.com/latest/lightscope_core.py.sig"
echo "   ├── public-key                        → https://thelightscope.com/latest/public-key"
echo "   ├── version                           → https://thelightscope.com/latest/version"
echo "   ├── $STD_RPM  → (standard)"
echo "   └── $NOHP_RPM → (no-honeypot)"
echo ""
echo "🔧 LOCAL TESTING:"
echo "=============================================="
echo ""
echo "# Test standard RPM installation:"
echo "sudo rpm -i $STD_RPM"
echo "# Or: sudo dnf install ./$STD_RPM"
echo ""
echo "# Test no-honeypot RPM installation:"
echo "sudo rpm -i $NOHP_RPM"
echo "# Or: sudo dnf install ./$NOHP_RPM"
echo ""
echo "# Check service status:"
echo "sudo systemctl status lightscope"
echo ""
echo "# View logs:"
echo "sudo journalctl -fu lightscope"
echo ""
echo "✅ Packages ready for distribution!"

echo ""
echo "🚀 AUTOMATED DEPLOYMENT TO SERVER"
echo "=============================================="
echo ""

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass for password authentication..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y sshpass
    elif command -v yum &> /dev/null; then
        sudo yum install -y sshpass
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y sshpass
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y sshpass
    else
        echo "Please install sshpass manually"
        exit 1
    fi
fi

# Prompt for server credentials
echo "Enter server username (e.g., user):"
#read SERVER_USER
#echo "Enter server hostname (e.g., server):"
#read SERVER_HOST
SERVER_USER="kapitans"
SERVER_HOST="lightscope.isi.edu"
SERVER_USER_HOST="${SERVER_USER}@${SERVER_HOST}"

echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

echo ""
echo "📤 Uploading files to server..."

# Upload the tar.gz file and both RPM files
echo "Uploading archive and RPM packages..."
sshpass -p "$SERVER_PASSWORD" scp lightscope_v*_upload.tar.gz ${SERVER_USER_HOST}:~/
sshpass -p "$SERVER_PASSWORD" scp "$STD_RPM" ${SERVER_USER_HOST}:~/
sshpass -p "$SERVER_PASSWORD" scp "$NOHP_RPM" ${SERVER_USER_HOST}:~/

echo ""
echo "🔧 Deploying on remote server..."

# Create deployment script
sshpass -p "$SERVER_PASSWORD" ssh ${SERVER_USER_HOST} "cat > /tmp/deploy_rpm.sh << 'EOF'
#!/bin/bash
echo 'Moving files to /tmp...'
mv lightscope_v*_upload.tar.gz /tmp/ 2>/dev/null || true
mv lightscope-*-*.noarch.rpm /tmp/ 2>/dev/null || true
mv lightscope-nohoneypot-*-*.noarch.rpm /tmp/ 2>/dev/null || true

echo 'Switching to root and deploying...'
sudo bash -c '
    echo \"Cleaning existing RPM files...\"
    rm -f /var/www/lightscope/latest/*.rpm

    echo \"Moving files to target directory...\"
    mv /tmp/lightscope_v*_upload.tar.gz /var/www/lightscope/latest/
    mv /tmp/lightscope-*-*.noarch.rpm /var/www/lightscope/latest/ 2>/dev/null || true
    mv /tmp/lightscope-nohoneypot-*-*.noarch.rpm /var/www/lightscope/latest/ 2>/dev/null || true

    echo \"Changing to target directory...\"
    cd /var/www/lightscope/latest/

    echo \"Extracting archive...\"
    tar -xzf lightscope_v*_upload.tar.gz

    echo \"Moving contents from upload directory...\"
    if [ -d upload ]; then
        mv upload/* . 2>/dev/null || echo \"No files in upload directory\"
        rm -rf upload/
    fi

    echo \"Cleaning up archive...\"
    rm -f lightscope_v*_upload.tar.gz

    echo \"Creating generic latest RPM files...\"
    rm -f lightscope_latest.rpm lightscope-nohoneypot_latest.rpm

    STD=\$(ls -t lightscope-[0-9]*-*.noarch.rpm 2>/dev/null | head -1)
    if [ -n \"\$STD\" ] && [ -f \"\$STD\" ]; then
        cp \"\$STD\" lightscope_latest.rpm
        echo \"Created lightscope_latest.rpm from \$STD\"
    fi

    NOHP=\$(ls -t lightscope-nohoneypot-*-*.noarch.rpm 2>/dev/null | head -1)
    if [ -n \"\$NOHP\" ] && [ -f \"\$NOHP\" ]; then
        cp \"\$NOHP\" lightscope-nohoneypot_latest.rpm
        echo \"Created lightscope-nohoneypot_latest.rpm from \$NOHP\"
    fi

    echo \"Setting proper permissions...\"
    chown -R www-data:www-data /var/www/lightscope/latest/
    if ls /var/www/lightscope/latest/* 1> /dev/null 2>&1; then
        chmod -R 644 /var/www/lightscope/latest/*
    fi

    echo \"Deployment complete!\"
    ls -la /var/www/lightscope/latest/
'
EOF
chmod +x /tmp/deploy_rpm.sh"

# Execute deployment script
echo "Executing deployment script..."
sshpass -p "$SERVER_PASSWORD" ssh -t ${SERVER_USER_HOST} "/tmp/deploy_rpm.sh && rm /tmp/deploy_rpm.sh"

echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "🧪 You can now test the deployment:"
echo "curl https://thelightscope.com/latest/version"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl -O https://thelightscope.com/latest/lightscope_latest.rpm"
echo "curl -O https://thelightscope.com/latest/lightscope-nohoneypot_latest.rpm" 