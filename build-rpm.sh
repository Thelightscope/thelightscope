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

# sed -i wrapper: macOS sed requires an explicit (empty) backup suffix
sedi() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

SPEC_SRC="$RPM_BUILD_DIR/SPECS/lightscope.spec"
BUILD_SPEC="$RPM_BUILD_DIR/SPECS/lightscope-build.spec"

# Update version in the tracked spec file (idempotent)
sedi "s/Version:.*/Version: $VERSION/" "$SPEC_SRC"

# The tracked spec is the canonical source and must always default to
# honeypots = yes. Older versions of this script flipped it to "no" IN PLACE
# for the no-honeypot build and never restored it, so every later "standard"
# build on that machine silently shipped with honeypots disabled. Repair it
# here if a previous run left it mutated.
if grep -q '^honeypots = no' "$SPEC_SRC"; then
    echo "WARNING: tracked spec had 'honeypots = no' left over from a previous no-honeypot build - restoring 'honeypots = yes'"
    sedi 's/^honeypots = .*/honeypots = yes/' "$SPEC_SRC"
fi

# Build from a throwaway copy of the spec so per-build changes never touch the tracked file
cp "$SPEC_SRC" "$BUILD_SPEC"
trap 'rm -f "$BUILD_SPEC"' EXIT

# Explicitly set the honeypot default for this build (never rely on the current file contents)
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    HONEYPOT_DEFAULT="no"
    echo "LIGHTSCOPE_NO_HONEYPOT=1 detected: building no-honeypot package"
else
    HONEYPOT_DEFAULT="yes"
    echo "Building standard package (honeypots enabled)"
fi
sedi "s/^honeypots = .*/honeypots = $HONEYPOT_DEFAULT/" "$BUILD_SPEC"

# Verify every honeypots line in the build spec (config.ini.example and the %post template) matches
HP_LINES=$(grep -c '^honeypots = ' "$BUILD_SPEC" || true)
HP_OK=$(grep -c "^honeypots = $HONEYPOT_DEFAULT\$" "$BUILD_SPEC" || true)
if [ "$HP_LINES" -eq 0 ] || [ "$HP_LINES" -ne "$HP_OK" ]; then
    echo "ERROR: build spec does not have honeypots = $HONEYPOT_DEFAULT on all $HP_LINES 'honeypots =' lines (matched: $HP_OK)"
    exit 1
fi
echo "Verified: $HP_OK/$HP_LINES config template(s) in build spec set honeypots = $HONEYPOT_DEFAULT"

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
         -bb "$BUILD_SPEC"

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

# If LIGHTSCOPE_NO_HONEYPOT is set, rename the output file to include -nohoneypot
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    ACTUAL_FILENAME=$(echo "$ACTUAL_FILENAME" | sed "s/^${PACKAGE_NAME}-/${PACKAGE_NAME}-nohoneypot-/")
fi

# Move the built RPM to the current directory with the final name
mv "$ACTUAL_RPM" "./$ACTUAL_FILENAME"

echo "RPM package built successfully: $ACTUAL_FILENAME"
echo "Build complete!"
echo "To install: sudo rpm -i $ACTUAL_FILENAME"
echo "To remove: sudo rpm -e $PACKAGE_NAME" 