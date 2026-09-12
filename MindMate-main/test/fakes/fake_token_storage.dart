import 'package:mindmate/core/storage/secure_storage_service.dart';

/// In-memory [TokenStorage] test double. Exists so [ApiClient] and
/// [AuthRepository] tests never touch a real platform channel — see
/// `test/core/storage/secure_storage_service_test.dart` for the one test
/// file that exercises the real, `flutter_secure_storage`-backed
/// implementation directly.
class FakeTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;

  /// Incremented on every [saveTokens] call — lets a test assert a refresh
  /// actually happened (and how many times) without inspecting the token
  /// values themselves.
  int saveCount = 0;

  /// Incremented on every [clear] call.
  int clearCount = 0;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    saveCount++;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    clearCount++;
  }
}
