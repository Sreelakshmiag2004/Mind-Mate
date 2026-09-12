import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/utils/journal_streak.dart';

void main() {
  final today = DateTime(2025, 6, 15);

  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  group('calculateJournalStreak', () {
    test('no entry today -> 0, even if every prior day has one', () {
      final entries = [daysAgo(1), daysAgo(2), daysAgo(3)];

      expect(calculateJournalStreak(entries, today: today), 0);
    });

    test('today only -> 1', () {
      final entries = [daysAgo(0)];

      expect(calculateJournalStreak(entries, today: today), 1);
    });

    test('today + yesterday -> 2', () {
      final entries = [daysAgo(0), daysAgo(1)];

      expect(calculateJournalStreak(entries, today: today), 2);
    });

    test('three consecutive days ending today -> 3', () {
      final entries = [daysAgo(0), daysAgo(1), daysAgo(2)];

      expect(calculateJournalStreak(entries, today: today), 3);
    });

    test('a gap breaks the streak at the first missing date', () {
      // today, yesterday present; the day before that is missing; two more
      // consecutive days exist further back but must not be counted.
      final entries = [daysAgo(0), daysAgo(1), daysAgo(3), daysAgo(4)];

      expect(calculateJournalStreak(entries, today: today), 2);
    });

    test('entries after a gap (further in the past) do not extend the current streak', () {
      final entries = [daysAgo(0), daysAgo(5), daysAgo(6), daysAgo(7)];

      expect(calculateJournalStreak(entries, today: today), 1);
    });

    test('unsorted entries still calculate correctly', () {
      final entries = [daysAgo(2), daysAgo(0), daysAgo(1)];

      expect(calculateJournalStreak(entries, today: today), 3);
    });

    test('duplicate dates do not incorrectly increase the streak', () {
      final entries = [daysAgo(0), daysAgo(0), daysAgo(1), daysAgo(1), daysAgo(1)];

      expect(calculateJournalStreak(entries, today: today), 2);
    });

    test('an entry with a time-of-day component is compared by calendar day only', () {
      final entries = [
        DateTime(today.year, today.month, today.day, 23, 59),
        DateTime(today.year, today.month, today.day - 1, 0, 1),
      ];

      expect(calculateJournalStreak(entries, today: today), 2);
    });

    test('an empty entry list -> 0', () {
      expect(calculateJournalStreak(const [], today: today), 0);
    });

    test('defaults `today` to DateTime.now() when not provided', () {
      final now = DateTime.now();
      final entries = [DateTime(now.year, now.month, now.day)];

      expect(calculateJournalStreak(entries), 1);
    });
  });
}
