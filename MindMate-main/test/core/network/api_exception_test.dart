import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_exception.dart';

DioException _errorWithStatus(int statusCode, dynamic data, {RequestOptions? options}) {
  final requestOptions = options ?? RequestOptions(path: '/whatever');
  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: requestOptions, statusCode: statusCode, data: data),
  );
}

void main() {
  group('ApiException.fromDioException — network-level failures (no response)', () {
    test('connection timeout maps to NetworkException', () {
      final error = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionTimeout);
      expect(ApiException.fromDioException(error), isA<NetworkException>());
    });

    test('connection error maps to NetworkException', () {
      final error = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
      expect(ApiException.fromDioException(error), isA<NetworkException>());
    });

    test('receive timeout maps to NetworkException', () {
      final error = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.receiveTimeout);
      expect(ApiException.fromDioException(error), isA<NetworkException>());
    });

    test('a network exception carries no status code', () {
      final error = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
      expect(ApiException.fromDioException(error).statusCode, isNull);
    });
  });

  group('ApiException.fromDioException — status-code mapping', () {
    test('400 maps to BadRequestException', () {
      final exception = ApiException.fromDioException(_errorWithStatus(400, {'detail': 'bad'}));
      expect(exception, isA<BadRequestException>());
      expect(exception.statusCode, 400);
      expect(exception.message, 'bad');
    });

    test('401 maps to UnauthorizedException and preserves the backend detail message', () {
      final exception = ApiException.fromDioException(
        _errorWithStatus(401, {'detail': 'Incorrect email or password'}),
      );
      expect(exception, isA<UnauthorizedException>());
      expect(exception.message, 'Incorrect email or password');
    });

    test('403 maps to ForbiddenException', () {
      expect(ApiException.fromDioException(_errorWithStatus(403, {'detail': 'nope'})), isA<ForbiddenException>());
    });

    test('404 maps to NotFoundException', () {
      expect(ApiException.fromDioException(_errorWithStatus(404, {'detail': 'nope'})), isA<NotFoundException>());
    });

    test('409 maps to ConflictException', () {
      final exception = ApiException.fromDioException(
        _errorWithStatus(409, {'detail': 'An account with this email already exists'}),
      );
      expect(exception, isA<ConflictException>());
      expect(exception.message, 'An account with this email already exists');
    });

    test('429 maps to RateLimitException', () {
      expect(ApiException.fromDioException(_errorWithStatus(429, {'detail': 'slow down'})), isA<RateLimitException>());
    });

    test('500 maps to ServerException with a fixed, generic message (never the raw body)', () {
      final exception = ApiException.fromDioException(
        _errorWithStatus(500, {'detail': 'Traceback (most recent call last): ...'}),
      );
      expect(exception, isA<ServerException>());
      expect(exception.message, isNot(contains('Traceback')));
    });

    test('502 and 503 also map to ServerException', () {
      expect(ApiException.fromDioException(_errorWithStatus(502, {'detail': 'x'})), isA<ServerException>());
      expect(ApiException.fromDioException(_errorWithStatus(503, {'detail': 'x'})), isA<ServerException>());
    });

    test('an unrecognized status code falls back to UnknownApiException', () {
      final exception = ApiException.fromDioException(_errorWithStatus(451, {'detail': 'unavailable for legal reasons'}));
      expect(exception, isA<UnknownApiException>());
      expect(exception.statusCode, 451);
    });

    test('a missing/non-string detail falls back to a safe generic message instead of crashing', () {
      final exception = ApiException.fromDioException(_errorWithStatus(400, {'not_detail': 'oops'}));
      expect(exception.message, isNotEmpty);
    });
  });

  group('ValidationException (422)', () {
    test('parses field-level errors from the backend\'s documented detail-list shape', () {
      final data = {
        'detail': [
          {
            'type': 'string_too_short',
            'loc': ['body', 'password'],
            'msg': 'String should have at least 8 characters',
          },
          {
            'type': 'value_error',
            'loc': ['body', 'email'],
            'msg': 'value is not a valid email address',
          },
        ],
      };

      final exception = ApiException.fromDioException(_errorWithStatus(422, data));

      expect(exception, isA<ValidationException>());
      final validation = exception as ValidationException;
      expect(validation.statusCode, 422);
      expect(validation.fieldErrors['password'], contains('String should have at least 8 characters'));
      expect(validation.fieldErrors['email'], contains('value is not a valid email address'));
      expect(validation.message, contains('password'));
      expect(validation.message, contains('email'));
    });

    test('multiple errors on the same field are all preserved', () {
      final data = {
        'detail': [
          {
            'loc': ['body', 'password'],
            'msg': 'too short',
          },
          {
            'loc': ['body', 'password'],
            'msg': 'missing a digit',
          },
        ],
      };

      final validation = ApiException.fromDioException(_errorWithStatus(422, data)) as ValidationException;
      expect(validation.fieldErrors['password'], ['too short', 'missing a digit']);
    });

    test('an empty or malformed detail list still produces a safe, non-empty message', () {
      final validation = ApiException.fromDioException(_errorWithStatus(422, {'detail': []})) as ValidationException;
      expect(validation.fieldErrors, isEmpty);
      expect(validation.message, isNotEmpty);
    });
  });
}
