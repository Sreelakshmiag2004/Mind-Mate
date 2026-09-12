import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/mood/mood_model.dart';

const _moodJson = {
  'id': '9d1a2b3c-0001-4a11-8b11-000000000001',
  'user_id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
  'entry_date': '2025-01-05',
  'mood_value': 72,
  'created_at': '2025-01-05T10:00:00',
  'updated_at': '2025-01-05T10:00:00',
};

void main() {
  group('MoodModel.fromJson', () {
    test('parses every backend field using the backend\'s exact field names', () {
      final model = MoodModel.fromJson(_moodJson);

      expect(model.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(model.userId, 'e1822158-f808-4b37-b7f8-5903f92910ef');
      expect(model.moodValue, 72);
      expect(model.createdAt, DateTime.parse('2025-01-05T10:00:00'));
      expect(model.updatedAt, DateTime.parse('2025-01-05T10:00:00'));
    });

    test('parses entry_date as a local, time-of-day-free date rather than UTC midnight', () {
      final model = MoodModel.fromJson(_moodJson);

      // DateTime.parse('2025-01-05') would produce UTC midnight; entryDate
      // must instead be the plain local calendar date with no time offset
      // (PHASE9 Step 12 / reuses JournalModel's parseDateOnly).
      expect(model.entryDate, DateTime(2025, 1, 5));
      expect(model.entryDate.isUtc, isFalse);
      expect(model.entryDate.hour, 0);
    });

    test('mood_value is parsed as an int, not a double or string', () {
      final model = MoodModel.fromJson(_moodJson);

      expect(model.moodValue, isA<int>());
    });
  });

  group('MoodModel.toJson', () {
    test('serializes entry_date back to a plain YYYY-MM-DD string', () {
      final model = MoodModel.fromJson(_moodJson);

      final json = model.toJson();

      expect(json['entry_date'], '2025-01-05');
      expect(json['id'], _moodJson['id']);
      expect(json['user_id'], _moodJson['user_id']);
      expect(json['mood_value'], 72);
    });

    test('round-trips through fromJson/toJson without losing the date or value', () {
      final model = MoodModel.fromJson(_moodJson);
      final roundTripped = MoodModel.fromJson(model.toJson());

      expect(roundTripped.entryDate, model.entryDate);
      expect(roundTripped.moodValue, model.moodValue);
      expect(roundTripped.id, model.id);
    });
  });
}
