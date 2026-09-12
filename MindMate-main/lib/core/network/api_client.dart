import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';

/// Thin, centralized HTTP layer over Dio.
///
/// This is the ONLY class in the app that is allowed to know about Dio,
/// HTTP headers, or JSON-over-the-wire details — everything above it
/// (repositories, and above them, screens) talks only in typed models and
/// [ApiException]. Concretely, this class owns three things a
/// screen-by-screen implementation would otherwise have to repeat
/// everywhere (see PHASE6_INTEGRATION_AUDIT.md, Step 8):
///
/// 1. Attaching `Authorization: Bearer <access_token>` to every request
///    that needs it (`requiresAuth: true`, the default).
/// 2. Transparently refreshing an expired access token on a 401 and
///    retrying the original request exactly once — see
///    [_handleUnauthorized] for the full, tested state machine, including
///    why concurrent requests share a single in-flight refresh.
/// 3. Converting every Dio failure into a typed [ApiException] so nothing
///    above this layer ever catches a raw [DioException].
class ApiClient {
  ApiClient({Dio? dio, TokenStorage? tokenStorage, String? baseUrl})
    : _tokenStorage = tokenStorage ?? SecureTokenStorage(),
      _dio = dio ?? Dio() {
    // Applied unconditionally — including to an injected `dio` (tests pass
    // one to swap in a fake HttpClientAdapter) — rather than only when this
    // constructor builds its own Dio instance. Without this, Dio's default
    // validateStatus (2xx/3xx only) routes any 4xx/5xx straight to its own
    // error path and `_rejectErrorStatusCodes` below — where the 401 ->
    // refresh -> retry logic actually lives — never runs at all.
    if (baseUrl != null) {
      _dio.options.baseUrl = baseUrl;
    } else if (_dio.options.baseUrl.isEmpty) {
      _dio.options.baseUrl = AppConfig.apiBaseUrl;
    }
    _dio.options.connectTimeout = AppConfig.requestTimeout;
    _dio.options.receiveTimeout = AppConfig.requestTimeout;
    _dio.options.sendTimeout = AppConfig.requestTimeout;
    _dio.options.headers = {..._dio.options.headers, 'Content-Type': 'application/json'};
    _dio.options.validateStatus = (_) => true;

    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _attachAuthHeader, onResponse: _rejectErrorStatusCodes),
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Non-null exactly while a refresh is in flight. Every 401 that arrives
  /// while this is set awaits the SAME future instead of starting its own
  /// refresh call — see [_handleUnauthorized]. This is what turns "five
  /// concurrent requests all get a 401 at once" into one `/auth/refresh`
  /// call instead of five (each of which, per the backend's refresh-token
  /// *rotation* behavior confirmed in `backend/tests/test_auth.py`
  /// (`test_reusing_a_rotated_refresh_token_is_rejected`), would invalidate
  /// the one before it and fail).
  Future<bool>? _refreshInFlight;

  Future<Map<String, dynamic>?> get(String path, {Map<String, dynamic>? queryParameters, bool requiresAuth = true}) =>
      _send('GET', path, queryParameters: queryParameters, requiresAuth: requiresAuth);

  Future<Map<String, dynamic>?> post(String path, {Object? data, bool requiresAuth = true}) =>
      _send('POST', path, data: data, requiresAuth: requiresAuth);

  Future<Map<String, dynamic>?> patch(String path, {Object? data, bool requiresAuth = true}) =>
      _send('PATCH', path, data: data, requiresAuth: requiresAuth);

  /// PHASE11B: added for Scheduler's whole-day `PUT /scheduler/{entry_date}`
  /// replace — the first caller in the app that needs a `PUT` rather than a
  /// `PATCH`. Goes through the same [_send] every other verb uses, so it
  /// gets identical Bearer-header attachment, 401-refresh-retry, and
  /// [ApiException] mapping; purely additive, no existing caller is
  /// affected.
  Future<Map<String, dynamic>?> put(String path, {Object? data, bool requiresAuth = true}) =>
      _send('PUT', path, data: data, requiresAuth: requiresAuth);

  Future<Map<String, dynamic>?> delete(String path, {Object? data, bool requiresAuth = true}) =>
      _send('DELETE', path, data: data, requiresAuth: requiresAuth);

  /// Like [get], but for the handful of endpoints whose response body is a
  /// bare JSON array rather than an object — currently only
  /// `GET /checklists/items` (`list[ChecklistItemRead]`; every other
  /// list-shaped endpoint this app calls, e.g. `/journals`/`/moods`, is
  /// `Page[T]`-wrapped and goes through [get] instead). [_send]/[get]
  /// deliberately reject a bare-array body (see [_send]'s own comment on
  /// that), so this is a separate, minimal, purely additive method rather
  /// than a behavior change to [_send] — every existing caller of
  /// [get]/[post]/[patch]/[delete] is unaffected. Still goes through
  /// `_dio`, so it gets the same Bearer-header attachment and transparent
  /// 401-refresh-retry as every other call (that logic lives in the
  /// interceptors registered on `_dio` itself, not in [_send]).
  Future<List<dynamic>?> getList(String path, {Map<String, dynamic>? queryParameters, bool requiresAuth = true}) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        queryParameters: queryParameters,
        options: Options(method: 'GET', extra: {'requiresAuth': requiresAuth}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }

