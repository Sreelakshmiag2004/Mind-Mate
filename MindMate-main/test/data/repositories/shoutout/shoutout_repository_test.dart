import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/shoutout_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _shoutoutJson({
  String id = '9d1a2b3c-0001-4a11-8b11-000000000001',
  String entryDate = '2025-01-05',
  String? title = 'Overwhelmed',
  String? content = 'Too much on my plate.',
  bool? feltBetter,
  String? feltBetterAt,
}) => {
  'id': id,
  'user_id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
  'entry_date': entryDate,
  'title': title,
  'content': content,
  'felt_better': feltBetter,
  'felt_better_at': feltBetterAt,
  'created_at': '2025-01-05T08:00:00',
  'updated_at': '2025-01-05T08:00:00',
};

Map<String, dynamic> _pageJson(List<Map<String, dynamic>> items) =>
    {'items': items, 'total': items.length, 'limit': 1, 'offset': 0};

void main() {
  late MockApiClient apiClient;
  late ShoutoutRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = ShoutoutRepository(apiClient: apiClient);
  });

  group('getForDate', () {
    test('GETs /shoutouts with start_date/end_date both set to the same date and limit=1', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _pageJson([_shoutoutJson()]));

      await repository.getForDate(DateTime(2025, 1, 5));

      final captured =
          verify(
            () => apiClient.get(ApiEndpoints.shoutouts, queryParameters: captureAny(named: 'queryParameters')),
          ).captured.single as Map;
      expect(captured['start_date'], '2025-01-05');
      expect(captured['end_date'], '2025-01-05');
      expect(captured['limit'], 1);
    });

    test('returns null when the date has no shoutout (empty items)', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _pageJson(const []));

      final shoutout = await repository.getForDate(DateTime(2025, 1, 5));

      expect(shoutout, isNull);
    });

    test('returns null when the backend returns a null body', () async {
      when(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => null);

      final shoutout = await repository.getForDate(DateTime(2025, 1, 5));

      expect(shoutout, isNull);
    });

    test('returns the parsed shoutout when one exists for the date', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _pageJson([_shoutoutJson(title: 'Work stress')]));

      final shoutout = await repository.getForDate(DateTime(2025, 1, 5));

      expect(shoutout, isNotNull);
      expect(shoutout!.title, 'Work stress');
      expect(shoutout.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.getForDate(DateTime(2025, 1, 5)), throwsA(isA<NetworkException>()));
    });

    test('a 401 that survives ApiClient\'s own refresh propagates as UnauthorizedException', () async {
      when(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters'))).thenThrow(
        const UnauthorizedException('Could not validate credentials', statusCode: 401),
      );

      await expectLater(repository.getForDate(DateTime(2025, 1, 5)), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('create', () {
    test('POSTs /shoutouts with entry_date/title/content, no user_id', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _shoutoutJson());

      await repository.create(entryDate: DateTime(2025, 1, 5), title: 'Overwhelmed', content: 'Too much on my plate.');

      final sentBody = verify(
        () => apiClient.post(ApiEndpoints.shoutouts, data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody, {'entry_date': '2025-01-05', 'title': 'Overwhelmed', 'content': 'Too much on my plate.'});
      expect(sentBody.containsKey('user_id'), isFalse);
    });

    test('returns the created shoutout, id included', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _shoutoutJson());

      final shoutout = await repository.create(entryDate: DateTime(2025, 1, 5));

      expect(shoutout.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(shoutout.feltBetter, isNull);
    });

    test('a duplicate date rejected by the backend propagates as ConflictException (409)', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A shoutout for 2025-01-05 already exists', statusCode: 409));

      await expectLater(repository.create(entryDate: DateTime(2025, 1, 5)), throwsA(isA<ConflictException>()));
    });

    test('a 422 (e.g. title too long) propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('title: ensure this value has at most 200 characters', {
          'title': ['ensure this value has at most 200 characters'],
        }),
      );

      await expectLater(repository.create(entryDate: DateTime(2025, 1, 5)), throwsA(isA<ValidationException>()));
    });
  });

  group('update', () {
    test('PATCHes /shoutouts/{id} with only the provided fields', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _shoutoutJson());

      await repository.update(id: '9d1a2b3c-0001-4a11-8b11-000000000001', title: 'New title');

      final sentBody = verify(
        () => apiClient.patch(
          ApiEndpoints.shoutoutById('9d1a2b3c-0001-4a11-8b11-000000000001'),
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(sentBody, {'title': 'New title'});
      expect(sentBody.containsKey('content'), isFalse);
    });

    test('a 404 (not found / not yours) propagates as NotFoundException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Shoutout not found', statusCode: 404));

      await expectLater(
        repository.update(id: 'missing-id', title: 'x'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('createOrUpdate', () {
    test('GETs first, then POSTs when no shoutout exists for the date (never blindly POSTs)', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _pageJson(const []));
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenAnswer((_) async => _shoutoutJson());

      await repository.createOrUpdate(entryDate: DateTime(2025, 1, 5), title: 'Overwhelmed', content: 'x');

      verify(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters'))).called(1);
      verify(() => apiClient.post(ApiEndpoints.shoutouts, data: any(named: 'data'))).called(1);
      verifyNever(() => apiClient.patch(any(), data: any(named: 'data')));
    });

    test('GETs first, then PATCHes the existing shoutout\'s exact id when one exists for the date', () async {
      when(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
        (_) async => _pageJson([_shoutoutJson(id: 'existing-id-123', title: 'Old title')]),
      );
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _shoutoutJson(id: 'existing-id-123', title: 'New title'),
      );

      final result = await repository.createOrUpdate(
        entryDate: DateTime(2025, 1, 5),
        title: 'New title',
        content: 'x',
      );

      verify(() => apiClient.patch(ApiEndpoints.shoutoutById('existing-id-123'), data: any(named: 'data'))).called(1);
      verifyNever(() => apiClient.post(any(), data: any(named: 'data')));
      expect(result.id, 'existing-id-123');
      expect(result.title, 'New title');
    });

    test('a 409 from the POST path (rare create-vs-create race) still propagates as ConflictException', () async {
      when(
        () => apiClient.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _pageJson(const []));
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('A shoutout for 2025-01-05 already exists', statusCode: 409));

      await expectLater(
        repository.createOrUpdate(entryDate: DateTime(2025, 1, 5)),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('answerFeelBetter', () {
    test('POSTs /shoutouts/{id}/feel-better with {"felt_better": true}', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _shoutoutJson(feltBetter: true, feltBetterAt: '2025-01-06T09:15:00+00:00'));

      final result = await repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', true);

      final sentBody = verify(
        () => apiClient.post(
          ApiEndpoints.shoutoutFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001'),
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(sentBody, {'felt_better': true});
      expect(result.feltBetter, isTrue);
      expect(result.feltBetterAt, isNotNull);
    });

    test('POSTs /shoutouts/{id}/feel-better with {"felt_better": false}', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _shoutoutJson(feltBetter: false, feltBetterAt: '2025-01-06T09:15:00+00:00'));

      final result = await repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', false);

      final sentBody = verify(
        () => apiClient.post(any(), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody, {'felt_better': false});
      expect(result.feltBetter, isFalse);
    });

    // The one-shot 409 rule itself: repository must not swallow or retry
    // it — it propagates as ConflictException exactly like any other 409,
    // so the caller (journal_page.dart's _setYesterdayFeelBetter) can
    // catch it specifically and treat it as "already answered" rather
    // than a generic failure (PHASE13 Step 6). That UI-side re-fetch
    // behavior itself isn't covered here — journal_page.dart is a large,
    // Firebase-adjacent StatefulWidget not practical to unit test in
    // isolation (same constraint noted for Journal/Mood/Checklist) — but
    // this pins the contract the UI's catch block depends on.
    test('a second answer (already answered) propagates as ConflictException (409), not swallowed', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException("This shoutout's follow-up has already been answered", statusCode: 409));

      await expectLater(
        repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', false),
        throwsA(isA<ConflictException>()),
      );
    });

    test('answering another user\'s shoutout propagates as NotFoundException (404)', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Shoutout not found', statusCode: 404));

      await expectLater(
        repository.answerFeelBetter('not-mine', true),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('a 422 (e.g. malformed body) propagates as ValidationException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('felt_better: field required', {
          'felt_better': ['field required'],
        }),
      );

      await expectLater(
        repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', true),
        throwsA(isA<ValidationException>()),
      );
    });

    test('an unauthenticated request propagates as UnauthorizedException (401)', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(
        repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', true),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', true),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a 5xx propagates as ServerException', () async {
      when(() => apiClient.post(any(), data: any(named: 'data'))).thenThrow(
        const ServerException('The server is temporarily unavailable.', statusCode: 500),
      );

      await expectLater(
        repository.answerFeelBetter('9d1a2b3c-0001-4a11-8b11-000000000001', true),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
