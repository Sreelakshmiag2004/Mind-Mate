import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/vault/vault_lock_model.dart';

/// The only layer in the app that knows how the Vault lock actually talks
/// to the FastAPI backend — `vault_password.dart` calls methods on this
/// class, never [ApiClient] directly, matching the pattern
/// `ShoutoutRepository`/`SchedulerRepository` already established
/// (PHASE14C).
///
/// Deliberately does NOT send `user_id`, a Firebase UID, a username, or a
/// password hash on any request — the backend derives the acting user
/// from the Bearer token `ApiClient` attaches, and receives the Vault
/// password itself (never a hash) so it alone can Argon2-hash/verify it
/// (see PHASE14B backend contract report, Section 6). This repository
/// never persists the password anywhere on-device either — each method
/// takes it as a plain `String` argument and forgets it as soon as the
/// HTTP call returns.
class VaultLockRepository {
  VaultLockRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `ShoutoutRepository.instance`/`SchedulerRepository.instance`. Tests
  /// should construct `VaultLockRepository(apiClient: ...)` directly.
  static VaultLockRepository get instance => _instance ??= VaultLockRepository();
  static VaultLockRepository? _instance;

  final ApiClient _apiClient;

  /// `GET /vault/lock` — this user's current Vault-lock state.
  /// `configured: false` (never a 404) means no Vault password has been
  /// created yet.
  Future<VaultLockModel> getState() async {
    final body = await _apiClient.get(ApiEndpoints.vaultLock);
    return VaultLockModel.fromJson(body!);
  }

  /// `POST /vault/lock` — creates this user's Vault password. Throws
  /// [ConflictException] (409) if one already exists; there is
  /// deliberately no "change password" call in this phase (see PHASE14C
  /// implementation report, "Limitations/deferred items").
  Future<VaultLockModel> createLock(String password) async {
    final body = await _apiClient.post(ApiEndpoints.vaultLock, data: {'password': password});
    return VaultLockModel.fromJson(body!);
  }

  /// `POST /vault/unlock` — verifies [password] against the backend's
  /// Argon2 hash. On success, the backend itself advances
  /// `last_viewed_at`/`previous_viewed_at` and returns the updated state;
  /// this method never writes those anywhere itself. Throws
  /// [UnauthorizedException] (401) for any incorrect attempt — including
  /// when no Vault lock has been created yet — never revealing which of
  /// those two happened (PHASE14B backend contract report, Section 5/7).
  Future<VaultLockModel> unlock(String password) async {
    final body = await _apiClient.post(ApiEndpoints.vaultUnlock, data: {'password': password});
    return VaultLockModel.fromJson(body!);
  }
}
