/// Phase 7 — environment configuration for the FastAPI backend.
///
/// The backend's own base URL is the one thing about this integration that
/// must never be hardcoded (see PHASE6_INTEGRATION_AUDIT.md, Step 9) — it
/// differs between the Android emulator, a physical device on the same
/// network, iOS Simulator, and production, and none of those values belong
/// in source control as a default that gets silently shipped.
///
/// Override it at build/run time with:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8000
///
/// or for a release build:
///
///   flutter build apk --dart-define=API_BASE_URL=https://api.mindmate.example.com
///
/// See API_CONFIGURATION.md at the project root for the full set of
/// per-environment values (Android emulator vs. physical device vs. iOS
/// Simulator vs. production) and why each one is what it is.
class AppConfig {
  AppConfig._();

  /// Falls back to the Android-emulator loopback alias so `flutter run` on
  /// an emulator works out of the box with zero configuration — this is a
  /// development convenience, not a production default. It is NOT reachable
  /// from a physical device, iOS Simulator, or any real deployment; those
  /// all require passing `--dart-define=API_BASE_URL=...` explicitly.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// How long a single HTTP request is allowed to take before Dio gives up.
  /// Generous enough for a slow mobile connection, short enough that a
  /// hung request doesn't leave a screen spinning indefinitely.
  static const Duration requestTimeout = Duration(seconds: 20);
}
