#!/bin/bash
set -e

# Build script for LightScope RPM package

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_BUILD_DIR="$SCRIPT_DIR/rpm-build"
PACKAGE_NAME="lightscope"

# Get version from lightscope_core.py
VERSION=$(grep -o 'ls_version = "[^"]*"' lightscope/lightscope_core.py | sed 's/ls_version = "\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from lightscope_core.py"
    exit 1
fi

echo "Building LightScope v$VERSION RPM package..."

# Create necessary directories
mkdir -p "$RPM_BUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy the actual lightscope_core.py to SOURCES (overwrite any existing version)
echo "Copying lightscope/lightscope_core.py (v$VERSION) to RPM SOURCES directory..."
cp lightscope/lightscope_core.py "$RPM_BUILD_DIR/SOURCES/"

# Verify the copy worked
BUILT_VERSION=$(grep -o 'ls_version = "[^"]*"' "$RPM_BUILD_DIR/SOURCES/lightscope_core.py" | sed 's/ls_version = "\(.*\)"/\1/')
echo "Verified SOURCES version: $BUILT_VERSION"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "ERROR: Version mismatch! Expected $VERSION, got $BUILT_VERSION"
    exit 1
fi

# Update version in spec file
# Handle macOS vs Linux sed differences
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS requires backup extension
    sed -i '' "s/Version:.*/Version: $VERSION/" "$RPM_BUILD_DIR/SPECS/lightscope.spec"
else
    # Linux sed
    sed -i "s/Version:.*/Version: $VERSION/" "$RPM_BUILD_DIR/SPECS/lightscope.spec"
fi

# Build the RPM
echo "Creating RPM package..."

rpmbuild --define "_topdir $RPM_BUILD_DIR" \
         --define "_builddir $RPM_BUILD_DIR/BUILD" \
         --define "_rpmdir $RPM_BUILD_DIR/RPMS" \
         --define "_sourcedir $RPM_BUILD_DIR/SOURCES" \
         --define "_specdir $RPM_BUILD_DIR/SPECS" \
         --define "_srcrpmdir $RPM_BUILD_DIR/SRPMS" \
         --define "_build_os linux" \
         --define "_target_os linux" \
         --define "_buildhost linux-builder" \
         -bb "$RPM_BUILD_DIR/SPECS/lightscope.spec"

# Find the actual RPM file that was created (it may include dist tag like .el10, .fc39, etc.)
ACTUAL_RPM=$(find "$RPM_BUILD_DIR/RPMS/noarch/" -name "${PACKAGE_NAME}-${VERSION}-*.noarch.rpm" | head -1)

if [ -z "$ACTUAL_RPM" ]; then
    echo "ERROR: Could not find built RPM package"
    echo "Expected pattern: ${PACKAGE_NAME}-${VERSION}-*.noarch.rpm"
    echo "Files in RPMS/noarch/:"
    ls -la "$RPM_BUILD_DIR/RPMS/noarch/" || echo "Directory not found"
    exit 1
fi

# Get the actual filename for output
ACTUAL_FILENAME=$(basename "$ACTUAL_RPM")

# Move the built RPM to the current directory
mv "$ACTUAL_RPM" .

echo "RPM package built successfully: $ACTUAL_FILENAME"
echo "Build complete!"
echo "To install: sudo rpm -i $ACTUAL_FILENAME"
echo "To remove: sudo rpm -e $PACKAGE_NAME" 