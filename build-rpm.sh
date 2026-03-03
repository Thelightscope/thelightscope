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

# Copy the lightscope-runner.py script to SOURCES
echo "Copying lightscope/lightscope-runner.py to RPM SOURCES directory..."
if [ -f "lightscope/lightscope-runner.py" ]; then
    cp lightscope/lightscope-runner.py "$RPM_BUILD_DIR/SOURCES/lightscope_runner.py"
    echo "✅ Successfully copied lightscope-runner.py to SOURCES"
else
    echo "Error: lightscope/lightscope-runner.py not found!"
    exit 1
fi

# Verify the runner script copy
if [ -f "$RPM_BUILD_DIR/SOURCES/lightscope_runner.py" ]; then
    RUNNER_SIZE=$(stat -c%s "$RPM_BUILD_DIR/SOURCES/lightscope_runner.py")
    echo "✅ Runner script copied successfully (size: $RUNNER_SIZE bytes)"
else
    echo "Error: Runner script not found in SOURCES directory!"
    exit 1
fi

# Copy the public key to SOURCES (try both naming conventions)
echo "Copying public key to RPM SOURCES directory..."
if [ -f "lightscope-public.pem" ]; then
    cp lightscope-public.pem "$RPM_BUILD_DIR/SOURCES/lightscope-public.pem"
    echo "✅ Successfully copied lightscope-public.pem to SOURCES"
elif [ -f "lightscope_public.pem" ]; then
    cp lightscope_public.pem "$RPM_BUILD_DIR/SOURCES/lightscope-public.pem"
    echo "✅ Successfully copied lightscope_public.pem to SOURCES (renamed to lightscope-public.pem)"
else
    echo "Warning: Public key not found (lightscope-public.pem or lightscope_public.pem)"
    echo "The package will build but signature verification will not work without the public key"
fi

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

# If LIGHTSCOPE_NO_HONEYPOT is set, default honeypots to disabled in spec config templates
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    echo "LIGHTSCOPE_NO_HONEYPOT=1 detected: setting honeypots = no in spec config templates"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/^honeypots = yes/honeypots = no/' "$RPM_BUILD_DIR/SPECS/lightscope.spec"
    else
        sed -i 's/^honeypots = yes/honeypots = no/' "$RPM_BUILD_DIR/SPECS/lightscope.spec"
    fi
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

# If LIGHTSCOPE_NO_HONEYPOT is set, rename the output file to include -nohoneypot
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    NOHP_FILENAME=$(echo "$ACTUAL_FILENAME" | sed "s/^${PACKAGE_NAME}-/${PACKAGE_NAME}-nohoneypot-/")
    mv "$ACTUAL_FILENAME" "$NOHP_FILENAME"
    ACTUAL_FILENAME="$NOHP_FILENAME"
fi

echo "RPM package built successfully: $ACTUAL_FILENAME"
echo "Build complete!"
echo "To install: sudo rpm -i $ACTUAL_FILENAME"
echo "To remove: sudo rpm -e $PACKAGE_NAME" 