#!/bin/sh
#
# freebsd_build_all_upload.sh - build, sign and publish the FreeBSD packages.
# FreeBSD counterpart of dpkg_build_all_upload.sh; runs ON a FreeBSD host.
#
# One-time setup on the build host:
#   pkg install -y git python3 sshpass \
#       py3XX-dpkt py3XX-psutil py3XX-requests py3XX-cryptography py3XX-packaging py3XX-pypcap
#   (XX = the ports default, see: pkg rquery '%dn' python3)
#   put the release signing key somewhere outside the repo and point at it:
#       LIGHTSCOPE_PRIVATE_KEY=/root/lightscope-private.pem sh ./freebsd_build_all_upload.sh
#   (default: lightscope-private.pem in this directory, which .gitignore excludes)
#
# Steps: build both variants -> sign lightscope_core.py and bundle upload/ ->
#        scp the bundle to lightscope.isi.edu -> deploy into /var/www/lightscope/latest/
#
set -eu
cd "$(dirname "$0")"

die() { echo "Error: $*" >&2; exit 1; }

echo "=== LightScope FreeBSD Package Build ==="
[ "$(uname)" = "FreeBSD" ] || die "run this on a FreeBSD host (pkg create is FreeBSD-only)"
[ -f lightscope/lightscope_core.py ] || die "run from the thelightscope directory"

# ---- tools -------------------------------------------------------------------
PYTHON=$(command -v python3 || true)
if [ -z "$PYTHON" ]; then
    flavor=$(pkg rquery '%dn' python3 2>/dev/null | sed -n 's/^python3\([0-9][0-9]*\)$/3.\1/p' | head -1)
    [ -n "$flavor" ] && [ -x "/usr/local/bin/python$flavor" ] && PYTHON="/usr/local/bin/python$flavor"
fi
[ -n "$PYTHON" ] || die "python3 not found: pkg install python3"
"$PYTHON" -c "import cryptography" 2>/dev/null || die "python module cryptography missing: pkg install py3XX-cryptography"
command -v sshpass >/dev/null 2>&1 || die "sshpass not found: pkg install sshpass"

# ---- signing key -----------------------------------------------------------------
# Never generate a key here. Every installed LightScope verifies updates against
# the public key it shipped with; a new pair would make all of them reject updates.
PRIVATE_KEY="${LIGHTSCOPE_PRIVATE_KEY:-lightscope-private.pem}"
[ -f "$PRIVATE_KEY" ] || die "signing key not found at $PRIVATE_KEY (set LIGHTSCOPE_PRIVATE_KEY; never generate a new one)"
[ -f lightscope-public.pem ] || die "lightscope-public.pem not found"

# ---- clean ---------------------------------------------------------------------------
rm -rf upload/ build-freebsd/
rm -f lightscope_v*_upload.tar.gz lightscope_v*_upload.zip
rm -f lightscope-*.pkg

VERSION=$(sed -n 's/^ls_version = "\([^"]*\)".*/\1/p' lightscope/lightscope_core.py | head -1)
[ -n "$VERSION" ] || die "could not read ls_version"
STD_PKG="lightscope-${VERSION}.pkg"
NOHP_PKG="lightscope-nohoneypot-${VERSION}.pkg"
TARBALL="lightscope_v${VERSION}_upload.tar.gz"

# ---- build ---------------------------------------------------------------------------
echo ""; echo "1. Building standard package (honeypots=yes)..."
sh ./build-freebsd-pkg.sh
echo ""; echo "2. Building no-honeypot package (honeypots=no)..."
LIGHTSCOPE_NO_HONEYPOT=1 sh ./build-freebsd-pkg.sh
[ -f "$STD_PKG" ]  || die "$STD_PKG was not built"
[ -f "$NOHP_PKG" ] || die "$NOHP_PKG was not built"
echo ""; echo "3. Packages built:"; ls -la "$STD_PKG" "$NOHP_PKG"

# ---- sign + bundle ---------------------------------------------------------------------
echo ""; echo "4. Signing lightscope_core.py and bundling upload/ ..."
"$PYTHON" sign-and-upload.py --verify --package-type freebsd --no-upload --private-key "$PRIVATE_KEY"
[ -f "upload/$STD_PKG" ] && [ -f "upload/$NOHP_PKG" ] || die "packages missing from upload/"
[ -f "$TARBALL" ] || die "$TARBALL was not created"
echo ""; ls -la upload/

# ---- upload + deploy ---------------------------------------------------------------------
SERVER_USER_HOST="kapitans@lightscope.isi.edu"
REMOTE_PATH="/var/www/lightscope/latest"
# accept-new: trust the server's host key on first contact, still refuse a changed one
SSH_OPTS="-o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=accept-new"

# sshpass discards ssh's own messages, so explain its exit codes.
with_password() {
    sshpass -p "$SERVER_PASSWORD" "$@" && return 0
    rc=$?
    case $rc in
        5) die "ssh authentication failed: wrong password for $SERVER_USER_HOST" ;;
        6) die "ssh host key problem for $SERVER_USER_HOST (run: ssh $SERVER_USER_HOST true)" ;;
        *) die "ssh/scp failed with exit code $rc" ;;
    esac
}

printf '\nEnter password for %s (typing is hidden): ' "$SERVER_USER_HOST"
trap "stty echo" EXIT INT TERM; stty -echo; read -r SERVER_PASSWORD; stty echo; echo ""
[ -n "$SERVER_PASSWORD" ] || die "no password given"

echo ""; echo "5. Uploading $TARBALL ..."
with_password scp $SSH_OPTS "$TARBALL" "${SERVER_USER_HOST}:~/"

# The tarball carries lightscope_core.py, .sig, version, the public key and
# both .pkg files, so one archive is all the server needs.
DEPLOY=$(mktemp -t lsdeploy)
cat > "$DEPLOY" <<'EOF'
#!/bin/bash
set -e
TARBALL="$1"; VERSION="$2"; REMOTE_PATH="$3"
mv ~/"$TARBALL" /tmp/
sudo bash -c "
    set -e
    mv /tmp/$TARBALL $REMOTE_PATH/
    cd $REMOTE_PATH
    tar -xzf $TARBALL
    if [ -d upload ]; then mv upload/* . && rm -rf upload; fi
    rm -f $TARBALL
    rm -f lightscope_latest.pkg lightscope-nohoneypot_latest.pkg
    cp lightscope-$VERSION.pkg lightscope_latest.pkg
    cp lightscope-nohoneypot-$VERSION.pkg lightscope-nohoneypot_latest.pkg
    chown -R www-data:www-data $REMOTE_PATH/
    chmod -R 644 $REMOTE_PATH/* 2>/dev/null || true
    echo; echo 'Deployed:'; ls -la $REMOTE_PATH/
"
EOF
echo ""; echo "6. Deploying on the server (sudo will ask for your password)..."
with_password scp $SSH_OPTS "$DEPLOY" "${SERVER_USER_HOST}:/tmp/lightscope-deploy.sh"
with_password ssh -t $SSH_OPTS "$SERVER_USER_HOST" \
    "bash /tmp/lightscope-deploy.sh '$TARBALL' '$VERSION' '$REMOTE_PATH'; rc=\$?; rm -f /tmp/lightscope-deploy.sh; exit \$rc"
rm -f "$DEPLOY"

echo ""
echo "DEPLOYMENT COMPLETE"
echo "  https://thelightscope.com/latest/version"
echo "  https://thelightscope.com/latest/lightscope_latest.pkg"
echo "  https://thelightscope.com/latest/lightscope-nohoneypot_latest.pkg"
