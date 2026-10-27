#!/bin/sh
#
# build-freebsd-pkg.sh - build the LightScope FreeBSD package
#
# Produces lightscope-<version>.pkg (or lightscope-nohoneypot-<version>.pkg)
# in the repository root. Counterpart of build-dpkg.sh / build-rpm.sh.
#
# Run on FreeBSD 13.x or 14.x (pkg(8) is part of the base system). Install the
# runtime dependencies on the build host first so their versions are recorded
# in the package manifest:
#
#   pkg install python311 py311-dpkt py311-psutil py311-requests \
#               py311-cryptography py311-packaging py311-pypcap
#
# Usage:
#   ./build-freebsd-pkg.sh                build the package
#   ./build-freebsd-pkg.sh --stage-only   only assemble build-freebsd/ (runs on any OS)
#
# Environment:
#   PYVER=311                 Python flavor to depend on
#                             (default: what the python3 metapackage uses, else 311)
#   LIGHTSCOPE_NO_HONEYPOT=1  build the no-honeypot variant (config default honeypots = no)
#
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_SRC="$SCRIPT_DIR/freebsd_package"
BUILD_DIR="$SCRIPT_DIR/build-freebsd"
STAGE="$BUILD_DIR/stage"
META="$BUILD_DIR/metadata"
PLIST="$BUILD_DIR/plist"
PREFIX="/usr/local"
LS_HOME="$PREFIX/lightscope"

STAGE_ONLY=0
if [ "${1:-}" = "--stage-only" ]; then
    STAGE_ONLY=1
fi

HAVE_PKG=0
if [ "$(uname)" = "FreeBSD" ] && command -v pkg >/dev/null 2>&1; then
    HAVE_PKG=1
fi
if [ "$STAGE_ONLY" -eq 0 ] && [ "$HAVE_PKG" -eq 0 ]; then
    echo "Error: building the package needs pkg(8) on FreeBSD (use --stage-only elsewhere)" >&2
    exit 1
fi

# ---- versions ------------------------------------------------------------------
VERSION=$(sed -n 's/^ls_version = "\([^"]*\)".*/\1/p' "$SCRIPT_DIR/lightscope/lightscope_core.py" | head -1)
if [ -z "$VERSION" ]; then
    echo "Error: could not extract ls_version from lightscope/lightscope_core.py" >&2
    exit 1
fi
RUNNER_VERSION=$(sed -n 's/^runner_version = "\([^"]*\)".*/\1/p' "$SCRIPT_DIR/lightscope/lightscope-runner.py" | head -1)

# ---- python flavor ---------------------------------------------------------------
if [ -z "${PYVER:-}" ]; then
    PYVER=""
    if [ "$HAVE_PKG" -eq 1 ]; then
        PYVER=$(pkg rquery '%dn' python3 2>/dev/null | sed -n 's/^python\(3[0-9][0-9]*\)$/\1/p' | head -1 || true)
    fi
    [ -n "$PYVER" ] || PYVER=311
fi
PYDOT="3.${PYVER#3}"            # 311 -> 3.11
PYTHON="$PREFIX/bin/python$PYDOT"

# ---- variant ------------------------------------------------------------------------
if [ "${LIGHTSCOPE_NO_HONEYPOT:-0}" = "1" ]; then
    PKG_NAME="lightscope-nohoneypot"
    HONEYPOT_DEFAULT="no"
else
    PKG_NAME="lightscope"
    HONEYPOT_DEFAULT="yes"
fi

echo "Building $PKG_NAME v$VERSION (runner $RUNNER_VERSION) for FreeBSD: python$PYVER, honeypots=$HONEYPOT_DEFAULT"

# ---- stage ---------------------------------------------------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$STAGE" "$META"

subst() {
    sed -e "s|@PYTHON@|$PYTHON|g" \
        -e "s|@PYVER@|$PYVER|g" \
        -e "s|@VERSION@|$VERSION|g" \
        -e "s|@HONEYPOT_DEFAULT@|$HONEYPOT_DEFAULT|g" \
        -e "s|@PREFIX@|$PREFIX|g" "$1" > "$2"
}

# Static files (rc script, newsyslog, samples) with placeholders filled in
(cd "$PKG_SRC" && find usr -type f) | while IFS= read -r rel; do
    mkdir -p "$STAGE/$(dirname "$rel")"
    subst "$PKG_SRC/$rel" "$STAGE/$rel"
done
chmod 0755 "$STAGE$PREFIX/etc/rc.d/lightscope"
chmod 0644 "$STAGE$PREFIX/etc/newsyslog.conf.d/lightscope.conf" \
           "$STAGE$PREFIX/share/lightscope/config.ini.sample" \
           "$STAGE$PREFIX/share/lightscope/devfs.rules.sample"

# Application files: the same core and runner the Linux packages ship
mkdir -p "$STAGE$LS_HOME/bin" "$STAGE$LS_HOME/config"
cp "$SCRIPT_DIR/lightscope/lightscope_core.py" "$STAGE$LS_HOME/bin/"
cp "$SCRIPT_DIR/lightscope/lightscope-runner.py" "$STAGE$LS_HOME/bin/"
chmod 0644 "$STAGE$LS_HOME/bin/lightscope_core.py"
chmod 0755 "$STAGE$LS_HOME/bin/lightscope-runner.py"

if [ -f "$SCRIPT_DIR/lightscope-public.pem" ]; then
    cp "$SCRIPT_DIR/lightscope-public.pem" "$STAGE$LS_HOME/config/lightscope-public.pem"
    chmod 0644 "$STAGE$LS_HOME/config/lightscope-public.pem"
else
    echo "Error: lightscope-public.pem not found; the runner cannot verify updates without it" >&2
    exit 1
