import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/mood_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _entryJson({
  String id = '9d1a2b3c-0001-4a11-8b11-000000000001',
  String entryDate = '2025-01-05',
  int moodValue = 72,
}) => {
  'id': id,
  'user_id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
  'entry_date': entryDate,
  'mood_value': moodValue,
  'created_at': '2025-01-05T10:00:00',
  'updated_at': '2025-01-05T10:00:00',
};

void main() {
  late MockApiClient apiClient;
  late MoodRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = MoodRepository(apiClient: apiClient);
  });

  group('getForDate', () {
    test('requests a one-day inclusive range with limit=1, offset=0', () async {
      when(
        () => apiClient.get(ApiEndpoints.moods, queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {
        'items': [_entryJson()],
        'total': 1,
        'limit': 1,
        'offset': 0,
      });

      await repository.getForDate(DateTime(2025, 1, 5));

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.moods, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['start_date'], '2025-01-05');
      expect(captured['end_date'], '2025-01-05');
      expect(captured['limit'], 1);
      expect(captured['offset'], 0);
    });

    test('returns null when no entry exists for that date', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 1, 'offset': 0});

      final entry = await repository.getForDate(DateTime(2025, 1, 5));

      expect(entry, isNull);
    });
  });

  group('getEntriesForRange', () {
    test('sends the formatted start/end dates and default pagination', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {
        'items': [_entryJson(id: 'id-1', entryDate: '2025-01-03'), _entryJson(id: 'id-2', entryDate: '2025-01-01')],
        'total': 2,
        'limit': 100,
        'offset': 0,
      });

      final entries = await repository.getEntriesForRange(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 15),
      );

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.moods, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['start_date'], '2025-01-01');
      expect(captured['end_date'], '2025-01-15');
      expect(captured['limit'], 100);
      expect(captured['offset'], 0);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.id), ['id-1', 'id-2']);
    });

    test('forwards a custom limit/offset (pagination parameters)', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 10, 'offset': 20});

      await repository.getEntriesForRange(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
        limit: 10,
        offset: 20,
      );

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.moods, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['limit'], 10);
      expect(captured['offset'], 20);
    });

    test('returns an empty list when the backend returns no items', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 100, 'offset': 0});

      final entries = await repository.getEntriesForRange(startDate: DateTime(2025, 1, 1), endDate: DateTime(2025, 1, 31));

      expect(entries, isEmpty);
    });
  });

  group('getById', () {
    test('GETs /moods/{id} and parses the response', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _entryJson(id: 'abc-123'));

      final entry = await repository.getById('abc-123');

      verify(() => apiClient.get(ApiEndpoints.moodById('abc-123'))).called(1);
      expect(entry.id, 'abc-123');
    });

    test('an unknown id 404s as NotFoundException', () async {
      when(() => apiClient.get(any())).thenThrow(const NotFoundException('Mood entry not found', statusCode: 404));

      await expectLater(repository.getById('missing'), throwsA(isA<NotFoundException>()));
    });
  });

  group('create', () {
    test('POSTs entry_date/mood_value and never sends user_id', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 72);

      final sentBody = verify(() => apiClient.post(ApiEndpoints.moods, data: captureAny(named: 'data')))
          .captured
          .single as Map;
      expect(sentBody['entry_date'], '2025-01-05');
      expect(sentBody['mood_value'], 72);
      expect(sentBody.containsKey('user_id'), isFalse);
      expect(sentBody.length, 2, reason: 'POST body should only ever contain entry_date and mood_value');
    });

    test('returns the created MoodModel parsed from the response', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _entryJson(id: 'new-id', moodValue: 55));

      final created = await repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 55);

      expect(created.id, 'new-id');
      expect(created.moodValue, 55);
    });

    test('a duplicate-date 409 propagates as ConflictException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A mood entry for 2025-01-05 already exists', statusCode: 409));

      await expectLater(
        repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<ConflictException>()),
      );
    });

    test('an out-of-range mood_value 422 propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('mood_value: must be <= 100', {
          'mood_value': ['must be <= 100'],
        }),
      );

      await expectLater(
        repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 150),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a 401 that survives ApiClient\'s own refresh propagates as UnauthorizedException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(
        repository.create(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('update', () {
    test('PATCHes /moods/{id} and only sends the fields provided', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.update(id: 'abc-123', moodValue: 95);

      final sentBody = verify(
        () => apiClient.patch(ApiEndpoints.moodById('abc-123'), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody['mood_value'], 95);
      expect(sentBody.containsKey('entry_date'), isFalse);
      expect(sentBody.containsKey('user_id'), isFalse);
    });

    test('uses the backend id passed in, never constructs one from a date', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.update(id: 'the-real-uuid', moodValue: 10);

      verify(() => apiClient.patch(ApiEndpoints.moodById('the-real-uuid'), data: any(named: 'data'))).called(1);
    });

    test('another user\'s / unknown id 404s as NotFoundException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Mood entry not found', statusCode: 404));

      await expectLater(
        repository.update(id: 'not-mine', moodValue: 1),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('moving to an already-taken date 409s as ConflictException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A mood entry for 2025-01-01 already exists', statusCode: 409));

      await expectLater(
        repository.update(id: 'abc-123', entryDate: DateTime(2025, 1, 1)),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('createOrUpdate (PHASE9 Step 6/Step 4 pattern)', () {
    test('POSTs first, and returns the created MoodModel on success', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson(moodValue: 80));

      final result = await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), moodValue: 80);

      verify(() => apiClient.post(ApiEndpoints.moods, data: any(named: 'data'))).called(1);
      verifyNever(() => apiClient.patch(any(), data: any(named: 'data')));
      expect(result.moodValue, 80);
    });

    test(
      'on an unexpected 409 from POST, looks the entry up by date and PATCHes it instead of retrying POST',
      () async {
        var postCallCount = 0;
        when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async {
          postCallCount++;
          throw const ConflictException('A mood entry for 2025-01-05 already exists', statusCode: 409);
        });
        when(
          () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer((_) async => {
          'items': [_entryJson(id: 'existing-id', moodValue: 40)],
          'total': 1,
          'limit': 1,
          'offset': 0,
        });
        when(
          () => apiClient.patch(any(), data: any(named: 'data')),
        ).thenAnswer((_) async => _entryJson(id: 'existing-id', moodValue: 65));

        final result = await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), moodValue: 65);

        expect(postCallCount, 1, reason: 'POST must not be retried after a 409');
        verify(() => apiClient.patch(ApiEndpoints.moodById('existing-id'), data: any(named: 'data'))).called(1);
        expect(result.id, 'existing-id');
        expect(result.moodValue, 65);
      },
    );

    test('rethrows the 409 if a fresh getForDate somehow still finds nothing', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A mood entry for 2025-01-05 already exists', statusCode: 409));
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 1, 'offset': 0});

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a generic ApiException from create is not treated as the 409 fallback case', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ServerException('The server is temporarily unavailable.', statusCode: 500));

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<ServerException>()),
      );
      verifyNever(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters')));
    });

    test('a network failure from create propagates without attempting the 409 fallback', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), moodValue: 50),
        throwsA(isA<NetworkException>()),
      );
      verifyNever(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters')));
    });
  });
}
