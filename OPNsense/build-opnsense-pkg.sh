#!/bin/sh
#
# Build LightScope OPNsense package
# Run this script on FreeBSD/OPNsense
#

set -e

echo "=== LightScope OPNsense Package Builder ==="
echo ""

# Check if we're on FreeBSD
if [ "$(uname)" != "FreeBSD" ]; then
    echo "Error: This script must be run on FreeBSD/OPNsense"
    echo "Current OS: $(uname)"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "Makefile" ]; then
    echo "Error: Makefile not found. Run this from the opnsense directory"
    exit 1
fi

# Extract version
VERSION=$(grep "^PLUGIN_VERSION=" Makefile | cut -d'=' -f2 | tr -d '[:space:]')
echo "Building version: $VERSION"

# Clean previous builds
echo ""
echo "Cleaning previous builds..."
make clean 2>/dev/null || true
rm -rf work/

# Build the package
echo ""
echo "Building package..."
make package

# Find the built package
PKG_FILE=$(find work/pkg -name "*.pkg" 2>/dev/null | head -1)

if [ -z "$PKG_FILE" ]; then
    echo "Error: Package build failed - no .pkg file found"
    exit 1
fi

# Copy to current directory with standard name
cp "$PKG_FILE" "os-lightscope-${VERSION}.pkg"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Package: os-lightscope-${VERSION}.pkg"
ls -la "os-lightscope-${VERSION}.pkg"

echo ""
echo "Package info:"
pkg info -F "os-lightscope-${VERSION}.pkg" 2>/dev/null || echo "(pkg info not available)"

echo ""
echo "To install locally:"
echo "  pkg add os-lightscope-${VERSION}.pkg"
echo ""
echo "To sign and upload, copy the package to your build machine and run:"
echo "  ./opnsense_build_all_upload.sh"
