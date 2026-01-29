#!/bin/bash
set -e

# Add common paths
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

# Add Homebrew to PATH on macOS
if [[ "$OSTYPE" == "darwin"* ]] && [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== LightScope OPNsense Package Build & Deploy ==="
echo ""
echo "Requirements:"
echo "  - Python3 with cryptography module for signing packages"
echo "  - FreeBSD/OPNsense system for building .pkg (or pre-built package)"
echo ""

# Configuration
OPNSENSE_DIR="opnsense"
UPLOAD_DIR="opnsense_upload"
SERVER_USER="kapitans"
SERVER_HOST="lightscope.isi.edu"
SERVER_PATH="/var/www/lightscope/opnsense"
PRIVATE_KEY="lightscope-private.pem"
PUBLIC_KEY="lightscope-public.pem"

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf "$UPLOAD_DIR/"
rm -f opnsense_v*_upload.*

# Check if we're in the right directory
if [ ! -d "$OPNSENSE_DIR" ]; then
    echo -e "${RED}Error: Please run this script from the thelightscope directory${NC}"
    echo "Current directory: $(pwd)"
    echo "Expected to find: $OPNSENSE_DIR/"
    exit 1
fi

# Extract version from Makefile
VERSION=$(grep "^PLUGIN_VERSION=" "$OPNSENSE_DIR/Makefile" | cut -d'=' -f2 | tr -d '[:space:]\t')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from Makefile${NC}"
    exit 1
fi
echo -e "${GREEN}Building LightScope OPNsense v$VERSION${NC}"

echo ""
echo "=== Step 1: Code Signing Keys Setup ==="

# Check if cryptography is installed
if ! python3 -c "import cryptography" 2>/dev/null; then
    echo "Installing cryptography for signing..."
    pip3 install cryptography
fi

# Check for existing key pair
if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    echo "No signing key pair found."
    echo "Generating new RSA key pair..."
    python3 sign-and-upload.py --generate-keys
    echo -e "${GREEN}Generated new RSA key pair${NC}"
else
    echo -e "${GREEN}Using existing key pair:${NC}"
    echo "  - $PRIVATE_KEY"
    echo "  - $PUBLIC_KEY"
fi

# Copy public key to upload directory
echo "Copying public key..."
mkdir -p "$UPLOAD_DIR/keys"
cp "$PUBLIC_KEY" "$UPLOAD_DIR/keys/lightscope-public.pem"
echo "Public key copied to: $UPLOAD_DIR/keys/lightscope-public.pem"

# Also update the embedded public key in the source
mkdir -p "$OPNSENSE_DIR/src/share/lightscope"
cp "$PUBLIC_KEY" "$OPNSENSE_DIR/src/share/lightscope/lightscope-public.pem"
echo "Updated embedded public key in source"

echo ""
echo "=== Step 2: Build Package ==="

# Check if we're on FreeBSD/OPNsense
if [ "$(uname)" = "FreeBSD" ]; then
    echo "Building on FreeBSD/OPNsense..."
    cd "$OPNSENSE_DIR"

    # Clean previous build
    make clean 2>/dev/null || true

    # Build package
    make package

    # Find the built package
    PKG_FILE=$(find work/pkg -name "*.pkg" 2>/dev/null | head -1)
    if [ -z "$PKG_FILE" ]; then
        echo -e "${RED}Error: Package build failed - no .pkg file found${NC}"
        exit 1
    fi

    # Copy to parent directory
    cp "$PKG_FILE" "../os-lightscope-${VERSION}.pkg"
    cd ..

    echo -e "${GREEN}Package built: os-lightscope-${VERSION}.pkg${NC}"
else
    echo -e "${YELLOW}Not on FreeBSD - checking for pre-built package...${NC}"

    # Look for existing package
    PKG_FILE="os-lightscope-${VERSION}.pkg"
    if [ ! -f "$PKG_FILE" ]; then
        # Try to find any version
        PKG_FILE=$(ls os-lightscope-*.pkg 2>/dev/null | head -1)
    fi

    if [ -z "$PKG_FILE" ] || [ ! -f "$PKG_FILE" ]; then
        echo ""
        echo -e "${YELLOW}No pre-built package found.${NC}"
        echo ""
        echo "To build the package, you need to either:"
        echo "  1. Run this script on FreeBSD/OPNsense"
        echo "  2. Copy a pre-built os-lightscope-${VERSION}.pkg to this directory"
        echo ""
        echo "To build on OPNsense:"
        echo "  cd /path/to/opnsense"
        echo "  make package"
        echo "  # Package will be in work/pkg/"
        echo ""

        # Create a source tarball for manual building
        echo "Creating source tarball for manual building..."
        TAR_NAME="os-lightscope-${VERSION}-src.tar.gz"
        tar -czf "$TAR_NAME" -C "$OPNSENSE_DIR" .
        echo -e "${GREEN}Source tarball created: $TAR_NAME${NC}"
        echo ""
        echo "Copy this to your OPNsense system and run:"
        echo "  tar -xzf $TAR_NAME"
        echo "  make package"
        echo ""

        echo "Do you want to continue without the package? (for testing upload) (y/n)"
        read -r CONTINUE_WITHOUT_PKG
        if [ "$CONTINUE_WITHOUT_PKG" != "y" ] && [ "$CONTINUE_WITHOUT_PKG" != "Y" ]; then
            exit 1
        fi
        PKG_FILE=""
    else
        echo -e "${GREEN}Found pre-built package: $PKG_FILE${NC}"
    fi
fi

echo ""
echo "=== Step 3: Sign Package ==="

mkdir -p "$UPLOAD_DIR/pkg"

if [ -n "$PKG_FILE" ] && [ -f "$PKG_FILE" ]; then
    # Copy package to upload directory
    cp "$PKG_FILE" "$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg"

    # Sign the package using Python/cryptography (same as dpkg)
    echo "Signing package with RSA key..."
    python3 << SIGN_EOF
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
import hashlib

# Load private key
with open("$PRIVATE_KEY", 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

# Read the package file
with open("$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg", 'rb') as f:
    file_data = f.read()

# Create signature
signature = private_key.sign(
    file_data,
    padding.PSS(
        mgf=padding.MGF1(hashes.SHA256()),
        salt_length=padding.PSS.MAX_LENGTH
    ),
    hashes.SHA256()
)

# Save signature
with open("$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg.sig", 'wb') as f:
    f.write(signature)

print(f"Signed package: $UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg")
print(f"Signature size: {len(signature)} bytes")
SIGN_EOF

    # Calculate SHA256
    if command -v sha256sum &> /dev/null; then
        SHA256=$(sha256sum "$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        SHA256=$(shasum -a 256 "$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg" | awk '{print $1}')
    else
        echo -e "${RED}Error: No SHA256 tool found${NC}"
        exit 1
    fi

    echo -e "${GREEN}Package signed successfully${NC}"
    echo "SHA256: $SHA256"
else
    echo -e "${YELLOW}Skipping package signing (no package file)${NC}"
    SHA256="PLACEHOLDER_SHA256_REPLACE_AFTER_BUILD"
fi

echo ""
echo "=== Step 4: Create Version Manifest ==="

# Get current date in ISO format
RELEASE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create version.json
cat > "$UPLOAD_DIR/version.json" << EOF
{
    "current_version": "$VERSION",
    "release_date": "$RELEASE_DATE",
    "package_url": "https://thelightscope.com/opnsense/pkg/os-lightscope-${VERSION}.pkg",
    "signature_url": "https://thelightscope.com/opnsense/pkg/os-lightscope-${VERSION}.pkg.sig",
    "public_key_url": "https://thelightscope.com/opnsense/keys/lightscope-public.pem",
    "sha256": "$SHA256",
    "changelog": "LightScope OPNsense Plugin v$VERSION",
    "requires_restart": true,
    "freebsd_version_min": "14.0",
    "opnsense_version_min": "24.7"
}
EOF

echo -e "${GREEN}Created version.json${NC}"
cat "$UPLOAD_DIR/version.json"

echo ""
echo "=== Step 5: Verify Signature ==="

if [ -f "$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg" ]; then
    echo "Verifying RSA signature..."
    python3 << VERIFY_EOF
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature
import sys

try:
    # Load public key
    with open("$PUBLIC_KEY", 'rb') as f:
        public_key = serialization.load_pem_public_key(f.read())

    # Read the package file
    with open("$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg", 'rb') as f:
        file_data = f.read()

    # Read the signature
    with open("$UPLOAD_DIR/pkg/os-lightscope-${VERSION}.pkg.sig", 'rb') as f:
        signature = f.read()

    # Verify signature
    public_key.verify(
        signature,
        file_data,
        padding.PSS(
            mgf=padding.MGF1(hashes.SHA256()),
            salt_length=padding.PSS.MAX_LENGTH
        ),
        hashes.SHA256()
    )

    print("Signature verification successful!")
    sys.exit(0)

except InvalidSignature:
    print("Signature verification FAILED: Invalid signature")
    sys.exit(1)
except Exception as e:
    print(f"Signature verification FAILED: {e}")
    sys.exit(1)
VERIFY_EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Signature verification successful!${NC}"
    else
        echo -e "${RED}Signature verification FAILED!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping signature verification (no package file)${NC}"
fi

echo ""
echo "=== Step 6: Create Upload Archive ==="

# Create tar.gz archive
TAR_NAME="opnsense_v${VERSION}_upload.tar.gz"
tar -czf "$TAR_NAME" "$UPLOAD_DIR"
echo -e "${GREEN}Created archive: $TAR_NAME${NC}"

echo ""
echo "=== Upload Directory Contents ==="
find "$UPLOAD_DIR" -type f -exec ls -la {} \;

echo ""
echo "=== Step 7: Deploy to Server ==="
echo ""

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}sshpass not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null || echo "Please install sshpass manually"
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y sshpass
    else
        echo "Please install sshpass manually"
    fi
fi

SERVER_USER_HOST="${SERVER_USER}@${SERVER_HOST}"
echo "Server: $SERVER_USER_HOST"
echo "Path: $SERVER_PATH"
echo ""
echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

if [ -z "$SERVER_PASSWORD" ]; then
    echo -e "${RED}No password provided. Skipping upload.${NC}"
    echo ""
    echo "Manual upload commands:"
    echo "  scp $TAR_NAME ${SERVER_USER_HOST}:~/"
    echo "  ssh ${SERVER_USER_HOST}"
    echo "  sudo mkdir -p $SERVER_PATH/pkg $SERVER_PATH/keys"
    echo "  sudo mv ~/$TAR_NAME /tmp/"
    echo "  cd /tmp && sudo tar -xzf $TAR_NAME"
    echo "  sudo mv $UPLOAD_DIR/* $SERVER_PATH/"
    echo "  sudo chown -R www-data:www-data $SERVER_PATH"
    exit 0
fi

echo ""
echo "Uploading archive to server..."
sshpass -p "$SERVER_PASSWORD" scp "$TAR_NAME" "${SERVER_USER_HOST}:~/"

echo ""
echo "Deploying on remote server..."

# Create deployment script
sshpass -p "$SERVER_PASSWORD" ssh "${SERVER_USER_HOST}" "cat > /tmp/deploy_opnsense.sh << 'DEPLOY_EOF'
#!/bin/bash
echo 'Moving archive to /tmp...'
mv ~/$TAR_NAME /tmp/ 2>/dev/null || true

echo 'Deploying with sudo...'
sudo bash -c '
    # Create directory structure
    mkdir -p $SERVER_PATH/pkg
    mkdir -p $SERVER_PATH/keys

    echo \"Extracting archive...\"
    cd /tmp
    tar -xzf $TAR_NAME

    echo \"Moving files to server path...\"
    # Move version.json
    if [ -f $UPLOAD_DIR/version.json ]; then
        mv $UPLOAD_DIR/version.json $SERVER_PATH/
        echo \"Deployed version.json\"
    fi

    # Move package files
    if [ -d $UPLOAD_DIR/pkg ]; then
        mv $UPLOAD_DIR/pkg/* $SERVER_PATH/pkg/ 2>/dev/null || true
        echo \"Deployed package files\"
    fi

    # Move keys
    if [ -d $UPLOAD_DIR/keys ]; then
        mv $UPLOAD_DIR/keys/* $SERVER_PATH/keys/ 2>/dev/null || true
        echo \"Deployed GPG keys\"
    fi

    # Clean up
    rm -rf $UPLOAD_DIR $TAR_NAME

    # Set permissions
    chown -R www-data:www-data $SERVER_PATH
    chmod -R 644 $SERVER_PATH/*
    chmod 755 $SERVER_PATH $SERVER_PATH/pkg $SERVER_PATH/keys

    echo \"\"
    echo \"Final directory contents:\"
    find $SERVER_PATH -type f -exec ls -la {} \;
'
echo 'Deployment complete!'
DEPLOY_EOF
chmod +x /tmp/deploy_opnsense.sh"

# Execute deployment
sshpass -p "$SERVER_PASSWORD" ssh -t "${SERVER_USER_HOST}" "/tmp/deploy_opnsense.sh && rm /tmp/deploy_opnsense.sh"

echo ""
echo -e "${GREEN}=== DEPLOYMENT COMPLETE ===${NC}"
echo ""
echo "Test the deployment:"
echo "  curl https://thelightscope.com/opnsense/version.json"
echo "  curl https://thelightscope.com/opnsense/keys/lightscope-public.pem"
if [ -n "$PKG_FILE" ]; then
    echo "  curl -I https://thelightscope.com/opnsense/pkg/os-lightscope-${VERSION}.pkg"
fi
echo ""
echo "Server URLs:"
echo "  Version manifest: https://thelightscope.com/opnsense/version.json"
echo "  Public key:       https://thelightscope.com/opnsense/keys/lightscope-public.pem"
echo "  Package:          https://thelightscope.com/opnsense/pkg/os-lightscope-${VERSION}.pkg"
echo "  Signature:        https://thelightscope.com/opnsense/pkg/os-lightscope-${VERSION}.pkg.sig"
