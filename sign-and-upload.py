#!/usr/bin/env python3
"""
Code Signing and Upload Script for LightScope
This script signs the lightscope_core.py file and prepares it for secure distribution.
"""

import os
import sys
import json
import hashlib
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
import argparse

def generate_key_pair(private_key_path, public_key_path):
    """Generate a new RSA key pair for signing"""
    print("Generating new RSA key pair...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=4096,
    )
    
    # Get public key
    public_key = private_key.public_key()
    
    # Serialize private key
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()  # For simplicity, no password
    )
    
    # Serialize public key
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    
    # Save keys
    with open(private_key_path, 'wb') as f:
        f.write(private_pem)
    
    with open(public_key_path, 'wb') as f:
        f.write(public_pem)
    
    # Set restrictive permissions on private key
    os.chmod(private_key_path, 0o600)
    os.chmod(public_key_path, 0o644)
    
    print(f"Private key saved to: {private_key_path}")
    print(f"Public key saved to: {public_key_path}")

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
        if not Path(file_path).exists():
            print(f"Error: File to verify not found: {file_path}")
            return False
        
        if not Path(signature_path).exists():
            print(f"Error: Signature file not found: {signature_path}")
            return False
        
        if not Path(public_key_path).exists():
            print(f"Error: Public key file not found: {public_key_path}")
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
        print(f"  Public key size: {len(public_key_data)} bytes")
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
            print(f"  This means the file was modified after signing OR wrong key pair")
        else:
            print(f"Signature verification failed: {e}")
            print(f"  Exception type: {type(e).__name__}")
        print(f"  File: {file_path}")
        print(f"  Signature: {signature_path}")
        print(f"  Public key: {public_key_path}")
        return False

def get_file_hash(file_path):
    """Get SHA256 hash of a file"""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def extract_version(file_path):
    """Extract version from lightscope_core.py"""
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
    """Create version information JSON"""
    file_hash = get_file_hash(file_path)
    
    version_info = {
        "version": version,
        "sha256": file_hash,
        "filename": "lightscope_core.py",
        "download_url": "https://thelightscope.com/latest/lightscope_core.py",
        "signature_url": "https://thelightscope.com/latest/lightscope_core.py.sig",
        "public_key_url": "https://thelightscope.com/latest/public-key",
        "version_url": "https://thelightscope.com/latest/version",
        "release_notes": f"LightScope version {version}",
        "minimum_runner_version": "1.0.0"
    }
    
    return version_info

def create_archives(upload_dir, version):
    """Create tar.gz and zip archives of the upload directory"""
    import tarfile
    import zipfile
    import shutil
    
    upload_path = Path(upload_dir)
    base_name = f"lightscope_v{version}_upload"
    
    # Create tar.gz archive
    tar_path = Path(f"{base_name}.tar.gz")
    with tarfile.open(tar_path, "w:gz") as tar:
        tar.add(upload_path, arcname=upload_path.name)
    print(f"Created tar.gz archive: {tar_path}")
    
    # Create zip archive
    zip_path = Path(f"{base_name}.zip")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for file_path in upload_path.rglob('*'):
            if file_path.is_file():
                # Create relative path for archive
                arcname = Path(upload_path.name) / file_path.relative_to(upload_path)
                zipf.write(file_path, arcname)
    print(f"Created zip archive: {zip_path}")