    if (response.data == null) return null;
    if (response.data is String && (response.data as String).isEmpty) return null;
    if (response.data is List<dynamic>) return response.data as List<dynamic>;
    throw UnknownApiException('Unexpected response shape from the server.', statusCode: response.statusCode);
  }

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required bool requiresAuth,
  }) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, extra: {'requiresAuth': requiresAuth}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }

    // A 204 (logout's own response — verified against a live backend, see
    // PHASE7_API_INTEGRATION.md) has no body at all; Dio's transformer
    // represents that as an empty string rather than null since there is no
    // JSON content-type header to key off of.
    if (response.data == null) return null;
    if (response.data is String && (response.data as String).isEmpty) return null;
    if (response.data is Map<String, dynamic>) return response.data as Map<String, dynamic>;
    // A handful of endpoints (list responses) return a bare JSON array;
    // none of the auth endpoints this phase integrates do, but this keeps
    // `_send`'s contract honest rather than silently swallowing the case.
    throw UnknownApiException(
      'Unexpected response shape from the server.',
      statusCode: response.statusCode,
    );
  }

  void _attachAuthHeader(RequestOptions options, RequestInterceptorHandler handler) async {
    final requiresAuth = options.extra['requiresAuth'] != false;
    if (requiresAuth) {
      final accessToken = await _tokenStorage.readAccessToken();
      if (accessToken != null) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
    }
    handler.next(options);
  }

  /// `validateStatus` above accepts every status code so this interceptor
  /// can implement the refresh-and-retry flow itself (Dio's error-handling
  /// path is what makes an in-place retry straightforward); this step is
  /// what turns a non-2xx response back into the `DioException` the rest of
  /// the app expects, for every status this phase doesn't specifically
  /// handle here.
  void _rejectErrorStatusCodes(Response response, ResponseInterceptorHandler handler) async {
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 200 && statusCode < 300) {
      return handler.next(response);
    }

    final options = response.requestOptions;
    final requiresAuth = options.extra['requiresAuth'] != false;
    final alreadyRetried = options.extra['__retried'] == true;
    final isRefreshCall = options.path == ApiEndpoints.refresh;

    if (statusCode == 401 && requiresAuth && !alreadyRetried && !isRefreshCall) {
      final retried = await _handleUnauthorized(options);
      if (retried != null) {
        return handler.resolve(retried);
      }
    }

    handler.reject(
      DioException(requestOptions: options, response: response, type: DioExceptionType.badResponse),
    );
  }

  /// Attempts exactly one token refresh (deduplicated across concurrent
  /// callers via [_refreshInFlight]) and, if it succeeds, retries the
  /// original request exactly once with the new access token. Returns the
  /// retried response on success, or null if either the refresh or the
  /// retry itself failed — in both cases the caller (`_rejectErrorStatusCodes`)
  /// falls back to rejecting with the original 401, which every public
  /// method above maps to [UnauthorizedException].
  Future<Response<dynamic>?> _handleUnauthorized(RequestOptions failedRequest) async {
    _refreshInFlight ??= _performRefresh();
    final refreshSucceeded = await _refreshInFlight!;

    if (!refreshSucceeded) return null;

    // Only `__retried` needs to be set here — `_dio.fetch` re-runs the full
    // interceptor chain, so `_attachAuthHeader` attaches the freshly
    // refreshed access token from storage on its own; setting it here too
    // would just be immediately overwritten.
    final retryOptions = failedRequest.copyWith(extra: {...failedRequest.extra, '__retried': true});
    try {
      return await _dio.fetch<dynamic>(retryOptions);
    } on DioException {
      return null;
    }
  }

  Future<bool> _performRefresh() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) return false;

      final Response<dynamic> response;
      try {
        response = await _dio.post<dynamic>(
          ApiEndpoints.refresh,
          data: {'refresh_token': refreshToken},
          options: Options(extra: {'requiresAuth': false}),
        );
      } on DioException {
        // `_rejectErrorStatusCodes` deliberately never retries the refresh
        // call itself (see `isRefreshCall` there — refreshing a refresh
        // would risk an infinite loop), so a non-2xx here (e.g. the refresh
        // token was already rotated out, or has expired — see
        // `backend/tests/test_auth.py::test_reusing_a_rotated_refresh_token_is_rejected`)
        // surfaces as a thrown DioException rather than a response this
        // method could inspect the status code of directly.
        await _tokenStorage.clear();
        return false;
      }

      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        await _tokenStorage.clear();
        return false;
      }

      final body = response.data as Map<String, dynamic>;
      final newAccessToken = body['access_token'] as String?;
      final newRefreshToken = body['refresh_token'] as String?;
      if (newAccessToken == null || newRefreshToken == null) {
        await _tokenStorage.clear();
        return false;
      }

      await _tokenStorage.saveTokens(accessToken: newAccessToken, refreshToken: newRefreshToken);
      return true;
    } finally {
      _refreshInFlight = null;
    }
  }
}
