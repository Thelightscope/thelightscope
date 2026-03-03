#!/bin/bash
# Build and upload a LightScope RPM package with honeypots disabled by default.
# This wrapper sets LIGHTSCOPE_NO_HONEYPOT=1 so the installed config.ini
# will have  honeypots = no  and no honeypot processes will start.
set -e
export LIGHTSCOPE_NO_HONEYPOT=1
exec "$(dirname "$0")/rpm_build_all_upload.sh"
