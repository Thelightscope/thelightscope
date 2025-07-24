#!/bin/bash
set -e

# Add Homebrew to PATH on macOS
if [[ "$OSTYPE" == "darwin"* ]] && [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "=== LightScope macOS Package Build and Sign ==="
echo ""
echo "Requirements for building:"
echo "  - macOS: Xcode Command Line Tools"
echo "  - Python 3.8+ with cryptography package"
echo ""

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf upload/
rm -f lightscope_v*_upload.*
rm -f LightScope-*-macOS.zip

# Check if we're in the right directory
if [ ! -f "lightscope/lightscope_core_mac.py" ]; then
    echo "Error: Please run this script from the thelightscope directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

echo "1. Building macOS package..."
./build-macos.sh

echo ""
echo "2. Package built successfully!"
ls -la LightScope-*-macOS.zip

echo ""
echo "=== Code Signing for macOS ==="

# Check if cryptography is installed
if ! python3 -c "import cryptography" 2>/dev/null; then
    echo "Installing cryptography for signing..."
    pip3 install cryptography
fi

echo "3. Checking for signing keys..."
if [ ! -f "lightscope-private.pem" ] || [ ! -f "lightscope-public.pem" ]; then
    echo "Generating new RSA key pair..."
    python3 sign-and-upload.py --generate-keys
else
    echo "Using existing key pair:"
    echo "  - lightscope-private.pem"
    echo "  - lightscope-public.pem"
fi

echo ""
echo "4. Signing the macOS core file for distribution..."

# Create macOS-specific signing script
cat > sign-mac-distribution.py << 'EOF'
#!/usr/bin/env python3
"""
Code Signing and Upload Script for LightScope macOS
This script signs the lightscope_core_mac.py file and prepares it for secure distribution.
"""

import os
import sys
import json
import hashlib
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
import argparse
import shutil

def load_private_key(private_key_path):
    """Load private key from file"""
    try:
        with open(private_key_path, 'rb') as f:
            private_key = serialization.load_pem_private_key(
                f.read(),
                password=None,
            )
        return private_key
    except Exception as e:
        print(f"Error loading private key: {e}")
        return None

def sign_file(file_path, private_key, signature_path):
    """Sign a file using the private key"""
    try:
        # Read the file to be signed
        with open(file_path, 'rb') as f:
            file_data = f.read()
        
        # Debug information
        print(f"  Signing file size: {len(file_data)} bytes")
        print(f"  File hash (SHA256): {hashlib.sha256(file_data).hexdigest()[:16]}...")
        
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
        with open(signature_path, 'wb') as f:
            f.write(signature)
        
        print(f"  Signature size: {len(signature)} bytes")
        print(f"File signed successfully: {signature_path}")
        return True
        
    except Exception as e:
        print(f"Error signing file: {e}")
        return False

def verify_signature(file_path, signature_path, public_key_path):
    """Verify a signature (for testing)"""
    try:
        # Check if files exist
        for path, name in [(file_path, "file"), (signature_path, "signature"), (public_key_path, "public key")]:
            if not Path(path).exists():
                print(f"Error: {name} not found: {path}")
                return False
        
        # Load public key
        with open(public_key_path, 'rb') as f:
            public_key_data = f.read()
            public_key = serialization.load_pem_public_key(public_key_data)
        
        # Read file and signature
        with open(file_path, 'rb') as f:
            file_data = f.read()
        
        with open(signature_path, 'rb') as f:
            signature = f.read()
        
        # Debug information
        print(f"  File size: {len(file_data)} bytes")
        print(f"  Signature size: {len(signature)} bytes")
        print(f"  File hash (SHA256): {hashlib.sha256(file_data).hexdigest()[:16]}...")
        
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
        return True
        
    except Exception as e:
        from cryptography.exceptions import InvalidSignature
        if isinstance(e, InvalidSignature):
            print(f"Signature verification failed: Invalid signature")
        else:
            print(f"Signature verification failed: {e}")
        return False

def get_file_hash(file_path):
    """Get SHA256 hash of a file"""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def extract_version(file_path):
    """Extract version from lightscope_core_mac.py"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            import re
            match = re.search(r'ls_version\s*=\s*["\']([^"\']+)["\']', content)
            if match:
                return match.group(1)
    except Exception as e:
        print(f"Error extracting version: {e}")
    return None

def create_version_info(file_path, version):
    """Create version information JSON for macOS"""
    file_hash = get_file_hash(file_path)
    
    version_info = {
        "version": version,
        "sha256": file_hash,
        "filename": "lightscope_core_mac.py",
        "download_url": "https://thelightscope.com/latest/lightscope_core_mac.py",
        "signature_url": "https://thelightscope.com/latest/lightscope_core_mac.py.sig",
        "public_key_url": "https://thelightscope.com/latest/public-key",
        "version_url": "https://thelightscope.com/latest/version_mac",
        "release_notes": f"LightScope macOS version {version}",
        "minimum_runner_version": "1.0.0",
        "platform": "macOS"
    }
    
    return version_info

# Main execution
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sign LightScope macOS core files")
    parser.add_argument("--private-key", default="lightscope-private.pem",
                       help="Path to private key file")
    parser.add_argument("--public-key", default="lightscope-public.pem",
                       help="Path to public key file")
    parser.add_argument("--core-file", default="lightscope/lightscope_core_mac.py",
                       help="Path to lightscope_core_mac.py file")
    parser.add_argument("--output-dir", default="upload",
                       help="Output directory for signed files")
    parser.add_argument("--verify", action="store_true", default=True,
                       help="Verify signature after signing")
    
    args = parser.parse_args()
    
    # Create output directory (remove and recreate to ensure clean state)
    output_dir = Path(args.output_dir)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Check if core file exists
    if not Path(args.core_file).exists():
        print(f"Error: {args.core_file} not found")
        sys.exit(1)
    
    # Check if private key exists
    if not Path(args.private_key).exists():
        print(f"Error: Private key {args.private_key} not found")
        sys.exit(1)
    
    # Load private key
    private_key = load_private_key(args.private_key)
    if not private_key:
        sys.exit(1)
    
    # Extract version
    version = extract_version(args.core_file)
    if not version:
        print("Error: Could not extract version from core file")
        sys.exit(1)
    
    print(f"Signing LightScope macOS v{version}...")
    
    # Copy core file to output directory
    output_core = output_dir / "lightscope_core_mac.py"
    shutil.copy2(args.core_file, output_core)
    
    # Sign the file
    signature_path = output_dir / "lightscope_core_mac.py.sig"
    if not sign_file(output_core, private_key, signature_path):
        sys.exit(1)
    
    # Copy public key to output directory
    shutil.copy2(args.public_key, output_dir / "lightscope-public.pem")
    
    # Create version info (macOS-specific)
    version_info = create_version_info(output_core, version)
    version_file = output_dir / "version_mac"
    with open(version_file, 'w') as f:
        json.dump(version_info, f, indent=2)
    
    print(f"macOS version info created: {version_file}")
    
    # Also create a copy of the ZIP package in upload directory
    zip_files = list(Path(".").glob("LightScope-*-macOS.zip"))
    if zip_files:
        latest_zip = max(zip_files, key=lambda p: p.stat().st_mtime)
        zip_output = output_dir / latest_zip.name
        shutil.copy2(latest_zip, zip_output)
        print(f"Added macOS package: {zip_output}")
    
    # Verify signature if requested
    if args.verify:
        print("Verifying signature...")
        if not verify_signature(output_core, signature_path, args.public_key):
            sys.exit(1)
    
    print("\nmacOS signing complete!")
    print(f"Files ready for distribution in: {output_dir}")
    print("Files created:")
    print(f"  - lightscope_core_mac.py (signed macOS core file)")
    print(f"  - lightscope_core_mac.py.sig (signature)")
    print(f"  - lightscope-public.pem (public key)")
    print(f"  - version_mac (macOS version information)")
    if zip_files:
        print(f"  - {latest_zip.name} (macOS installer package)")
    
    print("\n✅ macOS distribution files ready!")
EOF

# Run the macOS signing script
python3 sign-mac-distribution.py --verify

# Clean up temporary signing script
rm sign-mac-distribution.py

echo ""
echo "5. Upload directory created:"
ls -la upload/

echo ""
echo "=== Distribution Complete ==="
echo ""
echo "📦 DEPLOYMENT INSTRUCTIONS FOR macOS 📦"
echo "=============================================="
echo ""
echo "Files created for distribution:"
echo "  1. upload/ directory - Contains all macOS distribution files"
echo "  2. LightScope-$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core_mac.py | sed 's/ls_version = "\(.*\)"/\1/')-macOS.zip - Complete macOS installer package"
echo ""
echo "🚀 SERVER UPLOAD LOCATIONS:"
echo "=============================================="
echo ""
echo "ALL macOS FILES GO TO: 📁 /var/www/lightscope/latest/"
echo ""
echo "   ├── lightscope_core_mac.py           → https://thelightscope.com/latest/lightscope_core_mac.py"
echo "   ├── lightscope_core_mac.py.sig       → https://thelightscope.com/latest/lightscope_core_mac.py.sig"
echo "   ├── public-key                       → https://thelightscope.com/latest/public-key"
echo "   ├── version_mac                      → https://thelightscope.com/latest/version_mac"
echo "   └── LightScope-$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core_mac.py | sed 's/ls_version = "\(.*\)"/\1/')-macOS.zip → https://thelightscope.com/latest/LightScope-$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core_mac.py | sed 's/ls_version = "\(.*\)"/\1/')-macOS.zip"
echo ""
echo "📋 UPLOAD COMMANDS:"
echo "=============================================="
echo ""
echo "# Upload macOS-specific files:"
echo "scp upload/lightscope_core_mac.py \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope_core_mac.py.sig \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/lightscope-public.pem \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/public-key"
echo "scp upload/version_mac \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo "scp upload/LightScope-*-macOS.zip \${SERVER_USER}@\${SERVER_HOST}:/var/www/lightscope/latest/"
echo ""
echo "🧪 TESTING DEPLOYMENT:"
echo "=============================================="
echo ""
echo "# Test macOS endpoints:"
echo "curl https://thelightscope.com/latest/version_mac"
echo "curl https://thelightscope.com/latest/public-key"
echo "curl https://thelightscope.com/latest/lightscope_core_mac.py"
echo "curl https://thelightscope.com/latest/lightscope_core_mac.py.sig"
echo "curl https://thelightscope.com/latest/LightScope-$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core_mac.py | sed 's/ls_version = "\(.*\)"/\1/')-macOS.zip"
echo ""
echo "✅ macOS package ready for distribution!"

echo ""
echo "🚀 AUTOMATED DEPLOYMENT TO SERVER"
echo "=============================================="
echo ""

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass for password authentication..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install hudochenkov/sshpass/sshpass
        else
            echo "Please install Homebrew or manually install sshpass"
            echo "You can upload manually using the commands above"
            exit 0
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y sshpass
    fi
fi

SERVER_USER_HOST="kapitans@lightscope.isi.edu"

echo "Enter password for ${SERVER_USER_HOST}:"
read -s SERVER_PASSWORD

echo ""
echo "📤 Uploading macOS files to server..."

# Upload individual files
echo "Uploading lightscope_core_mac.py..."
sshpass -p "$SERVER_PASSWORD" scp upload/lightscope_core_mac.py ${SERVER_USER_HOST}:/var/www/lightscope/latest/

echo "Uploading lightscope_core_mac.py.sig..."
sshpass -p "$SERVER_PASSWORD" scp upload/lightscope_core_mac.py.sig ${SERVER_USER_HOST}:/var/www/lightscope/latest/

echo "Uploading public key..."
sshpass -p "$SERVER_PASSWORD" scp upload/lightscope-public.pem ${SERVER_USER_HOST}:/var/www/lightscope/latest/public-key

echo "Uploading macOS version info..."
sshpass -p "$SERVER_PASSWORD" scp upload/version_mac ${SERVER_USER_HOST}:/var/www/lightscope/latest/

echo "Uploading macOS installer package..."
sshpass -p "$SERVER_PASSWORD" scp upload/LightScope-*-macOS.zip ${SERVER_USER_HOST}:/var/www/lightscope/latest/

echo ""
echo "🔧 Setting proper permissions on server..."

# Set permissions script
sshpass -p "$SERVER_PASSWORD" ssh ${SERVER_USER_HOST} "
sudo bash -c '
    echo \"Setting proper permissions for macOS files...\"
    chown -R www-data:www-data /var/www/lightscope/latest/
    chmod -R 644 /var/www/lightscope/latest/*
    echo \"macOS deployment complete!\"
    ls -la /var/www/lightscope/latest/lightscope_core_mac.*
    ls -la /var/www/lightscope/latest/version_mac
    ls -la /var/www/lightscope/latest/LightScope-*-macOS.zip 2>/dev/null || echo \"macOS ZIP package not found\"
'
"

echo ""
echo "✅ macOS DEPLOYMENT COMPLETE!"
echo ""
echo "🧪 You can now test the macOS deployment:"
echo "curl https://thelightscope.com/latest/version_mac"
echo "curl https://thelightscope.com/latest/lightscope_core_mac.py"
echo "curl https://thelightscope.com/latest/lightscope_core_mac.py.sig"
echo ""
echo "🎉 macOS LightScope package is now available for secure auto-updates!" 