import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/storage/secure_storage_service.dart';

/// This is the one test file in the suite that exercises the REAL
/// [SecureTokenStorage] (every other test uses `FakeTokenStorage`, an
/// in-memory double). `flutter_secure_storage` talks to the platform
/// through a `MethodChannel` — there is no real Keychain/Keystore
/// available in the test environment, so this test stands in for the
/// native side by handling that channel's method calls directly, using
/// the exact channel name and method/argument shapes the installed
/// `flutter_secure_storage_platform_interface` package uses (verified by
/// reading its `MethodChannelFlutterSecureStorage` source — see
/// PHASE7_API_INTEGRATION.md). This is a genuine test of `SecureTokenStorage`
/// end-to-end down to (a mocked) platform boundary, not a re-test of the
/// `TokenStorage` interface contract, which `FakeTokenStorage`-based tests
/// elsewhere already cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> backingStore;

  setUp(() {
    backingStore = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'write':
          backingStore[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'read':
          return backingStore[call.arguments['key'] as String];
        case 'delete':
          backingStore.remove(call.arguments['key'] as String);
          return null;
        case 'containsKey':
          return backingStore.containsKey(call.arguments['key'] as String);
        default:
          throw MissingPluginException('Unmocked method: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  SecureTokenStorage buildStorage() => SecureTokenStorage(
    storage: const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
  );

  test('readAccessToken and readRefreshToken return null before anything is saved', () async {
    final storage = buildStorage();

    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('saveTokens persists both tokens, independently readable afterward', () async {
    final storage = buildStorage();

    await storage.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

    expect(await storage.readAccessToken(), 'access-1');
    expect(await storage.readRefreshToken(), 'refresh-1');
  });

  test('saveTokens replaces a previously stored pair rather than merging with it', () async {
    final storage = buildStorage();
    await storage.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

    await storage.saveTokens(accessToken: 'access-2', refreshToken: 'refresh-2');

    expect(await storage.readAccessToken(), 'access-2');
    expect(await storage.readRefreshToken(), 'refresh-2');
  });

  test('clear removes both tokens', () async {
    final storage = buildStorage();
    await storage.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

    await storage.clear();

    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('two independently-constructed SecureTokenStorage instances share the same underlying storage', () async {
    // Regression guard: confirms tokens are keyed by a fixed, well-known
    // key (not e.g. an instance-specific key) — session restoration on
    // app startup constructs a fresh AuthRepository/SecureTokenStorage and
    // must still see whatever a previous instance (or app run) saved.
    final first = buildStorage();
    await first.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

    final second = buildStorage();

    expect(await second.readAccessToken(), 'access-1');
  });
}
