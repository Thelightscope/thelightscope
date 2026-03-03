#!/bin/bash
set -e

# Add Homebrew to PATH on macOS
if [[ "$OSTYPE" == "darwin"* ]] && [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "=== LightScope DEB Package Build ==="
echo ""
echo "Requirements for building:"
echo "  - DEB: dpkg-deb (usually pre-installed on Debian/Ubuntu)"
echo ""

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf upload/
rm -f lightscope_v*_upload.*
rm -f *.deb

# Check if we're in the right directory
if [ ! -f "lightscope/lightscope_core.py" ]; then
    echo "Error: Please run this script from the thelightscope directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

echo "=== Code Signing Keys Setup ==="

# Check if cryptography is installed
if ! python3 -c "import cryptography" 2>/dev/null; then
    echo "Installing cryptography for signing..."
    pip3 install cryptography
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
echo "2. Building standard dpkg package (honeypots=yes)..."
./build-dpkg.sh

echo ""
echo "3. Building no-honeypot dpkg package (honeypots=no)..."
LIGHTSCOPE_NO_HONEYPOT=1 ./build-dpkg.sh

echo ""
echo "4. Packages built successfully!"
ls -la *.deb

echo ""
echo "5. Package information (standard):"
dpkg --info lightscope_*_all.deb

echo ""
echo "6. Package information (no-honeypot):"
dpkg --info lightscope-nohoneypot_*_all.deb

echo ""
echo "7. Signing the code..."
python3 sign-and-upload.py --verify --package-type deb

echo ""
echo "8. Upload directory created:"
ls -la upload/

echo "9. Archive files created:"
ls -la lightscope_v*_upload.*

VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
STD_DEB="lightscope_${VERSION}_all.deb"
NOHP_DEB="lightscope-nohoneypot_${VERSION}_all.deb"

echo ""
echo "=== Test Complete ==="
echo ""
echo "📦 DEPLOYMENT INSTRUCTIONS 📦"
echo "=============================================="
echo ""
echo "Files created for distribution:"
echo "  1. upload/ directory - Contains all distribution files"
echo "  2. lightscope_v${VERSION}_upload.tar.gz - Complete package archive"
echo "  3. $STD_DEB - Debian installer (honeypots enabled)"
echo "  4. $NOHP_DEB - Debian installer (honeypots disabled)"
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
echo "   ├── $STD_DEB  → (standard)"
echo "   └── $NOHP_DEB → (no-honeypot)"
echo ""
echo "🔧 LOCAL TESTING:"
echo "=============================================="
echo ""
echo "# Test standard installation:"
echo "sudo dpkg -i $STD_DEB"
echo ""
echo "# Test no-honeypot installation:"
echo "sudo dpkg -i $NOHP_DEB"
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
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hudochenkov/sshpass/sshpass
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y sshpass
    fi
fi

# Prompt for server credentials
#echo "Enter server username (e.g., user):"
#read SERVER_USER
#echo "Enter server hostname (e.g., server):"
#read SERVER_HOST
#SERVER_USER_HOST="${SERVER_USER}@${SERVER_HOST}"
SERVER_USER_HOST="kapitans@lightscope.isi.edu"

echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

echo ""
echo "📤 Uploading files to server..."

# Upload the tar.gz file and both deb files
echo "Uploading archive and deb packages..."
sshpass -p "$SERVER_PASSWORD" scp lightscope_v*_upload.tar.gz ${SERVER_USER_HOST}:~/
sshpass -p "$SERVER_PASSWORD" scp "$STD_DEB" ${SERVER_USER_HOST}:~/
sshpass -p "$SERVER_PASSWORD" scp "$NOHP_DEB" ${SERVER_USER_HOST}:~/

echo ""
echo "🔧 Deploying on remote server..."

# Create deployment script
sshpass -p "$SERVER_PASSWORD" ssh ${SERVER_USER_HOST} "cat > /tmp/deploy.sh << 'EOF'
#!/bin/bash
echo 'Moving files to /tmp...'
mv lightscope_v*_upload.tar.gz /tmp/ 2>/dev/null || true
mv lightscope_*_all.deb /tmp/ 2>/dev/null || true
mv lightscope-nohoneypot_*_all.deb /tmp/ 2>/dev/null || true

echo 'Switching to root and deploying...'
sudo bash -c '
    echo \"Moving files to target directory...\"
    mv /tmp/lightscope_v*_upload.tar.gz /var/www/lightscope/latest/
    mv /tmp/lightscope_*_all.deb /var/www/lightscope/latest/ 2>/dev/null || true
    mv /tmp/lightscope-nohoneypot_*_all.deb /var/www/lightscope/latest/ 2>/dev/null || true

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

    echo \"Creating generic latest deb files...\"
    rm -f lightscope_latest.deb lightscope-nohoneypot_latest.deb

    STD=\$(ls -t lightscope_*_all.deb 2>/dev/null | grep -v nohoneypot | head -1)
    if [ -n \"\$STD\" ] && [ -f \"\$STD\" ]; then
        cp \"\$STD\" lightscope_latest.deb
        echo \"Created lightscope_latest.deb from \$STD\"
    fi

    NOHP=\$(ls -t lightscope-nohoneypot_*_all.deb 2>/dev/null | head -1)
    if [ -n \"\$NOHP\" ] && [ -f \"\$NOHP\" ]; then
        cp \"\$NOHP\" lightscope-nohoneypot_latest.deb
        echo \"Created lightscope-nohoneypot_latest.deb from \$NOHP\"
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
chmod +x /tmp/deploy.sh"

# Execute deployment script
echo "Executing deployment script..."
sshpass -p "$SERVER_PASSWORD" ssh -t ${SERVER_USER_HOST} "/tmp/deploy.sh && rm /tmp/deploy.sh"

echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "🧪 You can now test the deployment:"
echo "curl https://thelightscope.com/latest/version"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl -O https://thelightscope.com/latest/lightscope_latest.deb"
echo "curl -O https://thelightscope.com/latest/lightscope-nohoneypot_latest.deb" 