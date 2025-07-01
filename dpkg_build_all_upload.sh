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

echo "1. Building dpkg package..."
./build-dpkg.sh

echo ""
echo "2. Package built successfully!"
ls -la *.deb

echo ""
echo "3. Package information:"
dpkg --info *.deb

echo ""
echo "4. Package contents:"
dpkg --contents *.deb

echo ""
echo "=== Code Signing Test ==="

# Check if cryptography is installed
if ! python3 -c "import cryptography" 2>/dev/null; then
    echo "Installing cryptography for signing..."
    pip3 install cryptography
fi

echo "5. Checking for signing keys..."
if [ ! -f "lightscope-private.pem" ] || [ ! -f "lightscope-public.pem" ]; then
    echo "Generating new RSA key pair..."
    python3 sign-and-upload.py --generate-keys
else
    echo "Using existing key pair:"
    echo "  - lightscope-private.pem"
    echo "  - lightscope-public.pem"
fi

echo ""
echo "6. Signing the code..."
python3 sign-and-upload.py --verify

echo ""
echo "7. Upload directory created:"
ls -la upload/

echo "8. Archive files created:"
ls -la lightscope_v*_upload.*

echo ""
echo "=== Test Complete ==="
echo ""
echo "📦 DEPLOYMENT INSTRUCTIONS 📦"
echo "=============================================="
echo ""
echo "Files created for distribution:"
echo "  1. upload/ directory - Contains all distribution files"
echo "  2. lightscope_v$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_upload.tar.gz - Complete package archive"
echo "  3. lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb - Debian installer"
echo ""
echo "🚀 SERVER UPLOAD LOCATIONS:"
echo "=============================================="
echo ""
echo "ALL FILES GO TO: 📁 /var/www/lightscope/latest/"
echo ""
echo "   ├── lightscope_core.py           → https://thelightscope.com/latest/lightscope_core.py"
echo "   ├── lightscope_core.py.sig       → https://thelightscope.com/latest/lightscope_core.py.sig"
echo "   ├── public-key                   → https://thelightscope.com/latest/public-key"
echo "   ├── version                      → https://thelightscope.com/latest/version"
echo "   └── lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb    → https://thelightscope.com/latest/lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb"
echo ""
echo "📋 UPLOAD COMMANDS:"
echo "=============================================="
echo ""
echo "# Extract and upload ALL files to /latest/:"
echo "tar -xzf lightscope_v$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_upload.tar.gz"
echo "scp upload/lightscope_core.py \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope_core.py.sig \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope-public.pem \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/public-key"
echo "scp upload/version \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/version"
echo "scp lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo ""
echo "🧪 TESTING DEPLOYMENT:"
echo "=============================================="
echo ""
echo "# Test all endpoints (all in /latest/ now):"
echo "curl https://thelightscope.com/latest/version"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl https://thelightscope.com/latest/lightscope_core.py"
echo "curl https://thelightscope.com/latest/lightscope_core.py.sig"
echo "curl https://thelightscope.com/latest/lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb"
echo ""
echo "🔧 LOCAL TESTING:"
echo "=============================================="
echo ""
echo "# Test installation:"
echo "sudo dpkg -i lightscope_$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_amd64.deb"
echo ""
echo "# Check service status:"
echo "sudo systemctl status lightscope"
echo ""
echo "# View logs:"
echo "sudo journalctl -fu lightscope"
echo ""
echo "✅ Package ready for distribution!"

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
echo "Enter server username (e.g., user):"
read SERVER_USER
echo "Enter server hostname (e.g., server):"
read SERVER_HOST
SERVER_USER_HOST="${SERVER_USER}@${SERVER_HOST}"

echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

echo ""
echo "📤 Uploading files to server..."

# Upload the tar.gz file
echo "Uploading lightscope_v$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')_upload.tar.gz..."
sshpass -p "$SERVER_PASSWORD" scp lightscope_v*_upload.tar.gz ${SERVER_USER_HOST}:~/

echo ""
echo "🔧 Deploying on remote server..."

# Create deployment script
sshpass -p "$SERVER_PASSWORD" ssh ${SERVER_USER_HOST} "cat > /tmp/deploy.sh << 'EOF'
#!/bin/bash
echo 'Moving archive to /tmp...'
mv lightscope_v*_upload.tar.gz /tmp/ 2>/dev/null || true

echo 'Switching to root and deploying...'
sudo bash -c '
    echo \"Cleaning existing files...\"
    rm -rf /var/www/lightscope/latest/*
    
    echo \"Moving archive to target directory...\"
    mv /tmp/lightscope_v*_upload.tar.gz /var/www/lightscope/latest/
    
    echo \"Changing to target directory...\"
    cd /var/www/lightscope/latest/
    
    echo \"Extracting archive...\"
    echo \"Archive contents before extraction:\"
    tar -tzf lightscope_v*_upload.tar.gz | head -10
    tar -xzf lightscope_v*_upload.tar.gz
    echo \"Directory contents after extraction:\"
    ls -la
    
    echo \"Moving contents from upload directory...\"
    if [ -d upload ]; then
        echo \"Found upload directory, moving contents...\"
        ls -la upload/
        mv upload/* . 2>/dev/null || echo \"No files in upload directory\"
        rm -rf upload/
    else
        echo \"Warning: upload directory not found after extraction\"
        echo \"Checking for alternative structure...\"
        echo \"Current directory contents:\"
        ls -la
        
        # Check if files are in subdirectories
        for dir in */; do
            if [ -d \"\$dir\" ]; then
                echo \"Checking directory: \$dir\"
                ls -la \"\$dir\"
                if [ -f \"\$dir/lightscope_core.py\" ]; then
                    echo \"Found lightscope_core.py in \$dir, moving contents...\"
                    mv \"\$dir\"/* . 2>/dev/null || echo \"No files to move from \$dir\"
                    rm -rf \"\$dir\"
                    break
                fi
            fi
        done
    fi
    
    echo \"Final directory contents after moving files:\"
    ls -la
    
    echo \"Cleaning up...\"
    rm lightscope_v*_upload.tar.gz
    
    echo \"Creating generic latest.deb symlink...\"
    cp lightscope_*_amd64.deb lightscope_latest.deb 2>/dev/null || true
    
    echo \"Setting proper permissions...\"
    chown -R www-data:www-data /var/www/lightscope/latest/
    
    # Set permissions only if files exist
    if ls /var/www/lightscope/latest/* 1> /dev/null 2>&1; then
        chmod -R 644 /var/www/lightscope/latest/*
        echo \"Permissions set successfully\"
    else
        echo \"Warning: No files found to set permissions on\"
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