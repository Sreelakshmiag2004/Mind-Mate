import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the app's access/refresh tokens live.
///
/// An interface (not just a concrete class) so [ApiClient] and
/// [AuthRepository] can be unit-tested against an in-memory fake instead of
/// the real platform-channel-backed secure storage — see
/// `test/fakes/fake_token_storage.dart`.
abstract class TokenStorage {
  /// Persists both tokens together. Always called as a pair — the backend
  /// never issues one without the other (see `TokenResponse` in
  /// `app/schemas/auth.py`), and a refresh rotates both, so there is no
  /// legitimate state where only one of the two should be updated.
  Future<void> saveTokens({required String accessToken, required String refreshToken});

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  /// Removes both tokens. Called on logout and whenever a refresh attempt
  /// itself fails (see `api_client.dart`) — in both cases the app must fall
  /// back to requiring a fresh login, never keep a stale/rejected token
  /// around.
  Future<void> clear();
}

/// Real implementation, backed by `flutter_secure_storage` (Keychain on
/// iOS, EncryptedSharedPreferences/Keystore on Android). Deliberately not
/// Hive or `shared_preferences` — both store plaintext on disk, which is
/// not acceptable for a refresh token that is valid for
/// `REFRESH_TOKEN_EXPIRE_DAYS` (30 by default — see
/// `backend/app/core/config.py`) and is the credential that matters most
/// if the device is compromised.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'mindmate.auth.access_token';
  static const _refreshTokenKey = 'mindmate.auth.refresh_token';

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
