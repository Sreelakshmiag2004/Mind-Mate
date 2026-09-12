import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/checklist/checklist_model.dart';

const _itemJson = {
  'id': '9d1a2b3c-0001-4a11-8b11-000000000001',
  'label': 'Drank enough water 💧',
  'sort_order': 0,
};

Map<String, dynamic> _itemStateJson({
  String itemId = '9d1a2b3c-0001-4a11-8b11-000000000001',
  bool completed = false,
  String? completedAt,
}) => {
  'item_id': itemId,
  'label': 'Drank enough water 💧',
  'sort_order': 0,
  'completed': completed,
  'completed_at': completedAt,
};

Map<String, dynamic> _dayJson({List<Map<String, dynamic>>? items}) => {
  'entry_date': '2025-01-05',
  'items':
      items ??
      [
        _itemStateJson(completed: true, completedAt: '2025-01-05T10:00:00+00:00'),
        _itemStateJson(itemId: '9d1a2b3c-0002-4a11-8b11-000000000002'),
      ],
  'completed_count': 1,
  'total_count': 2,
};

void main() {
  group('ChecklistItem.fromJson', () {
    test('parses the catalog fields using the backend\'s exact names', () {
      final item = ChecklistItem.fromJson(_itemJson);

      expect(item.id, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(item.label, 'Drank enough water 💧');
      expect(item.sortOrder, 0);
    });

    test('toJson round-trips', () {
      final item = ChecklistItem.fromJson(_itemJson);
      final roundTripped = ChecklistItem.fromJson(item.toJson());

      expect(roundTripped.id, item.id);
      expect(roundTripped.label, item.label);
      expect(roundTripped.sortOrder, item.sortOrder);
    });
  });

  group('ChecklistItemState.fromJson', () {
    test('parses item_id/label/sort_order/completed', () {
      final state = ChecklistItemState.fromJson(_itemStateJson(completed: true));

      expect(state.itemId, '9d1a2b3c-0001-4a11-8b11-000000000001');
      expect(state.label, 'Drank enough water 💧');
      expect(state.sortOrder, 0);
      expect(state.completed, isTrue);
    });

    test('completed_at present is parsed into a DateTime', () {
      final state = ChecklistItemState.fromJson(
        _itemStateJson(completed: true, completedAt: '2025-01-05T10:00:00+00:00'),
      );

      expect(state.completedAt, isNotNull);
      expect(state.completedAt, DateTime.parse('2025-01-05T10:00:00+00:00'));
    });

    test('completed_at null (never toggled on this date) stays null', () {
      final state = ChecklistItemState.fromJson(_itemStateJson(completed: false, completedAt: null));

      expect(state.completed, isFalse);
      expect(state.completedAt, isNull);
    });
  });

  group('ChecklistDay.fromJson', () {
    test('parses entry_date, nested items, completed_count, and total_count', () {
      final day = ChecklistDay.fromJson(_dayJson());

      expect(day.items, hasLength(2));
      expect(day.completedCount, 1);
      expect(day.totalCount, 2);
      expect(day.items[0].completed, isTrue);
      expect(day.items[1].completed, isFalse);
    });

    test('entry_date parses as a local, time-of-day-free date rather than UTC midnight', () {
      final day = ChecklistDay.fromJson(_dayJson());

      // DateTime.parse('2025-01-05') would produce UTC midnight; entryDate
      // must instead be the plain local calendar date (reuses
      // JournalModel's parseDateOnly — PHASE10 Step 1/12).
      expect(day.entryDate, DateTime(2025, 1, 5));
      expect(day.entryDate.isUtc, isFalse);
    });

    test('always carries every catalog item, even ones never toggled (completed: false)', () {
      final day = ChecklistDay.fromJson(
        _dayJson(
          items: [
            _itemStateJson(itemId: 'a'),
            _itemStateJson(itemId: 'b'),
            _itemStateJson(itemId: 'c'),
          ],
        ),
      );

      expect(day.items.map((i) => i.itemId), ['a', 'b', 'c']);
      expect(day.items.every((i) => !i.completed), isTrue);
    });

    test('toJson serializes entry_date back to a plain YYYY-MM-DD string', () {
      final day = ChecklistDay.fromJson(_dayJson());

      final json = day.toJson();

      expect(json['entry_date'], '2025-01-05');
      expect(json['completed_count'], 1);
      expect(json['total_count'], 2);
      expect((json['items'] as List).length, 2);
    });
  });
}
