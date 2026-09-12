import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/checklist_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

const _catalogJson = [
  {'id': 'item-1', 'label': 'Drank enough water 💧', 'sort_order': 0},
  {'id': 'item-2', 'label': 'Slept well last night 🛌', 'sort_order': 1},
];

Map<String, dynamic> _dayJson({
  String entryDate = '2025-01-05',
  int completedCount = 0,
  List<Map<String, dynamic>>? items,
}) => {
  'entry_date': entryDate,
  'items':
      items ??
      [
        {
          'item_id': 'item-1',
          'label': 'Drank enough water 💧',
          'sort_order': 0,
          'completed': false,
          'completed_at': null,
        },
      ],
  'completed_count': completedCount,
  'total_count': 1,
};

void main() {
  late MockApiClient apiClient;
  late ChecklistRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = ChecklistRepository(apiClient: apiClient);
  });

  group('getCatalog', () {
    test('GETs /checklists/items via getList (bare array), not get', () async {
      when(() => apiClient.getList(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
        (_) async => _catalogJson,
      );

      final catalog = await repository.getCatalog();

      verify(() => apiClient.getList(ApiEndpoints.checklistItems)).called(1);
      verifyNever(() => apiClient.get(any(), queryParameters: any(named: 'queryParameters')));
      expect(catalog, hasLength(2));
      expect(catalog[0].id, 'item-1');
      expect(catalog[0].label, 'Drank enough water 💧');
      expect(catalog[0].sortOrder, 0);
      expect(catalog[1].id, 'item-2');
    });

    test('returns an empty list when the backend returns null/no items', () async {
      when(() => apiClient.getList(any())).thenAnswer((_) async => null);

      final catalog = await repository.getCatalog();

      expect(catalog, isEmpty);
    });

    test('a network failure propagates as NetworkException', () async {
      when(() => apiClient.getList(any())).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.getCatalog(), throwsA(isA<NetworkException>()));
    });

    test('a 401 that survives ApiClient\'s own refresh propagates as UnauthorizedException', () async {
      when(
        () => apiClient.getList(any()),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(repository.getCatalog(), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('getDay', () {
    test('GETs /checklists/{entry_date} with the date in the path, not a query param', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _dayJson());

      await repository.getDay(DateTime(2025, 1, 5));

      verify(() => apiClient.get(ApiEndpoints.checklistByDate('2025-01-05'))).called(1);
    });

    test('parses the full day snapshot from the response', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _dayJson(completedCount: 1));

      final day = await repository.getDay(DateTime(2025, 1, 5));

      expect(day.entryDate, DateTime(2025, 1, 5));
      expect(day.completedCount, 1);
      expect(day.totalCount, 1);
      expect(day.items.single.itemId, 'item-1');
    });

    test('an invalid/malformed date propagates as ValidationException', () async {
      when(
        () => apiClient.get(any()),
      ).thenThrow(ValidationException('entry_date: invalid date format', {'entry_date': []}));

      await expectLater(repository.getDay(DateTime(2025, 1, 5)), throwsA(isA<ValidationException>()));
    });
  });

  group('updateDay', () {
    test('PATCHes /checklists/{entry_date} with the exact completions body shape', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson());

      await repository.updateDay(DateTime(2025, 1, 5), {'item-1': true});

      final sentBody = verify(
        () => apiClient.patch(ApiEndpoints.checklistByDate('2025-01-05'), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody.containsKey('user_id'), isFalse);
      expect(sentBody['completions'], [
        {'item_id': 'item-1', 'completed': true},
      ]);
    });

    test('sends multiple completions in one request when given multiple entries', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson());

      await repository.updateDay(DateTime(2025, 1, 5), {'item-1': true, 'item-2': false});

      final sentBody = verify(
        () => apiClient.patch(any(), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect((sentBody['completions'] as List).length, 2);
    });

    test('an unknown item_id 404s as NotFoundException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Checklist item ... does not exist', statusCode: 404));

      await expectLater(
        repository.updateDay(DateTime(2025, 1, 5), {'missing-item': true}),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('an empty completions map still sends a well-formed (empty-list) body', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson());

      await repository.updateDay(DateTime(2025, 1, 5), {});

      final sentBody = verify(
        () => apiClient.patch(any(), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody['completions'], isEmpty);
    });
  });

  group('toggleItem', () {
    test('sends exactly {"completions": [{"item_id": ..., "completed": ...}]}', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson(completedCount: 1));

      await repository.toggleItem(DateTime(2025, 1, 5), 'item-1', true);

      final sentBody = verify(
        () => apiClient.patch(ApiEndpoints.checklistByDate('2025-01-05'), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody, {
        'completions': [
          {'item_id': 'item-1', 'completed': true},
        ],
      });
    });

    test('returns the updated day snapshot parsed from the response', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _dayJson(completedCount: 1));

      final day = await repository.toggleItem(DateTime(2025, 1, 5), 'item-1', true);

      expect(day.completedCount, 1);
    });

    test('a 422 (e.g. malformed request) propagates as ValidationException', () async {
      when(() => apiClient.patch(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('completions: field required', {
          'completions': ['field required'],
        }),
      );

      await expectLater(
        repository.toggleItem(DateTime(2025, 1, 5), 'item-1', true),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a 5xx propagates as ServerException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const ServerException('The server is temporarily unavailable.', statusCode: 500));

      await expectLater(
        repository.toggleItem(DateTime(2025, 1, 5), 'item-1', true),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
