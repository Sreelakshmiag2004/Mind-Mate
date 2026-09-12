import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/journal/journal_model.dart';

const _journalJson = {
  'id': '9d1a2b3c-0001-4a11-8b11-000000000001',
  'user_id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
  'entry_date': '2025-01-05',
  'title': 'A good day',
  'content': 'Went for a walk.',
  'created_at': '2025-01-05T10:00:00',
  'updated_at': '2025-01-05T10:00:00',
};

void main() {
  group('JournalModel.fromJson', () {
    test('parses every backend field using the backend\'s exact field names', () {
      final model = JournalModel.fromJson(_journalJson);

      expect(model.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(model.userId, 'e1822158-f808-4b37-b7f8-5903f92910ef');
      expect(model.title, 'A good day');
      expect(model.content, 'Went for a walk.');
      expect(model.createdAt, DateTime.parse('2025-01-05T10:00:00'));
      expect(model.updatedAt, DateTime.parse('2025-01-05T10:00:00'));
    });

    test('parses entry_date as a local, time-of-day-free date rather than UTC midnight', () {
      final model = JournalModel.fromJson(_journalJson);

      // DateTime.parse('2025-01-05') would produce UTC midnight; entryDate
      // must instead be the plain local calendar date with no time offset,
      // so it always reads back as 2025-01-05 regardless of the device's
      // timezone (PHASE8 Step 12).
      expect(model.entryDate, DateTime(2025, 1, 5));
      expect(model.entryDate.isUtc, isFalse);
      expect(model.entryDate.hour, 0);
    });

    test('title and content are nullable', () {
      final json = {..._journalJson, 'title': null, 'content': null};

      final model = JournalModel.fromJson(json);

      expect(model.title, isNull);
      expect(model.content, isNull);
    });
  });

  group('JournalModel.toJson', () {
    test('serializes entry_date back to a plain YYYY-MM-DD string', () {
      final model = JournalModel.fromJson(_journalJson);

      final json = model.toJson();

      expect(json['entry_date'], '2025-01-05');
      expect(json['id'], _journalJson['id']);
      expect(json['user_id'], _journalJson['user_id']);
      expect(json['title'], 'A good day');
      expect(json['content'], 'Went for a walk.');
    });

    test('round-trips through fromJson/toJson without losing the date', () {
      final model = JournalModel.fromJson(_journalJson);
      final roundTripped = JournalModel.fromJson(model.toJson());

      expect(roundTripped.entryDate, model.entryDate);
      expect(roundTripped.id, model.id);
    });
  });

  group('formatDateOnly / parseDateOnly', () {
    test('formatDateOnly zero-pads month and day', () {
      expect(formatDateOnly(DateTime(2025, 1, 5)), '2025-01-05');
      expect(formatDateOnly(DateTime(2025, 12, 31)), '2025-12-31');
    });

    test('parseDateOnly reads calendar fields directly, ignoring any timezone', () {
      final parsed = parseDateOnly('2025-01-05');

      expect(parsed, DateTime(2025, 1, 5));
      expect(parsed.isUtc, isFalse);
    });

    test('formatDateOnly and parseDateOnly are inverses', () {
      final date = DateTime(2025, 3, 7);
      expect(parseDateOnly(formatDateOnly(date)), date);
    });
  });
}
