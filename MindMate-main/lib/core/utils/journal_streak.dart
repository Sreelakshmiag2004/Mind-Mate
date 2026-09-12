/// PHASE8 Step 11 — replaces the old Firestore journal `streak` field.
///
/// The old field was a stored, per-entry value computed only from
/// *yesterday's* stored streak (`journal_page.dart`'s old `_calculateStreak`
/// — see PHASE8 audit report, Section F): if yesterday had an entry, today's
/// streak was `yesterday.streak + 1`, otherwise `1`. That one-day lookback
/// never re-verified the whole chain, so it could drift from what the
/// entries actually show. The backend deliberately does not store a streak
/// at all (see `backend/README.md`, "Design decisions") — a streak is a
/// derived value, not raw CRUD data.
///
/// This computes it fresh, client-side, from the real entry dates returned
/// by a single list call (`JournalRepository.getEntriesForRange`) — never
/// from a stored field, and never with one request per day.
library;

/// Counts the consecutive run of calendar days, ending at [today] (defaults
/// to `DateTime.now()`), for which [entryDates] contains an entry.
///
/// - If [today] itself is missing from [entryDates], the streak is `0` —
///   per PHASE8 Step 11, "if today has no entry, today's streak should be
///   0," even if yesterday and every day before it has one.
/// - Otherwise, counts today, then yesterday, then the day before, ...,
///   stopping at the first missing date. Entries further in the past than
///   that first gap do not extend the count — a streak broken by a gap
///   cannot be "restarted" by older entries on the far side of it.
/// - [entryDates] may be unsorted and may contain duplicate calendar days
///   (defensive only — the backend's `UNIQUE(user_id, entry_date)`
///   constraint makes a true duplicate impossible) without affecting the
///   result: entries are deduplicated to whole calendar days internally via
///   a `Set`, so a repeated date is only ever counted once.
/// - Every [DateTime] is compared by calendar day only — any time-of-day
///   component is ignored, so this never needs entries or `today` to be
///   time-of-day- or timezone-normalized by the caller.
int calculateJournalStreak(Iterable<DateTime> entryDates, {DateTime? today}) {
  final todayDate = _dateOnly(today ?? DateTime.now());
  final distinctDates = entryDates.map(_dateOnly).toSet();

  if (!distinctDates.contains(todayDate)) return 0;

  var streak = 0;
  var cursor = todayDate;
  while (distinctDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
