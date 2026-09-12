# API base URL configuration

The FastAPI backend's base URL is never hardcoded in this app (see
`lib/core/config/app_config.dart`). It is read at build/run time via a
`--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8000
```

If you omit `--dart-define=API_BASE_URL=...`, the app falls back to
`http://10.0.2.2:8000` — the Android emulator's alias for your host
machine's `localhost`. That default exists purely so `flutter run` works
out of the box on an emulator with zero configuration; it is **not**
reachable from a physical device, iOS Simulator, or any real deployment.

## Which value to use

| Target | `API_BASE_URL` |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` (the default — no flag needed) |
| Physical Android device, same Wi-Fi as your dev machine | `http://<your machine's LAN IP>:8000`, e.g. `http://192.168.1.23:8000` |
| iOS Simulator | `http://127.0.0.1:8000` or `http://localhost:8000` |
| Physical iOS device, same Wi-Fi | same as the physical Android case — your machine's LAN IP |
| Production | `https://<your production domain>`, supplied at build time — never committed anywhere in this repo |

To find your machine's LAN IP: `ipconfig` on Windows (look for the active
adapter's IPv4 address) or `ifconfig`/`ip addr` on macOS/Linux. It changes
between networks, so this is always passed at run/build time, never
hardcoded.

## Physical Android device + a local dev server (HTTP, not HTTPS)

The backend's local dev server is plain HTTP — there is no TLS certificate
for `10.0.2.2` or a LAN IP, and setting one up for local development isn't
worth the trouble. Android blocks cleartext (non-HTTPS) traffic by default
for apps targeting a recent SDK, so this repo's debug build allows it, but
**only** for the handful of hosts a local dev server could plausibly be
reachable at — see `android/app/src/debug/res/xml/network_security_config.xml`
and its reference from `android/app/src/debug/AndroidManifest.xml`. This
applies to debug builds only; a release build still requires HTTPS, as it
always should.

If you're testing against a LAN IP other than the ones already listed
there, add it to that file — do not widen the debug config to allow
cleartext for every domain.

## Building for production

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.mindmate.example.com
```

Never commit a real production URL as a default anywhere in this repo —
pass it explicitly at build time, the same way CI/CD or your release
process would for any other environment-specific value.
