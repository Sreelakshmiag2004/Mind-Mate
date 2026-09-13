import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/vault_lock_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _stateJson({
  bool configured = true,
  String? lastViewedAt,
  String? previousViewedAt,
}) => {
  'configured': configured,
  'last_viewed_at': lastViewedAt,
  'previous_viewed_at': previousViewedAt,
};

void main() {
  late MockApiClient apiClient;
  late VaultLockRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = VaultLockRepository(apiClient: apiClient);
  });

  group('getState', () {
    test('GETs /vault/lock', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _stateJson(configured: false));

      await repository.getState();

      verify(() => apiClient.get(ApiEndpoints.vaultLock)).called(1);
    });

    test('parses an unconfigured state (never a 404/error)', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _stateJson(configured: false));

      final state = await repository.getState();

      expect(state.configured, isFalse);
      expect(state.lastViewedAt, isNull);
    });

    test('parses a configured state', () async {
      when(
        () => apiClient.get(any()),
      ).thenAnswer((_) async => _stateJson(configured: true, lastViewedAt: '2025-01-06T09:15:00+00:00'));

      final state = await repository.getState();

      expect(state.configured, isTrue);
      expect(state.lastViewedAt, isNotNull);
    });

    test('a 401 propagates as UnauthorizedException', () async {
      when(
        () => apiClient.get(any()),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(repository.getState(), throwsA(isA<UnauthorizedException>()));
    });

    test('a network failure propagates as NetworkException', () async {
      when(() => apiClient.get(any())).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.getState(), throwsA(isA<NetworkException>()));
    });
  });

  group('createLock', () {
    test('POSTs /vault/lock with exactly {"password": ...} — no user_id, UID, username, or hash', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _stateJson(configured: true),
      );

      await repository.createLock('correcthorse');

      final sentBody = verify(
        () => apiClient.post(ApiEndpoints.vaultLock, data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody, {'password': 'correcthorse'});
      expect(sentBody.containsKey('user_id'), isFalse);
      expect(sentBody.containsKey('uid'), isFalse);
      expect(sentBody.containsKey('username'), isFalse);
      expect(sentBody.containsKey('password_hash'), isFalse);
    });

    test('returns the created (configured) state', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _stateJson(configured: true));

      final state = await repository.createLock('correcthorse');

      expect(state.configured, isTrue);
    });

    test('a duplicate create rejected by the backend propagates as ConflictException (409)', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A Vault lock already exists for this user', statusCode: 409));

      await expectLater(repository.createLock('correcthorse'), throwsA(isA<ConflictException>()));
    });

    test('a 422 (e.g. too-short password) propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('password: Password must be at least 6 characters long', {
          'password': ['Password must be at least 6 characters long'],
        }),
      );

      await expectLater(repository.createLock('abc'), throwsA(isA<ValidationException>()));
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.createLock('correcthorse'), throwsA(isA<NetworkException>()));
    });
  });

  group('unlock', () {
    test('POSTs /vault/unlock with exactly {"password": ...} — no user_id, UID, username, or hash', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _stateJson(configured: true, lastViewedAt: '2025-01-06T09:15:00+00:00'),
      );

      await repository.unlock('correcthorse');

      final sentBody = verify(
        () => apiClient.post(ApiEndpoints.vaultUnlock, data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody, {'password': 'correcthorse'});
      expect(sentBody.containsKey('user_id'), isFalse);
      expect(sentBody.containsKey('uid'), isFalse);
      expect(sentBody.containsKey('username'), isFalse);
      expect(sentBody.containsKey('password_hash'), isFalse);
    });

    test('returns the updated state, with last_viewed_at populated', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _stateJson(configured: true, lastViewedAt: '2025-01-06T09:15:00+00:00'));

      final state = await repository.unlock('correcthorse');

      expect(state.lastViewedAt, DateTime.parse('2025-01-06T09:15:00+00:00'));
    });

    test('an incorrect password propagates as UnauthorizedException (401)', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const UnauthorizedException('Incorrect Vault password', statusCode: 401));

      await expectLater(repository.unlock('wrong'), throwsA(isA<UnauthorizedException>()));
    });

    test('a 422 (e.g. empty password) propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('password: field required', {
          'password': ['field required'],
        }),
      );

      await expectLater(repository.unlock(''), throwsA(isA<ValidationException>()));
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.unlock('correcthorse'), throwsA(isA<NetworkException>()));
    });

    test('a 5xx propagates as ServerException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        const ServerException('The server is temporarily unavailable.', statusCode: 500),
      );

      await expectLater(repository.unlock('correcthorse'), throwsA(isA<ServerException>()));
    });
  });
}
