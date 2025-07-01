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
        
        print(f"File signed successfully: {signature_path}")
        return True
        
    except Exception as e:
        print(f"Error signing file: {e}")
        return False

def verify_signature(file_path, signature_path, public_key_path):
    """Verify a signature (for testing)"""
    try:
        # Load public key
        with open(public_key_path, 'rb') as f:
            public_key = serialization.load_pem_public_key(f.read())
        
        # Read file and signature
        with open(file_path, 'rb') as f:
            file_data = f.read()
        
        with open(signature_path, 'rb') as f:
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
        return True
        
    except Exception as e:
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
    """Upload the tar.gz archive to the server via SCP"""
    import subprocess
    
    tar_file = f"lightscope_v{version}_upload.tar.gz"
    
    # Prompt for server credentials
    print("\n📤 Server Upload Configuration")
    print("=" * 40)
    server_user = input("Enter server username (e.g., user): ").strip()
    server_host = input("Enter server hostname (e.g., serveru): ").strip()
    remote_path = input("Enter remote path (e.g., path): ").strip()
    
    # Ensure remote path ends with a slash if it's not empty
    if remote_path and not remote_path.endswith('/'):
        remote_path += '/'
    
    remote_host = f"{server_user}@{server_host}"
    
    print(f"\nUploading {tar_file} to {remote_host}:{remote_path}")
    print("Please enter your password when prompted...")
    
    try:
        # Use scp to upload the file, allowing interactive password prompt
        result = subprocess.run([
            "scp", 
            tar_file,
            f"{remote_host}:{remote_path}"
        ], check=True)
        
        print(f"✅ Successfully uploaded {tar_file} to server!")
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to upload file: {e}")
        print("You can manually upload later using:")
        print(f"scp {tar_file} {remote_host}:{remote_path}")
    except FileNotFoundError:
        print("❌ scp command not found. Please install OpenSSH client.")
        print("You can manually upload later using:")
        print(f"scp {tar_file} {remote_host}:{remote_path}")

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
    
    # Copy .deb package to output directory if it exists
    deb_file = Path(f"lightscope_{version}_amd64.deb")
    if deb_file.exists():
        deb_output = output_dir / deb_file.name
        shutil.copy2(deb_file, deb_output)
        print(f"Added .deb package: {deb_output}")
    else:
        print(f"Warning: .deb package not found: {deb_file}")
    
    # Copy .rpm package to output directory if it exists (look for any matching pattern)
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
        print(f"Warning: .rpm package not found: {rpm_pattern}")
    
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
    deb_file = output_dir / f"lightscope_{version}_amd64.deb"
    if deb_file.exists():
        print(f"  - {deb_file.name} (Debian package)")
    
    # Look for any RPM files in output directory
    import glob
    rpm_files = glob.glob(str(output_dir / f"lightscope-{version}-*.noarch.rpm"))
    for rpm_file in rpm_files:
        rpm_name = Path(rpm_file).name
        print(f"  - {rpm_name} (RPM package)")
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