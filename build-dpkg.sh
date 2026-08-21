#!/bin/bash
set -e

# Build script for LightScope Debian package

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/debian_package"
BUILD_DIR="$SCRIPT_DIR/build"
PACKAGE_NAME="lightscope"

# Get version from lightscope_core.py
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from lightscope_core.py"
    exit 1
fi

echo "Building LightScope v$VERSION dpkg package..."

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy package structure
cp -r "$PACKAGE_DIR"/* "$BUILD_DIR/"

# Copy the actual lightscope_core.py to the package (overwrite template version)
mkdir -p "$BUILD_DIR/opt/lightscope/bin"
echo "Copying lightscope/lightscope_core.py (v$VERSION) to build directory..."
cp lightscope/lightscope_core.py "$BUILD_DIR/opt/lightscope/bin/"

# Copy the actual lightscope-runner.py to the package (overwrite template version)
echo "Copying lightscope/lightscope-runner.py to build directory..."
cp lightscope/lightscope-runner.py "$BUILD_DIR/opt/lightscope/bin/"

# Get runner version for logging
RUNNER_VERSION=$(grep -o 'runner_version = "[^"]*"' "$BUILD_DIR/opt/lightscope/bin/lightscope-runner.py" | sed 's/runner_version = "\(.*\)"/\1/')
if [ -n "$RUNNER_VERSION" ]; then
    echo "Runner version: $RUNNER_VERSION"
else
    echo "Warning: Could not extract runner version"
fi

# Copy the public key to the package (try both naming conventions)
echo "Copying public key to build directory..."
mkdir -p "$BUILD_DIR/opt/lightscope/config"
if [ -f "lightscope-public.pem" ]; then
    cp lightscope-public.pem "$BUILD_DIR/opt/lightscope/config/lightscope-public.pem"
    echo "✅ Successfully copied lightscope-public.pem"
elif [ -f "lightscope_public.pem" ]; then
    cp lightscope_public.pem "$BUILD_DIR/opt/lightscope/config/lightscope-public.pem"
    echo "✅ Successfully copied lightscope_public.pem (renamed to lightscope-public.pem)"
else
    echo "Warning: Public key not found (lightscope-public.pem or lightscope_public.pem)"
    echo "The package will build but signature verification will not work without the public key"
fi

# Verify the copy worked
BUILT_VERSION=$(grep -o 'ls_version = "[^"]*"' "$BUILD_DIR/opt/lightscope/bin/lightscope_core.py" | sed 's/ls_version = "\(.*\)"/\1/')
echo "Verified built version: $BUILT_VERSION"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "ERROR: Version mismatch! Expected $VERSION, got $BUILT_VERSION"
    exit 1
fi

# Copy python-libpcap directory for local installation
if [ -d "python-libpcap" ]; then
    echo "Copying python-libpcap directory..."
    cp -r python-libpcap "$BUILD_DIR/opt/lightscope/"
else
    echo "Warning: python-libpcap directory not found"
fi

# Explicitly set the honeypot default in the (throwaway) build copy of the postinst
# config template. Always set it rather than only flipping yes->no so the result
# never depends on whatever the template currently says.
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    HONEYPOT_DEFAULT="no"
    echo "LIGHTSCOPE_NO_HONEYPOT=1 detected: building no-honeypot package"
else
    HONEYPOT_DEFAULT="yes"
    echo "Building standard package (honeypots enabled)"
fi
for f in "$BUILD_DIR/DEBIAN/postinst" "$BUILD_DIR/usr/share/lightscope/config.ini.example"; do
    [ -f "$f" ] || continue
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^honeypots = .*/honeypots = $HONEYPOT_DEFAULT/" "$f"
    else
        sed -i "s/^honeypots = .*/honeypots = $HONEYPOT_DEFAULT/" "$f"
    fi
done
if ! grep -q "^honeypots = $HONEYPOT_DEFAULT\$" "$BUILD_DIR/DEBIAN/postinst"; then
    echo "ERROR: postinst config template does not set honeypots = $HONEYPOT_DEFAULT"
    exit 1
fi
echo "Verified: postinst config template sets honeypots = $HONEYPOT_DEFAULT"

# Update version in control file
# Handle macOS vs Linux sed differences
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS requires backup extension
    sed -i '' "s/Version: .*/Version: $VERSION/" "$BUILD_DIR/DEBIAN/control"
else
    # Linux sed
    sed -i "s/Version: .*/Version: $VERSION/" "$BUILD_DIR/DEBIAN/control"
fi

# Set proper permissions
chmod 755 "$BUILD_DIR/DEBIAN/postinst"
chmod 755 "$BUILD_DIR/DEBIAN/prerm"
chmod 755 "$BUILD_DIR/DEBIAN/postrm"
chmod 755 "$BUILD_DIR/opt/lightscope/bin/lightscope-runner.py"
chmod 644 "$BUILD_DIR/opt/lightscope/bin/lightscope_core.py"
chmod 644 "$BUILD_DIR/lib/systemd/system/lightscope.service"
chmod 644 "$BUILD_DIR/usr/share/lightscope/config.ini.example"
# Set permissions for public key if it exists
if [ -f "$BUILD_DIR/opt/lightscope/config/lightscope-public.pem" ]; then
    chmod 644 "$BUILD_DIR/opt/lightscope/config/lightscope-public.pem"
fi

# Build the package
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    OUTPUT_FILE="${PACKAGE_NAME}-nohoneypot_${VERSION}_all.deb"
else
    OUTPUT_FILE="${PACKAGE_NAME}_${VERSION}_all.deb"
fi
echo "Creating package: $OUTPUT_FILE"

dpkg-deb --build "$BUILD_DIR" "$OUTPUT_FILE"

echo "Package built successfully: $OUTPUT_FILE"

# Optional: Run lintian to check for common issues
if command -v lintian &> /dev/null; then
    echo "Running lintian checks..."
    lintian "$OUTPUT_FILE" || echo "Warning: lintian found issues (not fatal)"
fi

echo "Build complete!"
echo "To install: sudo dpkg -i $OUTPUT_FILE"
echo "To remove: sudo dpkg -r $PACKAGE_NAME" 