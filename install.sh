#!/usr/bin/env bash
#
# Installer for rtsp-to-prusa-connect.
# Run as root:  sudo ./install.sh
#
set -euo pipefail

PREFIX_BIN="/usr/local/bin"
CONF="/etc/rtsp-to-prusa-connect.conf"
UNIT="/etc/systemd/system/rtsp-to-prusa-connect.service"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo ./install.sh)." >&2
    exit 1
fi

echo "Installing script to ${PREFIX_BIN}..."
install -m 0755 "${HERE}/rtsp-to-prusa-connect.sh" "${PREFIX_BIN}/rtsp-to-prusa-connect.sh"

echo "Installing systemd unit..."
install -m 0644 "${HERE}/rtsp-to-prusa-connect.service" "${UNIT}"

if [ ! -f "${CONF}" ]; then
    echo "Creating config at ${CONF} (edit it before starting the service)..."
    install -m 0600 "${HERE}/rtsp-to-prusa-connect.conf.example" "${CONF}"
else
    echo "Config ${CONF} already exists, leaving it untouched."
fi

# Best-effort dependency check.
missing=""
for bin in ffmpeg curl; do
    command -v "$bin" >/dev/null 2>&1 || missing="${missing} ${bin}"
done
if [ -n "${missing}" ]; then
    echo "NOTE: missing dependencies:${missing}"
    echo "      On Debian/Raspberry Pi OS: sudo apt update && sudo apt install -y${missing}"
fi

systemctl daemon-reload

cat <<EOF

Done.

Next steps:
  1. Edit your settings:      sudo nano ${CONF}
  2. Enable & start service:  sudo systemctl enable --now rtsp-to-prusa-connect
  3. Watch the logs:          journalctl -u rtsp-to-prusa-connect -f
EOF
