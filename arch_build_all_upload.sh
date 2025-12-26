#!/bin/bash
set -e

# Add common package manager paths
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

# Add Homebrew to PATH on macOS (for building source tarball)
if [[ "$OSTYPE" == "darwin"* ]] && [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "=== LightScope Arch Linux Package Build ==="
echo ""
echo "Requirements for Arch Linux building:"
echo "  - makepkg (pre-installed on Arch Linux)"
echo "  - Required for signing: python3-cryptography"
echo ""
echo "Note: If not running on Arch Linux, a source tarball will be created"
echo "      that can be built on an Arch system using makepkg."
echo ""

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf upload/
rm -f lightscope_v*_upload.*
rm -f *.pkg.tar.*
rm -f *-arch-src.tar.gz

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

    # Try different methods to install cryptography
    if command -v pip3 &> /dev/null; then
        pip3 install cryptography
    elif command -v pip &> /dev/null; then
        pip install cryptography
    elif command -v pacman &> /dev/null; then
        echo "Using pacman to install python-cryptography..."
        sudo pacman -S --noconfirm python-cryptography
    elif command -v dnf &> /dev/null; then
        echo "Using DNF to install python3-cryptography..."
        sudo dnf install -y python3-cryptography
    elif command -v apt-get &> /dev/null; then
        echo "Using APT to install python3-cryptography..."
        sudo apt-get update && sudo apt-get install -y python3-cryptography
    else
        echo "Error: Cannot install cryptography. Please install manually:"
        echo "  Arch Linux: sudo pacman -S python-cryptography"
        echo "  Or with pip: python3 -m pip install cryptography"
        exit 1
    fi

    # Verify installation worked
    if ! python3 -c "import cryptography" 2>/dev/null; then
        echo "Error: Failed to install cryptography module"
        echo "Please install manually and run the script again"
        exit 1
    fi
    echo "Cryptography installed successfully"
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
echo "2. Building Arch Linux package..."
./build-arch.sh

echo ""
echo "3. Package built successfully!"

# Get version for display
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')

# Check what was built
if ls lightscope-*-*.pkg.tar.* 1> /dev/null 2>&1; then
    echo "Arch Linux packages:"
    ls -la lightscope-*-*.pkg.tar.*
    PKG_FILE=$(ls lightscope-*-*.pkg.tar.* 2>/dev/null | head -1)
    PKG_TYPE="arch"
elif ls *-arch-src.tar.gz 1> /dev/null 2>&1; then
    echo "Arch Linux source tarball:"
    ls -la *-arch-src.tar.gz
    PKG_FILE=$(ls *-arch-src.tar.gz 2>/dev/null | head -1)
    PKG_TYPE="arch-src"
else
    echo "Error: No package found"
    exit 1
fi

echo ""
echo "4. Signing the code..."
python3 sign-and-upload.py --verify --package-type arch

echo ""
echo "5. Upload directory created:"
ls -la upload/

echo "6. Archive files created:"
ls -la lightscope_v*_upload.*

echo ""
echo "=== Build Complete ==="
echo ""
echo "DEPLOYMENT INSTRUCTIONS"
echo "=============================================="
echo ""
echo "Files created for distribution:"
echo "  1. upload/ directory - Contains all distribution files"
echo "  2. lightscope_v${VERSION}_upload.tar.gz - Complete package archive"
if [ "$PKG_TYPE" = "arch" ]; then
    echo "  3. $PKG_FILE - Arch Linux installer"
else
    echo "  3. $PKG_FILE - Arch Linux source (build with makepkg on Arch)"
fi
echo ""
echo "SERVER UPLOAD LOCATIONS:"
echo "=============================================="
echo ""
echo "ALL FILES GO TO: /var/www/lightscope/latest/"
echo ""
echo "   lightscope_core.py           -> https://thelightscope.com/latest/lightscope_core.py"
echo "   lightscope_core.py.sig       -> https://thelightscope.com/latest/lightscope_core.py.sig"
echo "   public-key                   -> https://thelightscope.com/latest/public-key"
echo "   version                      -> https://thelightscope.com/latest/version"
echo "   $PKG_FILE -> https://thelightscope.com/latest/$PKG_FILE"
echo ""
echo "UPLOAD COMMANDS:"
echo "=============================================="
echo ""
echo "# Extract and upload ALL files to /latest/:"
echo "tar -xzf lightscope_v${VERSION}_upload.tar.gz"
echo "scp upload/lightscope_core.py \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope_core.py.sig \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope-public.pem \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/public-key"
echo "scp upload/version \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/version"
echo "scp $PKG_FILE \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo ""
echo "TESTING DEPLOYMENT:"
echo "=============================================="
echo ""
echo "# Test all endpoints (all in /latest/ now):"
echo "curl https://thelightscope.com/latest/version"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl https://thelightscope.com/latest/lightscope_core.py"
echo "curl https://thelightscope.com/latest/lightscope_core.py.sig"
echo "curl https://thelightscope.com/latest/$PKG_FILE"
echo ""
echo "LOCAL TESTING (on Arch Linux):"
echo "=============================================="
echo ""
if [ "$PKG_TYPE" = "arch" ]; then
    echo "# Test installation:"
    echo "sudo pacman -U $PKG_FILE"
else
    echo "# Build and install from source tarball:"
    echo "tar -xzf $PKG_FILE"
    echo "makepkg -si"
fi
echo ""
echo "# Check service status:"
echo "sudo systemctl status lightscope"
echo ""
echo "# View logs:"
echo "sudo journalctl -fu lightscope"
echo ""
echo "Package ready for distribution!"

echo ""
echo "AUTOMATED DEPLOYMENT TO SERVER"
echo "=============================================="
echo ""

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass for password authentication..."
    if command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm sshpass
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hudochenkov/sshpass/sshpass
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y sshpass
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y sshpass
    else
        echo "Please install sshpass manually"
        exit 1
    fi
fi

# Server credentials
SERVER_USER="kapitans"
SERVER_HOST="lightscope.isi.edu"
SERVER_USER_HOST="${SERVER_USER}@${SERVER_HOST}"

echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

echo ""
echo "Uploading files to server..."

# Upload the tar.gz file
echo "Uploading lightscope_v${VERSION}_upload.tar.gz..."
sshpass -p "$SERVER_PASSWORD" scp lightscope_v*_upload.tar.gz ${SERVER_USER_HOST}:~/

echo ""
echo "Deploying on remote server..."

# Create deployment script
sshpass -p "$SERVER_PASSWORD" ssh ${SERVER_USER_HOST} "cat > /tmp/deploy_arch.sh << 'EOF'
#!/bin/bash
echo 'Moving archive to /tmp...'
mv lightscope_v*_upload.tar.gz /tmp/ 2>/dev/null || true

echo 'Switching to root and deploying...'
sudo bash -c '
    echo \"Cleaning existing Arch packages...\"
    rm -f /var/www/lightscope/latest/*.pkg.tar.*
    rm -f /var/www/lightscope/latest/*-arch-src.tar.gz

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

    echo \"Creating generic latest Arch package link...\"
    ARCH_PKG=\$(ls -t lightscope-*-*.pkg.tar.* 2>/dev/null | head -1)
    if [ -n \"\$ARCH_PKG\" ]; then
        cp \"\$ARCH_PKG\" lightscope_latest.pkg.tar.zst 2>/dev/null || true
    fi

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
chmod +x /tmp/deploy_arch.sh"

# Execute deployment script
echo "Executing deployment script..."
sshpass -p "$SERVER_PASSWORD" ssh -t ${SERVER_USER_HOST} "/tmp/deploy_arch.sh && rm /tmp/deploy_arch.sh"

echo ""
echo "DEPLOYMENT COMPLETE!"
echo ""
echo "You can now test the deployment:"
echo "curl https://thelightscope.com/latest/version"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl https://thelightscope.com/latest/$PKG_FILE"
