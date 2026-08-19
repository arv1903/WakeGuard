# Flutter companion dashboard

This app is the shared Flutter client for the Python driver-monitoring API.
It supports desktop-local and mobile-companion modes without adding third-party
Dart dependencies.

## Requirements

- Flutter 3.27+
- Python backend running with `--api`

This repository contains the shared Dart source and intentionally does not
check in generated platform folders. Run `flutter create .` once inside this
directory to generate the Windows/Android/iOS runner projects before building.
For LAN-only mobile development, use HTTP on a trusted network and configure
the generated Android/iOS platform projects to permit cleartext local traffic;
use HTTPS or a tunnel for production deployments.

## Run on desktop

From this directory:

```bash
flutter pub get
flutter run -d windows --dart-define=API_URL=http://127.0.0.1:8765
```

To let the desktop app start the Python service automatically during local
development, add the backend root and enable the optional process manager:

```bash
flutter run -d windows \
  --dart-define=AUTO_START_BACKEND=true \
  --dart-define=BACKEND_ROOT=..
```

## Run on a mobile device

Start the backend on the computer or edge device that owns the camera:

```bash
python main.py --api --api-host 0.0.0.0 --api-token CHANGE_ME
```

Use the computer's LAN address in the Flutter app, for example:

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:8765
```

Both devices must be on the same network, and the host firewall must permit
the selected port. Open connection settings and choose **Pair device**: reveal
the short-lived code on the local desktop, then enter it on the phone. The
backend exchanges it for a 24-hour bearer token in memory. Manual bearer-token
entry remains available for administration. Use **Forget paired device** in
connection settings to revoke the companion token and clear it locally; the
master deployment token cannot be revoked from the client. Pairing failures are
throttled by the backend to slow guessing.

The client consumes the state SSE channel for live metrics and a persistent
`/api/v1/video.mjpg` connection for the camera feed; frames are decoded on the
UI thread with stale frames dropped, so playback stays smooth even when the
backend runs faster than the display can decode.

## Security notes

LAN mode is intended for a trusted network during this MVP. Always configure a
strong `--api-token`, keep the service off public interfaces, and use HTTPS or
a secure tunnel before exposing it beyond the local network. Tokens and pairing
codes are held in memory by the Python service and are revoked when the service
restarts; a failed remote forget request still clears the token from the local
Flutter client, so the device can be paired again safely.
