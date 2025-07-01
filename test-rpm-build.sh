#!/bin/bash
set -e

echo "=== LightScope RPM Build Prerequisites Test ==="

# Check if we're in the right directory
if [ ! -f "lightscope/lightscope_core.py" ]; then
    echo "❌ Error: Please run this script from the thelightscope directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

echo "✅ Found lightscope_core.py"

# Extract version
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from lightscope_core.py"
    exit 1
fi

echo "✅ Version detected: $VERSION"

# Check for rpmbuild
if command -v rpmbuild &> /dev/null; then
    echo "✅ rpmbuild is available"
    rpmbuild --version
else
    echo "⚠️  rpmbuild not found - install with:"
    echo "   macOS: brew install rpm"
    echo "   Fedora/RHEL: sudo dnf install rpm-build"
    echo "   Ubuntu/Debian: sudo apt install rpm"
fi

# Check for rpm (for package inspection)
if command -v rpm &> /dev/null; then
    echo "✅ rpm is available"
else
    echo "⚠️  rpm not found - install with same commands as rpmbuild"
fi

# Check build script exists
if [ -f "build-rpm.sh" ]; then
    echo "✅ build-rpm.sh exists"
    if [ -x "build-rpm.sh" ]; then
        echo "✅ build-rpm.sh is executable"
    else
        echo "⚠️  build-rpm.sh is not executable - run: chmod +x build-rpm.sh"
    fi
else
    echo "❌ build-rpm.sh not found"
fi

# Check comprehensive script exists
if [ -f "rpm_build_all_upload.sh" ]; then
    echo "✅ rpm_build_all_upload.sh exists"
    if [ -x "rpm_build_all_upload.sh" ]; then
        echo "✅ rpm_build_all_upload.sh is executable"
    else
        echo "⚠️  rpm_build_all_upload.sh is not executable - run: chmod +x rpm_build_all_upload.sh"
    fi
else
    echo "❌ rpm_build_all_upload.sh not found"
fi

echo ""
echo "📋 NEXT STEPS:"
echo "=============="

if command -v rpmbuild &> /dev/null; then
    echo "🚀 Ready to build! Run:"
    echo "   ./build-rpm.sh                    # Build RPM package only"
    echo "   ./rpm_build_all_upload.sh         # Build, sign, and prepare for upload"
else
    echo "📦 Install RPM build tools first:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   brew install rpm"
    elif command -v dnf &> /dev/null; then
        echo "   sudo dnf install rpm-build rpm-sign"
    elif command -v yum &> /dev/null; then
        echo "   sudo yum install rpm-build rpm-sign"
    elif command -v apt &> /dev/null; then
        echo "   sudo apt install rpm"
    else
        echo "   Install rpm-build package for your distribution"
    fi
    echo ""
    echo "   Then run: ./rpm_build_all_upload.sh"
fi

echo ""
echo "✅ RPM build system ready!" 