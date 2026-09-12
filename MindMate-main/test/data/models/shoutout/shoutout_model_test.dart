import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/shoutout/shoutout_model.dart';

Map<String, dynamic> _shoutoutJson({
  String id = '9d1a2b3c-0001-4a11-8b11-000000000001',
  String userId = 'e1822158-f808-4b37-b7f8-5903f92910ef',
  String entryDate = '2025-01-05',
  String? title = 'Overwhelmed',
  String? content = 'Too much on my plate.',
  bool? feltBetter,
  String? feltBetterAt,
}) => {
  'id': id,
  'user_id': userId,
  'entry_date': entryDate,
  'title': title,
  'content': content,
  'felt_better': feltBetter,
  'felt_better_at': feltBetterAt,
  'created_at': '2025-01-05T08:00:00',
  'updated_at': '2025-01-05T08:00:00',
};

void main() {
  group('ShoutoutModel.fromJson', () {
    test('parses id/user_id/entry_date/title/content/timestamps', () {
      final shoutout = ShoutoutModel.fromJson(_shoutoutJson());

      expect(shoutout.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(shoutout.userId, 'e1822158-f808-4b37-b7f8-5903f92910ef');
      expect(shoutout.title, 'Overwhelmed');
      expect(shoutout.content, 'Too much on my plate.');
      expect(shoutout.createdAt, DateTime.parse('2025-01-05T08:00:00'));
      expect(shoutout.updatedAt, DateTime.parse('2025-01-05T08:00:00'));
    });

    test('entry_date parses as a local, time-of-day-free date rather than UTC midnight', () {
      final shoutout = ShoutoutModel.fromJson(_shoutoutJson());

      expect(shoutout.entryDate, DateTime(2025, 1, 5));
      expect(shoutout.entryDate.isUtc, isFalse);
    });

    test('title and content are both nullable', () {
      final shoutout = ShoutoutModel.fromJson(_shoutoutJson(title: null, content: null));

      expect(shoutout.title, isNull);
      expect(shoutout.content, isNull);
    });

    test('felt_better null (never answered) parses as null, with felt_better_at also null', () {
      final shoutout = ShoutoutModel.fromJson(_shoutoutJson());

      expect(shoutout.feltBetter, isNull);
      expect(shoutout.feltBetterAt, isNull);
    });

    test('felt_better true parses as true, with felt_better_at populated', () {
      final shoutout = ShoutoutModel.fromJson(
        _shoutoutJson(feltBetter: true, feltBetterAt: '2025-01-06T09:15:00+00:00'),
      );

      expect(shoutout.feltBetter, isTrue);
      expect(shoutout.feltBetterAt, DateTime.parse('2025-01-06T09:15:00+00:00'));
    });

    test('felt_better false parses as false, not as null/falsy-missing', () {
      final shoutout = ShoutoutModel.fromJson(
        _shoutoutJson(feltBetter: false, feltBetterAt: '2025-01-06T09:15:00+00:00'),
      );

      expect(shoutout.feltBetter, isFalse);
      expect(shoutout.feltBetterAt, isNotNull);
    });

    test('toJson round-trips, including a populated felt_better', () {
      final shoutout = ShoutoutModel.fromJson(
        _shoutoutJson(feltBetter: true, feltBetterAt: '2025-01-06T09:15:00+00:00'),
      );

      final roundTripped = ShoutoutModel.fromJson(shoutout.toJson());

      expect(roundTripped.id, shoutout.id);
      expect(roundTripped.userId, shoutout.userId);
      expect(roundTripped.entryDate, shoutout.entryDate);
      expect(roundTripped.title, shoutout.title);
      expect(roundTripped.content, shoutout.content);
      expect(roundTripped.feltBetter, shoutout.feltBetter);
      expect(roundTripped.feltBetterAt, shoutout.feltBetterAt);
    });

    test('toJson serializes entry_date back to a plain YYYY-MM-DD string', () {
      final shoutout = ShoutoutModel.fromJson(_shoutoutJson());

      final json = shoutout.toJson();

      expect(json['entry_date'], '2025-01-05');
      expect(json['felt_better'], isNull);
      expect(json['felt_better_at'], isNull);
    });
  });
}
