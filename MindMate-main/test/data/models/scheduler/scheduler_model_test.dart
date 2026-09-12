import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/scheduler/scheduler_model.dart';

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
  group('SchedulerEntry.fromJson', () {
    test('parses id/entry_date/scheduled_time/description/timestamps', () {
      final entry = SchedulerEntry.fromJson(_entryJson());

      expect(entry.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(entry.scheduledTime, '09:00');
      expect(entry.description, 'Morning walk');
      expect(entry.createdAt, DateTime.parse('2025-01-05T08:00:00'));
      expect(entry.updatedAt, DateTime.parse('2025-01-05T08:00:00'));
    });

    test('entry_date parses as a local, time-of-day-free date rather than UTC midnight', () {
      final entry = SchedulerEntry.fromJson(_entryJson());

      expect(entry.entryDate, DateTime(2025, 1, 5));
      expect(entry.entryDate.isUtc, isFalse);
    });

    test('a null description is preserved as null, not an empty string', () {
      final entry = SchedulerEntry.fromJson(_entryJson(description: null));

      expect(entry.description, isNull);
    });

    test('toJson round-trips', () {
      final entry = SchedulerEntry.fromJson(_entryJson());
      final roundTripped = SchedulerEntry.fromJson(entry.toJson());

      expect(roundTripped.id, entry.id);
      expect(roundTripped.scheduledTime, entry.scheduledTime);
      expect(roundTripped.description, entry.description);
      expect(roundTripped.entryDate, entry.entryDate);
    });
  });

  group('SchedulerDay.fromJson', () {
    test('parses entry_date and nested items', () {
      final day = SchedulerDay.fromJson(_dayJson());

      expect(day.entryDate, DateTime(2025, 1, 5));
      expect(day.items, hasLength(1));
      expect(day.items.single.scheduledTime, '09:00');
    });

    test('an empty items list parses cleanly (nothing scheduled is not an error)', () {
      final day = SchedulerDay.fromJson(_dayJson(items: []));

      expect(day.items, isEmpty);
    });

    test('toJson serializes entry_date back to a plain YYYY-MM-DD string', () {
      final day = SchedulerDay.fromJson(_dayJson());

      final json = day.toJson();

      expect(json['entry_date'], '2025-01-05');
      expect((json['items'] as List), hasLength(1));
    });
  });

  group('SchedulerRowInput.toJson', () {
    test('serializes scheduled_time/description exactly', () {
      const row = SchedulerRowInput(scheduledTime: '09:00', description: 'Standup');

      expect(row.toJson(), {'scheduled_time': '09:00', 'description': 'Standup'});
    });

    test('a null description serializes as null, not omitted', () {
      const row = SchedulerRowInput(scheduledTime: '09:00');

      expect(row.toJson(), {'scheduled_time': '09:00', 'description': null});
    });
  });

  group('dotTimeToColon', () {
    test('converts a zero-padded "HH.MM" to "HH:MM"', () {
      expect(dotTimeToColon('09.30'), '09:30');
    });

    test('converts a non-zero-padded "H.MM" to zero-padded "HH:MM"', () {
      expect(dotTimeToColon('9.00'), '09:00');
    });

    test('zero-pads a single-digit minute too', () {
      expect(dotTimeToColon('9.5'), '09:05');
    });

    test('returns null for a blank string', () {
      expect(dotTimeToColon(''), isNull);
    });

    test('returns null for a whitespace-only string', () {
      expect(dotTimeToColon('   '), isNull);
    });

    test('returns null for an out-of-range hour or minute', () {
      expect(dotTimeToColon('24.00'), isNull);
      expect(dotTimeToColon('9.60'), isNull);
    });

    test('returns null for an unparseable string', () {
      expect(dotTimeToColon('not-a-time'), isNull);
    });
  });

  group('colonTimeToDot', () {
    test('converts "HH:MM" to "HH.MM"', () {
      expect(colonTimeToDot('09:30'), '09.30');
    });

    test('is the exact inverse of dotTimeToColon for zero-padded input', () {
      expect(colonTimeToDot(dotTimeToColon('09.30')!), '09.30');
    });

    test('returns the input unchanged if it is not in the expected shape', () {
      expect(colonTimeToDot('garbage'), 'garbage');
    });
  });

  group('buildSchedulerRows', () {
    test('converts each row\'s time and keeps its description', () {
      final rows = buildSchedulerRows([
        {'time': '9.00', 'desc': 'Standup'},
        {'time': '14.30', 'desc': 'Gym'},
      ]);

      expect(rows, isNotNull);
      expect(rows!.map((r) => r.scheduledTime), ['09:00', '14:30']);
      expect(rows.map((r) => r.description), ['Standup', 'Gym']);
    });

    test('drops rows with a blank time', () {
      final rows = buildSchedulerRows([
        {'time': '', 'desc': 'No time set'},
        {'time': '9.00', 'desc': 'Standup'},
      ]);

      expect(rows, hasLength(1));
      expect(rows!.single.scheduledTime, '09:00');
    });

    test('keeps a row with a blank description (only blank time is dropped)', () {
      final rows = buildSchedulerRows([
        {'time': '9.00', 'desc': ''},
      ]);

      expect(rows, hasLength(1));
      expect(rows!.single.description, isNull);
    });

    test('returns null when two rows resolve to the same backend time', () {
      final rows = buildSchedulerRows([
        {'time': '9.00', 'desc': 'Standup'},
        {'time': '09.00', 'desc': 'Duplicate!'},
      ]);

      expect(rows, isNull);
    });

    test('an empty row list returns an empty (non-null) list, not null', () {
      final rows = buildSchedulerRows([]);

      expect(rows, isNotNull);
      expect(rows, isEmpty);
    });
  });
}
