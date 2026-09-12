import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/secure_storage_service.dart';
import '../models/auth/me_response_model.dart';
import '../models/auth/token_response_model.dart';

/// The only layer in the app that knows how authentication against the
/// FastAPI backend actually works. Screens call methods on this class —
/// never [ApiClient] directly, never a URL, a header, or a JSON key (see
/// PHASE6_INTEGRATION_AUDIT.md, Step 5/9).
///
/// Deliberately contains zero Firebase code, per this phase's rules — see
/// PHASE7_API_INTEGRATION.md, section P, for exactly what that does and
/// does not mean for the rest of the app during this transitional phase.
class AuthRepository {
  AuthRepository({ApiClient? apiClient, TokenStorage? tokenStorage})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? SecureTokenStorage();

  /// Lazily-constructed app-wide singleton. There is no dependency-injection
  /// package in this project (see PHASE6_INTEGRATION_AUDIT.md, Step 8 —
  /// none was added here either, to keep this phase's new-dependency
  /// footprint to exactly what Step 4/6 asked for) and a second,
  /// independently-constructed `AuthRepository` would mean a second Dio
  /// instance with its own `_refreshInFlight` lock — i.e. a second,
  /// uncoordinated authority over the same stored tokens. Screens should
  /// use this singleton; tests should construct `AuthRepository(...)`
  /// directly with fakes injected.
  static AuthRepository get instance => _instance ??= AuthRepository();
  static AuthRepository? _instance;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  /// `POST /auth/register`. Stores the returned tokens on success — the
  /// backend treats registration as an immediate login (see
  /// `backend/app/api/routes/auth.py`), so there is no separate "now log
  /// in" step to perform afterward.
  ///
  /// Throws [ValidationException] (422 — bad email/password shape),
  /// [ConflictException] (409 — email already registered), or another
  /// [ApiException] subtype for anything else. Never invents a validation
  /// rule the backend doesn't enforce itself — see `RegisterRequest` in
  /// `app/schemas/auth.py` for the exact password policy (min 8 characters,
  /// at least one letter, at least one digit) this call defers to.
  Future<TokenResponseModel> register({required String email, required String password, String? fullName}) async {
    final body = await _apiClient.post(
      ApiEndpoints.register,
      requiresAuth: false,
      data: {
        'email': email,
        'password': password,
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
      },
    );
    final tokens = TokenResponseModel.fromJson(body!);
    await _tokenStorage.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    return tokens;
  }

  /// `POST /auth/login`. Throws [UnauthorizedException] for either an
  /// unknown email or a wrong password — the backend deliberately returns
  /// the identical response for both (see `auth.py`'s `login` handler) so
  /// this call can't be used to enumerate registered emails; this
  /// repository preserves that ambiguity rather than trying to guess which
  /// one happened.
  Future<TokenResponseModel> login({required String email, required String password}) async {
    final body = await _apiClient.post(
      ApiEndpoints.login,
      requiresAuth: false,
      data: {'email': email, 'password': password},
    );
    final tokens = TokenResponseModel.fromJson(body!);
    await _tokenStorage.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    return tokens;
  }

  /// Explicit, on-demand refresh. [ApiClient] already performs this
  /// automatically and transparently whenever an authenticated call gets a
  /// 401 (see `api_client.dart::_performRefresh`) — that internal path is
  /// what every ordinary authenticated request relies on, and callers
  /// should not need to call this directly. This method exists as a
  /// separate, explicit entry point for the cases that aren't "a request
  /// just failed" — e.g. a future "refresh proactively when the app
  /// resumes" hook — and to give the repository's public surface a
  /// directly testable `refresh()`, matching every other operation here.
  Future<bool> refresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final body = await _apiClient.post(
        ApiEndpoints.refresh,
        requiresAuth: false,
        data: {'refresh_token': refreshToken},
      );
      final tokens = TokenResponseModel.fromJson(body!);
      await _tokenStorage.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
      return true;
    } on ApiException {
      await _tokenStorage.clear();
      return false;
    }
  }

  /// `POST /auth/logout`, then unconditionally clears local tokens.
  ///
  /// The server call is best-effort: if it fails (no connectivity, the
  /// refresh token was already invalid, a 5xx), the device must still end
  /// up logged out locally — the alternative (leaving the app in a state
  /// where the UI says "logged out" but a valid token is still sitting in
  /// secure storage) is worse than a session that technically remains
  /// valid server-side until it naturally expires (`REFRESH_TOKEN_EXPIRE_DAYS`,
  /// 30 days by default).
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _apiClient.post(ApiEndpoints.logout, data: {'refresh_token': refreshToken});
      } on ApiException {
        // Intentionally swallowed — see method doc.
      }
    }
    await _tokenStorage.clear();
  }

  /// `GET /auth/me`. Throws [UnauthorizedException] if there is no valid
  /// session (and [ApiClient]'s own transparent-refresh attempt, if one was
  /// possible, has already failed by the time this exception reaches here).
  Future<MeResponseModel> getCurrentUser() async {
    final body = await _apiClient.get(ApiEndpoints.me);
    return MeResponseModel.fromJson(body!);
  }

  /// Whether an access token is currently stored — a cheap, local check
  /// that does NOT verify the token is still valid server-side. Used to
  /// decide whether [restoreSession] is worth attempting at all.
  Future<bool> hasStoredSession() => _tokenStorage.readAccessToken().then((token) => token != null);

  /// Startup session restoration (see PHASE7_API_INTEGRATION.md, section
  /// O). Returns the current user if a stored session is still valid — an
  /// expired access token is refreshed transparently by [ApiClient]'s own
  /// interceptor before this ever has to know that happened — or `null` if
  /// there is no stored session, or the stored one could not be restored at
  /// all (refresh itself failed, e.g. the refresh token expired or was
  /// already used).
  ///
  /// Deliberately reuses [getCurrentUser] rather than re-implementing
  /// "expired -> refresh -> retry" a second time here: [ApiClient] already
  /// owns that state machine for every authenticated call, `/auth/me`
  /// included, so there is exactly one implementation of it in the app.
  ///
  /// A network/server failure (no connectivity, a 5xx) is deliberately
  /// NOT treated the same as "no session" — it is rethrown so the caller
  /// can distinguish "you are logged out" from "we couldn't check right
  /// now," and tokens are left untouched in that case so a later retry can
  /// still succeed without forcing the user through login again.
  Future<MeResponseModel?> restoreSession() async {
    if (!await hasStoredSession()) return null;

    try {
      return await getCurrentUser();
    } on UnauthorizedException {
      await _tokenStorage.clear();
      return null;
    }
  }
}