def upload_to_server(version):
    """Upload the tar.gz archive to the server via SCP and deploy with sudo"""
    import subprocess
    import getpass

    tar_file = f"lightscope_v{version}_upload.tar.gz"

    # Server configuration
    server_user = "kapitans"
    server_host = "lightscope.isi.edu"
    remote_path = "/var/www/lightscope/latest/"
    remote_host = f"{server_user}@{server_host}"

    print("\n📤 Server Upload Configuration")
    print("=" * 40)
    print(f"Server: {remote_host}")
    print(f"Target: {remote_path}")

    # Check if sshpass is available for automated deployment
    sshpass_available = subprocess.run(["which", "sshpass"], capture_output=True).returncode == 0

    if not sshpass_available:
        print("\n❌ sshpass is not installed.")
        print("Install it with: brew install hudochenkov/sshpass/sshpass")
        print("\nManual deployment:")
        print(f"  scp {tar_file} {remote_host}:~/")
        print(f"  ssh {remote_host}")
        print(f"  sudo mv ~/{tar_file} {remote_path}")
        print(f"  cd {remote_path} && sudo tar -xzf {tar_file}")
        print(f"  sudo mv upload/* . && sudo rm -rf upload {tar_file}")
        print(f"  sudo chown -R www-data:www-data {remote_path}")
        sys.exit(1)

    print(f"\nEnter password for {remote_host}:")
    password = getpass.getpass()

    if not password:
        print("❌ No password provided. Aborting.")
        sys.exit(1)

    # Step 1: Upload to home directory
    print(f"\n📤 Step 1: Uploading {tar_file} to home directory...")

    result = subprocess.run([
        "sshpass", "-p", password,
        "scp", "-o", "BatchMode=no", "-o", "NumberOfPasswordPrompts=1",
        tar_file, f"{remote_host}:~/"
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"❌ Upload failed (exit code {result.returncode})")
        if "Permission denied" in result.stderr or "password" in result.stderr.lower():
            print("   Authentication failed - check your password")
        else:
            print(f"   Error: {result.stderr.strip()}")
        sys.exit(1)

    print(f"✅ Uploaded {tar_file} to home directory")

    # Step 2: SSH in and deploy with sudo
    print(f"\n🔧 Step 2: Deploying on remote server...")

    deploy_script = f'''
echo "Moving archive to /tmp..."
mv ~/{tar_file} /tmp/

echo "Deploying with sudo..."
sudo bash -c '
    echo "Moving archive to target directory..."
    mv /tmp/{tar_file} {remote_path}

    echo "Changing to target directory..."
    cd {remote_path}

    echo "Extracting archive..."
    tar -xzf {tar_file}

    echo "Moving contents from upload directory..."
    if [ -d upload ]; then
        mv upload/* . 2>/dev/null || echo "No files in upload directory"
        rm -rf upload/
    fi

    echo "Cleaning up archive..."
    rm -f {tar_file}

    echo "Setting proper permissions..."
    chown -R www-data:www-data {remote_path}
    chmod -R 644 {remote_path}* 2>/dev/null || true

    echo "Final directory contents:"
    ls -la {remote_path}
'
echo "Deployment complete!"
'''

    result = subprocess.run([
        "sshpass", "-p", password,
        "ssh", "-o", "NumberOfPasswordPrompts=1",
        "-t", remote_host, deploy_script
    ])

    if result.returncode != 0:
        print(f"\n❌ Deployment failed (exit code {result.returncode})")
        # Try to clean up the uploaded file
        subprocess.run([
            "sshpass", "-p", password,
            "ssh", remote_host, f"rm -f ~/{tar_file}"
        ], capture_output=True)
        sys.exit(1)

    print(f"\n✅ Deployment complete!")
    print(f"\n🧪 Test the deployment:")
    print(f"curl https://thelightscope.com/latest/version")
    print(f"curl https://thelightscope.com/latest/public-key")

def main():
    parser = argparse.ArgumentParser(description="Sign LightScope core files")
    parser.add_argument("--generate-keys", action="store_true", 
                       help="Generate new key pair")
    parser.add_argument("--private-key", default="lightscope-private.pem",
                       help="Path to private key file")
    parser.add_argument("--public-key", default="lightscope-public.pem",
                       help="Path to public key file")
    parser.add_argument("--core-file", default="lightscope/lightscope_core.py",
                       help="Path to lightscope_core.py file")
    parser.add_argument("--output-dir", default="upload",
                       help="Output directory for signed files")
    parser.add_argument("--verify", action="store_true",
                       help="Verify signature after signing")
    parser.add_argument("--no-upload", action="store_true",
                       help="Skip uploading to server via SCP")
    parser.add_argument("--package-type", choices=["deb", "rpm", "arch", "all"], default="all",
                       help="Which package type to include (default: all)")
    
    args = parser.parse_args()
    
    # Create output directory (remove and recreate to ensure clean state)
    output_dir = Path(args.output_dir)
    if output_dir.exists():
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Generate keys if requested
    if args.generate_keys:
        generate_key_pair(args.private_key, args.public_key)
        return
    
    # Check if core file exists
    if not Path(args.core_file).exists():
        print(f"Error: {args.core_file} not found")
        sys.exit(1)
    
    # Check if private key exists
    if not Path(args.private_key).exists():
        print(f"Error: Private key {args.private_key} not found")
        print("Use --generate-keys to create a new key pair")
        sys.exit(1)
    
    # Load private key
    private_key = load_private_key(args.private_key)
    if not private_key:
        sys.exit(1)
    
    # Verify that private and public keys match
    print("Verifying key pair compatibility...")
    try:
        # Load public key
        with open(args.public_key, 'rb') as f:
            public_key = serialization.load_pem_public_key(f.read())
        
        # Test with a simple message
        test_message = b"test message for key verification"
        test_signature = private_key.sign(
            test_message,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        # Verify the test signature
        public_key.verify(
            test_signature,
            test_message,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        print("✅ Key pair verification successful - private and public keys match")
        
    except Exception as e:
        print(f"❌ Key pair verification failed: {e}")
        print("The private and public keys do not match!")
        sys.exit(1)
    
    # Extract version
    version = extract_version(args.core_file)
    if not version:
        print("Error: Could not extract version from core file")
        sys.exit(1)
    
    print(f"Signing LightScope v{version}...")
    
    # Copy core file to output directory
    import shutil
    output_core = output_dir / "lightscope_core.py"
    shutil.copy2(args.core_file, output_core)
    
    # Sign the file
    signature_path = output_dir / "lightscope_core.py.sig"
    if not sign_file(output_core, private_key, signature_path):
        sys.exit(1)
    
    # Copy public key to output directory
    shutil.copy2(args.public_key, output_dir / "lightscope-public.pem")
    
    # Copy .deb package to output directory if it exists and requested
    if args.package_type in ["deb", "all"]:
        deb_file = Path(f"lightscope_{version}_all.deb")
        if deb_file.exists():
            deb_output = output_dir / deb_file.name
            shutil.copy2(deb_file, deb_output)
            print(f"Added .deb package: {deb_output}")
        else:
            print(f"Note: .deb package not found: {deb_file}")

    # Copy .rpm package to output directory if it exists and requested
    if args.package_type in ["rpm", "all"]:
        import glob
        rpm_pattern = f"lightscope-{version}-*.noarch.rpm"
        rpm_files = glob.glob(rpm_pattern)

        if rpm_files:
            # Use the first matching RPM file (there should only be one)
            rpm_file = Path(rpm_files[0])
            rpm_output = output_dir / rpm_file.name
            shutil.copy2(rpm_file, rpm_output)
            print(f"Added .rpm package: {rpm_output}")
        else:
            print(f"Note: .rpm package not found: {rpm_pattern}")

    # Copy Arch Linux package to output directory if it exists and requested
    if args.package_type in ["arch", "all"]:
        import glob
        # Try to find .pkg.tar.zst or .pkg.tar.xz files (Arch package formats)
        arch_patterns = [
            f"lightscope-{version}-*.pkg.tar.zst",
            f"lightscope-{version}-*.pkg.tar.xz",
            f"lightscope-{version}-*.pkg.tar.*",
            f"*-arch-src.tar.gz"  # Source tarball for building on Arch
        ]

        arch_found = False
        for pattern in arch_patterns:
            arch_files = glob.glob(pattern)
            if arch_files:
                arch_file = Path(arch_files[0])
                arch_output = output_dir / arch_file.name
                shutil.copy2(arch_file, arch_output)
                print(f"Added Arch Linux package: {arch_output}")
                arch_found = True
                break

        if not arch_found:
            print(f"Note: Arch Linux package not found")
    
    # Create version info
    version_info = create_version_info(output_core, version)
    version_file = output_dir / "version"
    with open(version_file, 'w') as f:
        json.dump(version_info, f, indent=2)
    
    print(f"Version info created: {version_file}")
    
    # Verify signature if requested
    if args.verify:
        print("Verifying signature...")
        if not verify_signature(output_core, signature_path, args.public_key):
            sys.exit(1)
    
    # Create archives
    print("Creating distribution archives...")
    create_archives(output_dir, version)
    
    print("\nSigning complete!")
    print(f"Files ready for distribution in: {output_dir}")
    print("Files created:")
    print(f"  - lightscope_core.py (signed file)")
    print(f"  - lightscope_core.py.sig (signature)")
    print(f"  - lightscope-public.pem (public key)")
    print(f"  - version (version information)")
    
    # List package files if they exist
    deb_file = output_dir / f"lightscope_{version}_all.deb"
    if deb_file.exists():
        print(f"  - {deb_file.name} (Debian package)")

    # Look for any RPM files in output directory
    import glob
    rpm_files = glob.glob(str(output_dir / f"lightscope-{version}-*.noarch.rpm"))
    for rpm_file in rpm_files:
        rpm_name = Path(rpm_file).name
        print(f"  - {rpm_name} (RPM package)")

    # Look for any Arch Linux packages in output directory
    arch_patterns = [
        str(output_dir / f"lightscope-{version}-*.pkg.tar.*"),
        str(output_dir / f"*-arch-src.tar.gz")
    ]
    for pattern in arch_patterns:
        arch_files = glob.glob(pattern)
        for arch_file in arch_files:
            arch_name = Path(arch_file).name
            print(f"  - {arch_name} (Arch Linux package)")
    print("\nArchives created:")
    print(f"  - lightscope_v{version}_upload.tar.gz")
    print(f"  - lightscope_v{version}_upload.zip")
    
    # Upload to server via SCP (unless disabled)
    if not args.no_upload:
        upload_to_server(version)
    else:
        print("\n⏭️  Skipping server upload (--no-upload specified)")
    
    print("\nNext steps:")
    print("1. All files now go to: https://thelightscope.com/latest/")
    print("2. Upload lightscope_core.py and lightscope_core.py.sig")
    print("3. Upload version as 'version' endpoint")
    print("4. Upload public key as 'public-key' endpoint")

if __name__ == "__main__":
    main() 