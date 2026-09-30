# rtsp-to-prusa-connect

Push snapshots from any **RTSP camera** to **[Prusa Connect](https://connect.prusa3d.com/)**.

A tiny, dependency-light service that grabs one frame from an RTSP stream every
few seconds with `ffmpeg` and uploads it to Prusa Connect using its "other
camera" HTTP API. Ideal for watching a print from a cheap ONVIF/RTSP camera
running alongside PrusaLink on a Raspberry Pi (Zero 2 W and up).

- Works with **any RTSP source** (IP cameras, NVR sub-streams, re-streamed feeds).
- Runs as a **systemd service** with auto-restart.
- Writes the temporary JPEG to **RAM (`/dev/shm`)** to spare the SD card.
- Sets the camera **display name** automatically (the Prusa Connect web UI cannot
  rename "other" cameras).
- Config kept out of the repo, in `/etc/rtsp-to-prusa-connect.conf`.

## Requirements

- Linux with `systemd`
- `ffmpeg` and `curl`

On Debian / Raspberry Pi OS:

```bash
sudo apt update && sudo apt install -y ffmpeg curl
```

## Install

```bash
git clone https://github.com/AttilaSVK/rtsp-to-prusa-connect.git
cd rtsp-to-prusa-connect
sudo ./install.sh
```

Then edit your settings and start the service:

```bash
sudo nano /etc/rtsp-to-prusa-connect.conf
sudo systemctl enable --now rtsp-to-prusa-connect
journalctl -u rtsp-to-prusa-connect -f
```

## Getting a Prusa Connect camera token

1. Open [Prusa Connect](https://connect.prusa3d.com/) and select your printer.
2. Go to the **Camera** tab and add a **new camera of type "Other"**.
3. Copy the **Token** it gives you into `PRUSA_TOKEN` in the config file.

## Configuration

All settings live in `/etc/rtsp-to-prusa-connect.conf`
(see [`rtsp-to-prusa-connect.conf.example`](rtsp-to-prusa-connect.conf.example)):

| Variable | Required | Default | Description |
|---|---|---|---|
| `RTSP_URL` | yes | – | Full RTSP URL, e.g. `rtsp://user:pass@192.168.1.50:554/stream0` |
| `PRUSA_TOKEN` | yes | – | Camera token from Prusa Connect |
| `FINGERPRINT` | yes | – | Stable unique camera ID (≥16 chars, no spaces). **Not** a secret, **not** the name. Keep it constant. |
| `CAMERA_NAME` | no | `RTSP Camera` | Display name in Prusa Connect |
| `INTERVAL` | no | `20` | Seconds between snapshots |
| `SNAPSHOT_PATH` | no | `/dev/shm/prusa_snapshot.jpg` | Temp JPEG path (RAM by default) |
| `RTSP_TRANSPORT` | no | `tcp` | `tcp` (reliable) or `udp` |
| `FFMPEG_TIMEOUT_OPT` | no | `-timeout` | Use `-stimeout` on older ffmpeg builds |
| `FFMPEG_TIMEOUT_US` | no | `5000000` | ffmpeg I/O timeout in microseconds |
| `PRUSA_HOST` | no | `https://webcam.connect.prusa3d.com` | API base URL |

### About `FINGERPRINT`

The fingerprint is only a unique identifier Prusa Connect uses to tell cameras
apart — it is **not** the display name and **not** secret. Pick any constant
string of at least 16 alphanumeric characters (no spaces) and never change it;
changing it makes Connect show a brand-new camera. The human-readable name is set
separately via `CAMERA_NAME`.

## How it works

On start-up the service sends `PUT /c/info` to register/rename the camera, then
loops:

1. `ffmpeg` grabs a single JPEG frame from `RTSP_URL` into a tmpfs file.
2. `curl` uploads it with `PUT /c/snapshot` (headers: `token`, `fingerprint`,
   `content-type: image/jpg`).
3. Sleep `INTERVAL` seconds, repeat.

See the Prusa Connect [camera API docs](https://connect.prusa3d.com/docs/cameras/)
for the endpoint details.

## Running manually (for testing)

```bash
export RTSP_URL='rtsp://192.168.1.50:554/stream0'
export PRUSA_TOKEN='...'
export FINGERPRINT='changeme0123456789abcdef'
export CAMERA_NAME='My Printer'
./rtsp-to-prusa-connect.sh
```

## Troubleshooting

- **Camera shows as "Unnamed Camera".** The web UI can't rename "other" cameras;
  this tool sets the name via `PUT /c/info` at startup. Make sure the service
  restarted after you set `CAMERA_NAME`, and that the `FINGERPRINT` matches the
  one used for snapshots (a mismatch creates a separate camera).
- **`capture failed`.** Test the URL directly:
  `ffmpeg -rtsp_transport tcp -i "$RTSP_URL" -frames:v 1 test.jpg`.
- **ffmpeg rejects `-timeout`.** Set `FFMPEG_TIMEOUT_OPT=-stimeout`.
- **Uploads return 401/403.** The `PRUSA_TOKEN` is wrong or expired.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Inspired by the community RTSP → Prusa Connect scripts
([nunofgs gist](https://gist.github.com/nunofgs/84861ee453254823be6b069ebbce9ad2)).
Not affiliated with Prusa Research.
