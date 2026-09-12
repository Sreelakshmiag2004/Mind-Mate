import 'package:dio/dio.dart';

/// Centralized mapping from a failed HTTP call to a typed, UI-safe
/// exception.
///
/// The backend's own error shape (verified directly against a running
/// instance — see PHASE7_API_INTEGRATION.md, "API contract verified
/// against a live server") is either:
///
///   `{"detail": "<human-readable string>"}`                 — most errors
///   `{"detail": [{"loc": [...], "msg": "...", "type": "..."}]}`  — 422 only
///
/// `message` on every subclass below is always safe to show directly in a
/// snackbar: it is either the backend's own `detail` string (already
/// written to be user-facing — see e.g. `auth.py`'s login handler, which
/// deliberately returns the same message for "unknown email" and "wrong
/// password") or a generic fallback for cases (network failure, an
/// unparseable response, a 5xx) where the backend gave nothing suitable to
/// show a user. Nothing here ever surfaces a stack trace, a raw exception
/// string, or an internal error code.
abstract class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// Null for errors that never got an HTTP response at all (timeout, no
  /// connection, DNS failure, ...).
  final int? statusCode;

  @override
  String toString() => message;

  /// Maps a failed Dio call to the right typed subclass. This is the only
  /// place in the app that should ever inspect a [DioException] directly —
  /// everything above [ApiClient] deals only in [ApiException].
  factory ApiException.fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException(
          'The request took too long to respond. Check your connection and try again.',
        );
      case DioExceptionType.connectionError:
        return const NetworkException(
          'Could not reach the server. Check your connection and try again.',
        );
      case DioExceptionType.cancel:
        return const NetworkException('The request was cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkException('Could not verify the server\'s security certificate.');
      case DioExceptionType.badResponse:
        return _fromResponse(error);
      case DioExceptionType.unknown:
      default:
        return const NetworkException(
          'Something went wrong while contacting the server. Check your connection and try again.',
        );
    }
  }

  static ApiException _fromResponse(DioException error) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final detail = _extractDetail(response?.data);

    switch (statusCode) {
      case 400:
        return BadRequestException(detail ?? 'That request was invalid.', statusCode: statusCode);
      case 401:
        return UnauthorizedException(
          detail ?? 'Your session has expired. Please log in again.',
          statusCode: statusCode,
        );
      case 403:
        return ForbiddenException(detail ?? 'You don\'t have permission to do that.', statusCode: statusCode);
      case 404:
        return NotFoundException(detail ?? 'That could not be found.', statusCode: statusCode);
      case 409:
        return ConflictException(detail ?? 'That already exists.', statusCode: statusCode);
      case 422:
        return ValidationException.fromResponseData(response?.data);
      case 429:
        return RateLimitException(
          detail ?? 'Too many attempts. Please wait a moment and try again.',
          statusCode: statusCode,
        );
      case 500:
      case 502:
      case 503:
        return ServerException(
          'The server is temporarily unavailable. Please try again shortly.',
          statusCode: statusCode,
        );
      default:
        return UnknownApiException(
          detail ?? 'An unexpected error occurred (status $statusCode).',
          statusCode: statusCode,
        );
    }
  }

  /// Pulls the backend's `detail` string out of a response body, when it is
  /// a plain string (every non-422 error). Returns null for anything else
  /// (missing body, a 422's list-shaped `detail`, or a body that isn't the
  /// backend's documented shape at all) rather than guessing.
  static String? _extractDetail(dynamic data) {
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }
}

/// No HTTP response was ever received: timeout, no connectivity, DNS
/// failure, TLS failure, or the request was cancelled.
class NetworkException extends ApiException {
  const NetworkException(super.message) : super(statusCode: null);
}

/// 400 — the request was malformed in a way that isn't a 422 field
/// validation error (e.g. a bad query parameter).
class BadRequestException extends ApiException {
  const BadRequestException(super.message, {required super.statusCode});
}

/// 401 — missing, invalid, or expired credentials. [ApiClient]'s
/// interceptor already tries a refresh before this ever reaches calling
/// code for an authenticated request; seeing this means the refresh itself
/// also failed (or the call was one, like login, where a 401 is expected
/// user-facing behavior, not a session problem).
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message, {required super.statusCode});
}

/// 403 — the caller is authenticated but not allowed to do this.
class ForbiddenException extends ApiException {
  const ForbiddenException(super.message, {required super.statusCode});
}

/// 404 — resource doesn't exist (or, per the backend's own IDOR-resistance
/// design used throughout, isn't the caller's).
class NotFoundException extends ApiException {
  const NotFoundException(super.message, {required super.statusCode});
}

/// 409 — a uniqueness rule was violated (e.g. registering an email that's
/// already in use).
class ConflictException extends ApiException {
  const ConflictException(super.message, {required super.statusCode});
}

/// 422 — Pydantic request-body/query validation failed. [fieldErrors] maps
/// each field's dotted path (e.g. `"password"`, joined from the backend's
/// `loc` array with the leading `"body"`/`"query"` segment dropped) to the
/// list of messages reported for it, so a form can highlight the specific
/// field(s) involved rather than showing one generic error.
class ValidationException extends ApiException {
  const ValidationException(super.message, this.fieldErrors) : super(statusCode: 422);

  final Map<String, List<String>> fieldErrors;

  factory ValidationException.fromResponseData(dynamic data) {
    final fieldErrors = <String, List<String>>{};
    if (data is Map && data['detail'] is List) {
      for (final entry in data['detail'] as List) {
        if (entry is! Map) continue;
        final loc = entry['loc'];
        final msg = entry['msg'];
        if (msg is! String) continue;
        final field = (loc is List && loc.isNotEmpty) ? loc.last.toString() : 'request';
        fieldErrors.putIfAbsent(field, () => []).add(msg);
      }
    }
    final message = fieldErrors.isEmpty
        ? 'Please check the information you entered and try again.'
        : fieldErrors.entries.map((e) => '${e.key}: ${e.value.join(', ')}').join('; ');
    return ValidationException(message, fieldErrors);
  }
}

/// 429 — the caller is being rate-limited.
class RateLimitException extends ApiException {
  const RateLimitException(super.message, {required super.statusCode});
}

/// 500 / 502 / 503 — the backend itself failed. Deliberately never shows
/// the raw body (which could contain a stack trace in a misconfigured
/// deployment) — always a fixed, generic message.
class ServerException extends ApiException {
  const ServerException(super.message, {required super.statusCode});
}

/// Any status code this client doesn't have a specific case for.
class UnknownApiException extends ApiException {
  const UnknownApiException(super.message, {required super.statusCode});
}
