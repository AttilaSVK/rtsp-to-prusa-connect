#!/usr/bin/env bash
#
# rtsp-to-prusa-connect
# ---------------------
# Grab a single frame from an RTSP camera at a fixed interval and upload it to
# Prusa Connect using the "other camera" HTTP API.
#
# It works with any RTSP source (IP camera, NVR sub-stream, a re-streamed feed,
# etc.). It was originally written to feed a Prusa Connect print view from a
# cheap ONVIF/RTSP camera, running next to PrusaLink on a Raspberry Pi.
#
# Configuration is read from the environment. When installed as a systemd
# service, those variables come from /etc/rtsp-to-prusa-connect.conf (see the
# provided .conf.example). Nothing secret is hard-coded here, so this file is
# safe to commit.
#
# API reference: https://connect.prusa3d.com/docs/cameras/
#
# License: MIT
#
set -uo pipefail

# --- Configuration (with sensible defaults) ---------------------------------

# Required: full RTSP URL of the source stream, e.g.
#   rtsp://user:pass@192.168.1.50:554/stream0
RTSP_URL="${RTSP_URL:?RTSP_URL is required (set it in the config file or environment)}"

# Required: the camera token from Prusa Connect
# (Connect -> your printer -> Camera -> add a new "Other" camera -> copy Token).
PRUSA_TOKEN="${PRUSA_TOKEN:?PRUSA_TOKEN is required}"

# Required: a stable, client-chosen camera fingerprint. This is NOT a secret and
# NOT the display name -- it is only the unique ID Prusa Connect uses to tell
# cameras apart. It must stay constant (changing it creates a new camera entry)
# and should be at least 16 alphanumeric characters, no spaces.
FINGERPRINT="${FINGERPRINT:?FINGERPRINT is required (>=16 chars, no spaces, keep it constant)}"

# Optional: the display name shown in Prusa Connect. Pushed via PUT /c/info at
# startup, because the web UI does not let you rename "other" cameras.
CAMERA_NAME="${CAMERA_NAME:-RTSP Camera}"

# Optional: seconds to wait between snapshots. The real cadence is roughly
# INTERVAL + (capture + upload time).
INTERVAL="${INTERVAL:-20}"

# Optional: where to write the temporary JPEG. Defaults to a tmpfs (RAM) path so
# it does not wear out the SD card. Falls back to /tmp if /dev/shm is missing.
SNAPSHOT_PATH="${SNAPSHOT_PATH:-/dev/shm/prusa_snapshot.jpg}"

# Optional: Prusa Connect camera API base URL. Rarely needs changing.
PRUSA_HOST="${PRUSA_HOST:-https://webcam.connect.prusa3d.com}"

# Optional: RTSP transport. "tcp" is the most reliable; use "udp" only if your
# network/camera needs it.
RTSP_TRANSPORT="${RTSP_TRANSPORT:-tcp}"

# Optional: ffmpeg I/O timeout in microseconds (5 s by default). If your ffmpeg
# build rejects "-timeout" for RTSP, set FFMPEG_TIMEOUT_OPT=-stimeout instead.
FFMPEG_TIMEOUT_OPT="${FFMPEG_TIMEOUT_OPT:--timeout}"
FFMPEG_TIMEOUT_US="${FFMPEG_TIMEOUT_US:-5000000}"

# --- Helpers ----------------------------------------------------------------

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# Fall back to /tmp if the tmpfs path is not available.
if [ ! -d "$(dirname "$SNAPSHOT_PATH")" ]; then
    SNAPSHOT_PATH="/tmp/prusa_snapshot.jpg"
    log "WARN: tmpfs path not available, using $SNAPSHOT_PATH"
fi

# Make sure the tools we need are present.
for bin in ffmpeg curl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "FATAL: '$bin' not found in PATH. Install it and retry."
        exit 1
    fi
done

# Register / rename the camera in Prusa Connect (PUT /c/info).
# The web UI cannot rename "other" cameras, so this is the only way to give it a
# name instead of "Unnamed Camera". It is idempotent, so we call it once at
# startup and simply log the result.
register_camera() {
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' \
        -X PUT "${PRUSA_HOST}/c/info" \
        -H "content-type: application/json" \
        -H "fingerprint: ${FINGERPRINT}" \
        -H "token: ${PRUSA_TOKEN}" \
        --data "{\"config\": {\"name\": \"${CAMERA_NAME}\"}}")"
    log "register (PUT /c/info) -> HTTP ${code}"
}

# Capture exactly one frame from the RTSP stream into $SNAPSHOT_PATH.
# Returns ffmpeg's exit status.
capture_frame() {
    ffmpeg -nostdin -loglevel error -y \
        -rtsp_transport "${RTSP_TRANSPORT}" \
        "${FFMPEG_TIMEOUT_OPT}" "${FFMPEG_TIMEOUT_US}" \
        -i "${RTSP_URL}" \
        -frames:v 1 -pix_fmt yuvj420p \
        "${SNAPSHOT_PATH}"
}

# Upload the current snapshot to Prusa Connect (PUT /c/snapshot).
# Prints the HTTP status code.
upload_snapshot() {
    curl -s -o /dev/null -w '%{http_code}' \
        -X PUT "${PRUSA_HOST}/c/snapshot" \
        -H "accept: */*" \
        -H "content-type: image/jpg" \
        -H "fingerprint: ${FINGERPRINT}" \
        -H "token: ${PRUSA_TOKEN}" \
        --data-binary "@${SNAPSHOT_PATH}" \
        --no-progress-meter --compressed
}

# --- Main loop --------------------------------------------------------------

log "starting: source=${RTSP_URL%%\?*} interval=${INTERVAL}s name='${CAMERA_NAME}'"
register_camera

# Clean shutdown on SIGTERM/SIGINT (so systemctl stop is instant and tidy).
trap 'log "stopping"; exit 0' TERM INT

while true; do
    if capture_frame; then
        code="$(upload_snapshot)"
        case "$code" in
            200|204) log "snapshot uploaded (HTTP ${code})" ;;
            401|403) log "ERROR: upload rejected (HTTP ${code}) -- check PRUSA_TOKEN" ;;
            *)       log "WARN: upload returned HTTP ${code}" ;;
        esac
    else
        log "WARN: capture failed -- is the camera reachable at ${RTSP_URL%%\?*}?"
    fi
    sleep "${INTERVAL}"
done
