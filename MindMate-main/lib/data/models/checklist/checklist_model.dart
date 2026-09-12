import '../journal/journal_model.dart' show formatDateOnly, parseDateOnly;

/// Mirrors `app.schemas.checklist.ChecklistItemRead` — one row of the
/// global, non-user-specific task catalog (`GET /checklists/items`; see
/// PHASE10 audit report, Section 2). The backend is authoritative for
/// `label`/`sortOrder`/`id` — this app no longer hard-codes them anywhere
/// once the catalog has loaded (see `homepage.dart`'s `loadChecklist`).
class ChecklistItem {
  const ChecklistItem({required this.id, required this.label, required this.sortOrder});

  final String id;
  final String label;
  final int sortOrder;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      label: json['label'] as String,
      sortOrder: json['sort_order'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'sort_order': sortOrder};
}

/// Mirrors `app.schemas.checklist.ChecklistItemState` — one catalog item's
/// completion state on a specific date, as returned nested inside a
/// [ChecklistDay]. `itemId` is the same UUID as the matching [ChecklistItem]
/// — that id, not array position, is how a Flutter checkbox's index maps
/// back to "which item is this" (see PHASE10 audit report, Section 3).
class ChecklistItemState {
  const ChecklistItemState({
    required this.itemId,
    required this.label,
    required this.sortOrder,
    required this.completed,
    this.completedAt,
  });

  final String itemId;
  final String label;
  final int sortOrder;
  final bool completed;

  /// Null when this item has never been completed on this date (the
  /// backend only creates a completion row on first toggle — see
  /// `app/models/checklist.py`). Not currently shown anywhere in the UI,
  /// but carried through for forward compatibility.
  final DateTime? completedAt;

  factory ChecklistItemState.fromJson(Map<String, dynamic> json) {
    return ChecklistItemState(
      itemId: json['item_id'] as String,
      label: json['label'] as String,
      sortOrder: json['sort_order'] as int,
      completed: json['completed'] as bool,
      completedAt: json['completed_at'] == null ? null : DateTime.parse(json['completed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'label': label,
    'sort_order': sortOrder,
    'completed': completed,
    'completed_at': completedAt?.toIso8601String(),
  };
}

/// Mirrors `app.schemas.checklist.ChecklistDayRead` — the full response of
/// both `GET /checklists/{entry_date}` and `PATCH /checklists/{entry_date}`:
/// every catalog item plus its completion state for that date, always all 5
/// items regardless of how many (if any) have ever been toggled on that
/// date (see PHASE10 audit report, Section 2).
class ChecklistDay {
  const ChecklistDay({
    required this.entryDate,
    required this.items,
    required this.completedCount,
    required this.totalCount,
  });

  /// Date-only — parsed with [parseDateOnly], not `DateTime.parse`
  /// directly, for the same local-vs-UTC reason documented on
  /// `JournalModel.entryDate`.
  final DateTime entryDate;
  final List<ChecklistItemState> items;
  final int completedCount;
  final int totalCount;

  factory ChecklistDay.fromJson(Map<String, dynamic> json) {
    return ChecklistDay(
      entryDate: parseDateOnly(json['entry_date'] as String),
      items: (json['items'] as List<dynamic>)
          .map((item) => ChecklistItemState.fromJson(item as Map<String, dynamic>))
          .toList(),
      completedCount: json['completed_count'] as int,
      totalCount: json['total_count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'entry_date': formatDateOnly(entryDate),
    'items': items.map((item) => item.toJson()).toList(),
    'completed_count': completedCount,
    'total_count': totalCount,
  };
}
