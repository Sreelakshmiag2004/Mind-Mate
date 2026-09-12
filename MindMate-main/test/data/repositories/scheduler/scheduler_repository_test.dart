import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/models/scheduler/scheduler_model.dart';
import 'package:mindmate/data/repositories/scheduler_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _entryJson({
  String id = '9d1a2b3c-0001-4a11-8b11-000000000001',
  String entryDate = '2025-01-05',
  String scheduledTime = '09:00',
  String? description = 'Morning walk',
}) => {
  'id': id,
  'entry_date': entryDate,
  'scheduled_time': scheduledTime,
  'description': description,
  'created_at': '2025-01-05T08:00:00',
  'updated_at': '2025-01-05T08:00:00',
};

Map<String, dynamic> _dayJson({String entryDate = '2025-01-05', List<Map<String, dynamic>>? items}) => {
  'entry_date': entryDate,
  'items': items ?? [_entryJson()],
};

void main() {
  late MockApiClient apiClient;
  late SchedulerRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = SchedulerRepository(apiClient: apiClient);
  });

  group('getDay', () {
    test('GETs /scheduler/{entry_date} with the date in the path', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _dayJson());

      await repository.getDay(DateTime(2025, 1, 5));

      verify(() => apiClient.get(ApiEndpoints.schedulerByDate('2025-01-05'))).called(1);
    });

    test('parses the full day, including its items, from the response', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _dayJson());

      final day = await repository.getDay(DateTime(2025, 1, 5));

      expect(day.entryDate, DateTime(2025, 1, 5));
      expect(day.items, hasLength(1));
      expect(day.items.single.scheduledTime, '09:00');
    });

    test('an empty-day response (nothing scheduled) parses with an empty items list', () async {
      when(() => apiClient.get(any())).thenAnswer((_) async => _dayJson(items: []));

      final day = await repository.getDay(DateTime(2025, 1, 5));

      expect(day.items, isEmpty);
    });

    test('a network failure propagates as NetworkException', () async {
      when(() => apiClient.get(any())).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.getDay(DateTime(2025, 1, 5)), throwsA(isA<NetworkException>()));
    });

    test('a 401 that survives ApiClient\'s own refresh propagates as UnauthorizedException', () async {
      when(
        () => apiClient.get(any()),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(repository.getDay(DateTime(2025, 1, 5)), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('replaceDay', () {
    test('PUTs /scheduler/{entry_date} with a rows array built from the input', () async {
      when(() => apiClient.put(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson());

      await repository.replaceDay(DateTime(2025, 1, 5), const [
        SchedulerRowInput(scheduledTime: '09:00', description: 'Morning walk'),
      ]);

      final sentBody = verify(
        () => apiClient.put(ApiEndpoints.schedulerByDate('2025-01-05'), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody.containsKey('user_id'), isFalse);
      expect(sentBody['rows'], [
        {'scheduled_time': '09:00', 'description': 'Morning walk'},
      ]);
    });

    test('sends an empty rows array (clears the day) when given no rows', () async {
      when(() => apiClient.put(any(), data: any(named: 'data'))).thenAnswer((_) async => _dayJson(items: []));

      await repository.replaceDay(DateTime(2025, 1, 5), const []);

      final sentBody = verify(
        () => apiClient.put(any(), data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(sentBody['rows'], isEmpty);
    });

    test('returns the saved day snapshot parsed from the response', () async {
      when(
        () => apiClient.put(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _dayJson(items: [_entryJson(scheduledTime: '14:30', description: 'Gym')]));

      final day = await repository.replaceDay(DateTime(2025, 1, 5), const [
        SchedulerRowInput(scheduledTime: '14:30', description: 'Gym'),
      ]);

      expect(day.items.single.scheduledTime, '14:30');
      expect(day.items.single.description, 'Gym');
    });

    test('a duplicate time rejected by the backend propagates as ValidationException (422)', () async {
      when(() => apiClient.put(any(), data: any(named: 'data'))).thenThrow(
        ValidationException('Two rows have the same scheduled_time', {
          'rows': ['duplicate scheduled_time'],
        }),
      );

      await expectLater(
        repository.replaceDay(DateTime(2025, 1, 5), const [
          SchedulerRowInput(scheduledTime: '09:00'),
          SchedulerRowInput(scheduledTime: '09:00'),
        ]),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a concurrent-write race rejected by the backend propagates as ConflictException (409)', () async {
      when(
        () => apiClient.put(any(), data: any(named: 'data')),
      ).thenThrow(const ConflictException('That time is already scheduled.', statusCode: 409));

      await expectLater(
        repository.replaceDay(DateTime(2025, 1, 5), const [SchedulerRowInput(scheduledTime: '09:00')]),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a 5xx propagates as ServerException', () async {
      when(() => apiClient.put(any(), data: any(named: 'data'))).thenThrow(
        const ServerException('The server is temporarily unavailable.', statusCode: 500),
      );

      await expectLater(
        repository.replaceDay(DateTime(2025, 1, 5), const [SchedulerRowInput(scheduledTime: '09:00')]),
        throwsA(isA<ServerException>()),
      );
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.put(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.replaceDay(DateTime(2025, 1, 5), const [SchedulerRowInput(scheduledTime: '09:00')]),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