fi

BUILT_VERSION=$(sed -n 's/^ls_version = "\([^"]*\)".*/\1/p' "$STAGE$LS_HOME/bin/lightscope_core.py" | head -1)
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "Error: staged core is v$BUILT_VERSION, expected v$VERSION" >&2
    exit 1
fi
if ! grep -q "^honeypots = $HONEYPOT_DEFAULT\$" "$STAGE$PREFIX/share/lightscope/config.ini.sample"; then
    echo "Error: config.ini.sample does not set honeypots = $HONEYPOT_DEFAULT" >&2
    exit 1
fi
if grep -rq '@[A-Z_]*@' "$STAGE"; then
    echo "Error: unreplaced placeholder in staged tree:" >&2
    grep -rn '@[A-Z_]*@' "$STAGE" >&2
    exit 1
fi

# ---- plist (paths relative to PREFIX) -------------------------------------------------
cat > "$PLIST" <<PLIST_EOF
@owner lightscope
@group lightscope
@mode 0755
@dir lightscope
@dir lightscope/bin
@dir lightscope/config
@mode 0644
lightscope/bin/lightscope_core.py
@mode 0755
lightscope/bin/lightscope-runner.py
@mode 0644
lightscope/config/lightscope-public.pem
@owner
@group
@mode 0755
etc/rc.d/lightscope
@mode 0644
etc/newsyslog.conf.d/lightscope.conf
share/lightscope/config.ini.sample
share/lightscope/devfs.rules.sample
@mode
PLIST_EOF

# ---- metadata ---------------------------------------------------------------------------
for s in +PRE_INSTALL +POST_INSTALL +PRE_DEINSTALL +POST_DEINSTALL; do
    subst "$PKG_SRC/$s" "$META/$s"
    chmod 0755 "$META/$s"
done
cp "$PKG_SRC/+DESC" "$META/+DESC"

if [ "$HAVE_PKG" -eq 1 ]; then
    ABI=$(pkg config ABI)             # e.g. FreeBSD:14:amd64
else
    ABI="FreeBSD:14:amd64"
fi
ABI_NOARCH="${ABI%:*}:*"              # pure Python, so FreeBSD:14:*
ARCH_NOARCH=$(echo "$ABI_NOARCH" | tr 'A-Z' 'a-z')

DEPS="python$PYVER py$PYVER-dpkt py$PYVER-psutil py$PYVER-requests py$PYVER-cryptography py$PYVER-packaging py$PYVER-pypcap"

fallback_origin() {
    case "$1" in
        python3*)          echo "lang/$1" ;;
        py*-dpkt)          echo "net/py-dpkt" ;;
        py*-psutil)        echo "sysutils/py-psutil" ;;
        py*-requests)      echo "www/py-requests" ;;
        py*-cryptography)  echo "security/py-cryptography" ;;
        py*-packaging)     echo "devel/py-packaging" ;;
        py*-pypcap)        echo "net/py-pypcap" ;;
        *)                 echo "misc/$1" ;;
    esac
}

dep_line() {
    name="$1"
    info=""
    if [ "$HAVE_PKG" -eq 1 ]; then
        info=$(pkg query '%o|%v' "$name" 2>/dev/null || true)
        if [ -z "$info" ]; then
            info=$(pkg rquery '%o|%v' "$name" 2>/dev/null | head -1 || true)
        fi
    fi
    if [ -z "$info" ]; then
        echo "Warning: $name is neither installed nor in the pkg catalog; recording version 0" >&2
        info="$(fallback_origin "$name")|0"
    fi
    origin="${info%%|*}"
    ver="${info#*|}"
    printf '    "%s": {origin: "%s", version: "%s"}\n' "$name" "$origin" "$ver"
}

{
    cat <<MANIFEST_EOF
name: "$PKG_NAME"
version: "$VERSION"
origin: "net-mgmt/$PKG_NAME"
comment: "Network security monitoring and honeypot system"
maintainer: "e@alumni.usc.edu"
www: "https://thelightscope.com"
prefix: "$PREFIX"
abi: "$ABI_NOARCH"
arch: "$ARCH_NOARCH"
licenselogic: "single"
licenses: ["MIT"]
categories: ["net-mgmt", "security"]
desc: <<EOD
$(cat "$PKG_SRC/+DESC")
EOD
deps: {
MANIFEST_EOF
    for d in $DEPS; do
        dep_line "$d"
    done
    echo "}"
} > "$META/+MANIFEST"

echo "Staged tree:  $STAGE"
echo "Manifest:     $META/+MANIFEST"
echo "Plist:        $PLIST"

if [ "$STAGE_ONLY" -eq 1 ]; then
    echo "--stage-only: skipping pkg create"
    exit 0
fi

# ---- build ----------------------------------------------------------------------------------
pkg create -v -m "$META" -r "$STAGE" -p "$PLIST" -o "$BUILD_DIR"

OUT=""
for candidate in "$BUILD_DIR/$PKG_NAME-$VERSION.pkg" "$BUILD_DIR/$PKG_NAME-$VERSION.txz"; do
    if [ -f "$candidate" ]; then
        OUT="$candidate"
        break
    fi
done
if [ -z "$OUT" ]; then
    echo "Error: pkg create produced no package in $BUILD_DIR" >&2
    exit 1
fi

FINAL="$SCRIPT_DIR/$PKG_NAME-$VERSION.pkg"
cp "$OUT" "$FINAL"
echo ""
echo "Package built: $FINAL"
pkg info -F "$FINAL" || true
echo ""
echo "To install:  pkg install $FINAL"
echo "To remove:   pkg delete $PKG_NAME"
