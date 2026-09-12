import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/journal_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _entryJson({
  String id = '9d1a2b3c-0001-4a11-8b11-000000000001',
  String entryDate = '2025-01-05',
  String? title = 'Title',
  String? content = 'Content',
}) => {
  'id': id,
  'user_id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
  'entry_date': entryDate,
  'title': title,
  'content': content,
  'created_at': '2025-01-05T10:00:00',
  'updated_at': '2025-01-05T10:00:00',
};

void main() {
  late MockApiClient apiClient;
  late JournalRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    apiClient = MockApiClient();
    repository = JournalRepository(apiClient: apiClient);
  });

  group('getForDate', () {
    test('requests a one-day inclusive range with limit=1, offset=0', () async {
      when(
        () => apiClient.get(ApiEndpoints.journals, queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {
        'items': [_entryJson()],
        'total': 1,
        'limit': 1,
        'offset': 0,
      });

      await repository.getForDate(DateTime(2025, 1, 5));

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.journals, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['start_date'], '2025-01-05');
      expect(captured['end_date'], '2025-01-05');
      expect(captured['limit'], 1);
      expect(captured['offset'], 0);
    });

    test('returns the matching entry when the list has one item', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {
        'items': [_entryJson(title: 'A good day')],
        'total': 1,
        'limit': 1,
        'offset': 0,
      });

      final entry = await repository.getForDate(DateTime(2025, 1, 5));

      expect(entry, isNotNull);
      expect(entry!.title, 'A good day');
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
    test('sends the formatted start/end dates and parses every returned item', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {
        'items': [
          _entryJson(id: 'id-1', entryDate: '2025-01-03'),
          _entryJson(id: 'id-2', entryDate: '2025-01-01'),
        ],
        'total': 2,
        'limit': 30,
        'offset': 0,
      });

      final entries = await repository.getEntriesForRange(DateTime(2025, 1, 1), DateTime(2025, 1, 3));

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.journals, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['start_date'], '2025-01-01');
      expect(captured['end_date'], '2025-01-03');
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.id), ['id-1', 'id-2']);
    });

    test('returns an empty list when the backend returns no items', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 30, 'offset': 0});

      final entries = await repository.getEntriesForRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31));

      expect(entries, isEmpty);
    });
  });

  group('create', () {
    test('POSTs entry_date/title/content and never sends user_id', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.create(entryDate: DateTime(2025, 1, 5), title: 'Title', content: 'Content');

      final sentBody = verify(() => apiClient.post(ApiEndpoints.journals, data: captureAny(named: 'data')))
          .captured
          .single as Map;
      expect(sentBody['entry_date'], '2025-01-05');
      expect(sentBody['title'], 'Title');
      expect(sentBody['content'], 'Content');
      expect(sentBody.containsKey('user_id'), isFalse);
    });

    test('returns the created JournalModel parsed from the response', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _entryJson(id: 'new-id'));

      final created = await repository.create(entryDate: DateTime(2025, 1, 5));

      expect(created.id, 'new-id');
    });

    test('a duplicate-date 409 propagates as ConflictException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A journal entry for 2025-01-05 already exists', statusCode: 409));

      await expectLater(
        repository.create(entryDate: DateTime(2025, 1, 5)),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a 422 validation failure propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('title: too long', {
          'title': ['too long'],
        }),
      );

      await expectLater(repository.create(entryDate: DateTime(2025, 1, 5)), throwsA(isA<ValidationException>()));
    });
  });

  group('update', () {
    test('PATCHes /journals/{id} and only sends the fields provided', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.update(journalId: 'abc-123', title: 'New title');

      final sentBody = verify(
        () => apiClient.patch(ApiEndpoints.journalById('abc-123'), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody['title'], 'New title');
      expect(sentBody.containsKey('content'), isFalse);
      expect(sentBody.containsKey('entry_date'), isFalse);
      expect(sentBody.containsKey('user_id'), isFalse);
    });

    test('uses the backend id passed in, never constructs one from a date', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.update(journalId: 'the-real-uuid', content: 'Updated');

      verify(() => apiClient.patch(ApiEndpoints.journalById('the-real-uuid'), data: any(named: 'data'))).called(1);
    });

    test('another user\'s / unknown id 404s as NotFoundException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Journal entry not found', statusCode: 404));

      await expectLater(
        repository.update(journalId: 'not-mine', title: 'Hijacked'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('moving to an already-taken date 409s as ConflictException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A journal entry for 2025-01-01 already exists', statusCode: 409));

      await expectLater(
        repository.update(journalId: 'abc-123', entryDate: DateTime(2025, 1, 1)),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.update(journalId: 'abc-123', title: 'x'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('delete', () {
    test('DELETEs /journals/{id}', () async {
      when(() => apiClient.delete(any())).thenAnswer((_) async => null);

      await repository.delete('abc-123');

      verify(() => apiClient.delete(ApiEndpoints.journalById('abc-123'))).called(1);
    });
  });

  group('createOrUpdate (PHASE8 Step 4)', () {
    test('PATCHes when existingId is provided, and never calls POST', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), existingId: 'abc-123', title: 'Edited');

      verify(() => apiClient.patch(ApiEndpoints.journalById('abc-123'), data: any(named: 'data'))).called(1);
      verifyNever(() => apiClient.post(any(), data: any(named: 'data')));
    });

    test('POSTs when existingId is null', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _entryJson());

      await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), title: 'New');

      verify(() => apiClient.post(ApiEndpoints.journals, data: any(named: 'data'))).called(1);
    });

    test(
      'on an unexpected 409 from POST, looks the entry up by date and PATCHes it instead of retrying POST',
      () async {
        var postCallCount = 0;
        when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async {
          postCallCount++;
          throw const ConflictException('A journal entry for 2025-01-05 already exists', statusCode: 409);
        });
        when(
          () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer((_) async => {
          'items': [_entryJson(id: 'existing-id', title: 'Old')],
          'total': 1,
          'limit': 1,
          'offset': 0,
        });
        when(
          () => apiClient.patch(any(), data: any(named: 'data')),
        ).thenAnswer((_) async => _entryJson(id: 'existing-id', title: 'New'));

        final result = await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), title: 'New');

        expect(postCallCount, 1, reason: 'POST must not be retried after a 409');
        verify(() => apiClient.patch(ApiEndpoints.journalById('existing-id'), data: any(named: 'data'))).called(1);
        expect(result.id, 'existing-id');
        expect(result.title, 'New');
      },
    );

    test('rethrows the 409 if a fresh getForDate somehow still finds nothing', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A journal entry for 2025-01-05 already exists', statusCode: 409));
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => {'items': [], 'total': 0, 'limit': 1, 'offset': 0});

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), title: 'New'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a generic ApiException from create is not treated as the 409 fallback case', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ServerException('The server is temporarily unavailable.', statusCode: 500));

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5)),
        throwsA(isA<ServerException>()),
      );
      verifyNever(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters')));
    });
  });
}
