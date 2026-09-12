import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'journal_entry_page.dart';
// PHASE8: Journal data comes from the FastAPI backend via
// JournalRepository. PHASE13: Shoutout (in this same file/State) has now
// also moved off Firestore, onto ShoutoutRepository — see the PHASE13
// implementation report. No Firebase import remains in this file.
import 'custom_snackbar.dart';
import 'core/network/api_exception.dart';
import 'core/utils/journal_streak.dart';
import 'data/models/journal/journal_model.dart';
import 'data/repositories/journal_repository.dart';
import 'data/repositories/shoutout_repository.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({Key? key}) : super(key: key);

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  DateTime selectedDate = DateTime.now();
  final TextEditingController problemController = TextEditingController();
  String shoutout = '';
  String problem = '';
  String selectedIssue = 'Not Listening, Just Blaming';
  bool? feelBetter;
  bool showCongrats = false;
  bool hasEntry = false;
  String entryTitle = '';
  String entryDescription = '';
  int streak = 0;

  /// PHASE8: the backend-assigned id of the currently-loaded entry (whatever
  /// date that is — today's when set by `_loadTodayJournal`, or the viewed
  /// date's when set by `_loadJournalForDate`). `null` when that date has no
  /// entry. Saving today's entry uses this to decide `PATCH` (id known) vs.
  /// `POST` (id null) — see `JournalRepository.createOrUpdate` and PHASE8
  /// Step 4/Step 6. The old Firestore scheme needed no equivalent: the date
  /// itself was the document id.
  String? journalEntryId;

  /// How many days of history one `getEntriesForRange` call fetches to
  /// compute the streak (PHASE8 Step 11) — comfortably covers any realistic
  /// streak in a single request without ever requesting one day at a time.
  static const int _streakLookbackDays = 60;
  String? todayShoutoutTitle;
  String? todayShoutoutDescription;
  String? yesterdayShoutoutTitle;
  bool? yesterdayFeelBetter;
  bool showFeelBetterCongrats = false;
  bool showFeelBetterComfort = false;

  /// PHASE13: the backend-assigned id of today's/yesterday's Shoutout
  /// (whichever exists), same role for Shoutout as [journalEntryId] plays
  /// for Journal — `null` when that date has no shoutout. Required because
  /// both `PATCH /shoutouts/{id}` and `POST /shoutouts/{id}/feel-better`
  /// address a shoutout by id, never by date (there is no
  /// `GET/PATCH /shoutouts/{date}` — see the PHASE13 backend contract
  /// verification report, Section 6). Deliberately separate fields from
  /// [journalEntryId]: a Journal entry and a Shoutout for the same date are
  /// two unrelated backend resources with their own ids.
  String? todayShoutoutId;
  String? yesterdayShoutoutId;

  @override
  void initState() {
    super.initState();
    _loadTodayJournal();
    _loadTodayShoutout();
    _loadYesterdayShoutout();
    _scheduleMidnightReset();
  }

  // PHASE8: Journal reads/writes go through JournalRepository (FastAPI).
  // PHASE13: Shoutout's methods below this point (_loadTodayShoutout,
  // _loadYesterdayShoutout, _setYesterdayFeelBetter, _resetShoutoutLocal)
  // now go through ShoutoutRepository (FastAPI) too — see the PHASE13
  // implementation report. The dead _saveShoutout() (an incompatible,
  // unreferenced Firestore write) was deleted rather than migrated.

  /// Loads today's entry (if any) and recomputes the streak. Called from
  /// `initState` and from the midnight-reset timer. Doesn't need any
  /// client-supplied identity: the backend derives the acting user from
  /// the Bearer token `ApiClient` attaches (PHASE8 Step 3).
  Future<void> _loadTodayJournal() async {
    final today = DateTime.now();
    try {
      final entry = await JournalRepository.instance.getForDate(today);
      final newStreak = await _computeStreak(today);
      if (!mounted) return;
      setState(() {
        _applyLoadedEntry(entry);
        streak = newStreak;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyJournalError(e));
    }
  }

  /// Saves [title]/[description] for [date] (in practice, always today —
  /// the UI only allows writing/editing today's entry, enforced by the
  /// button's own `onPressed` gate below, PHASE8 Step 8).
  ///
  /// PHASE8 Step 9: unlike the old Firestore `.set()`, this call can
  /// genuinely fail (network, 401-after-failed-refresh, 409, 422, ...). The
  /// UI is therefore no longer updated optimistically before this runs —
  /// callers await this method and it alone decides what the screen shows,
  /// only after the backend confirms the save. On failure, the screen is
  /// rolled back to its last known-good state and a clean, non-technical
  /// message is shown instead of leaving the UI claiming the entry saved.
  Future<void> _saveJournal(String title, String description, DateTime date) async {
    final previousHasEntry = hasEntry;
    final previousEntryId = journalEntryId;
    final previousTitle = entryTitle;
    final previousDescription = entryDescription;
    final previousStreak = streak;
    final previousShowCongrats = showCongrats;
    try {
      final saved = await JournalRepository.instance.createOrUpdate(
        entryDate: date,
        existingId: journalEntryId,
        title: title,
        content: description,
      );
      final newStreak = await _computeStreak(DateTime.now());
      if (!mounted) return;
      setState(() {
        hasEntry = true;
        journalEntryId = saved.id;
        entryTitle = saved.title ?? '';
        entryDescription = saved.content ?? '';
        streak = newStreak;
        showCongrats = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        hasEntry = previousHasEntry;
        journalEntryId = previousEntryId;
        entryTitle = previousTitle;
        entryDescription = previousDescription;
        streak = previousStreak;
        showCongrats = previousShowCongrats;
      });
      showCustomSnackBar(context, _friendlyJournalError(e));
    }
  }

  /// Loads the entry for an arbitrary [date] — used by the date picker's
  /// "View" flow, and internally before deciding Write vs. Edit mode for
  /// today. Deliberately does not touch [streak]: streak is a single,
  /// today-relative value (PHASE8 Step 11) owned by [_loadTodayJournal] and
  /// [_saveJournal], not a per-entry value the old Firestore doc's `streak`
  /// field used to be — viewing a past date's entry no longer overwrites it.
  Future<void> _loadJournalForDate(DateTime date) async {
    try {
      final entry = await JournalRepository.instance.getForDate(date);
      if (!mounted) return;
      setState(() => _applyLoadedEntry(entry));
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyJournalError(e));
    }
  }

  /// Shared by [_loadTodayJournal] and [_loadJournalForDate]: applies a
  /// loaded (or absent) entry to the Journal fields. Must be called from
  /// inside a `setState`.
  void _applyLoadedEntry(JournalModel? entry) {
    if (entry != null) {
      hasEntry = true;
      journalEntryId = entry.id;
      entryTitle = entry.title ?? '';
      entryDescription = entry.content ?? '';
      showCongrats = true;
    } else {
      hasEntry = false;
      journalEntryId = null;
      entryTitle = '';
      entryDescription = '';
      showCongrats = false;
    }
  }

  /// PHASE8 Step 11: fetches one window of history ending at [today] in a
  /// single list request (never one request per day) and computes the
  /// consecutive-day streak from the real entry dates it returns — see
  /// `core/utils/journal_streak.dart` for the actual counting logic, kept
  /// separate so it can be unit-tested without any network involved.
  Future<int> _computeStreak(DateTime today) async {
    final rangeStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: _streakLookbackDays - 1));
    final entries = await JournalRepository.instance.getEntriesForRange(rangeStart, today, limit: 100);
    return calculateJournalStreak(entries.map((e) => e.entryDate), today: today);
  }

  /// Maps a Journal [ApiException] to a short, clean, user-facing message —
  /// PHASE8 Step 9 asks specifically for network / 401 / 409 / 422 to each
  /// read sensibly for this screen; every other status falls back to
  /// [ApiException.message], which is already documented as safe to show
  /// directly (see `api_exception.dart`'s class doc) — never a raw
  /// exception string or stack trace.
  String _friendlyJournalError(ApiException e) {
    if (e is ConflictException) {
      return 'You already have a journal entry for that date.';
    }
    if (e is ValidationException) {
      return "That journal entry couldn't be saved — please shorten the title or text and try again.";
    }
    if (e is NetworkException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (e is UnauthorizedException) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong saving your journal. Please try again.';
  }

  /// Loads today's shoutout (if any) via `ShoutoutRepository.getForDate`
  /// (PHASE13 — replacing the old Firestore doc `.get()`). There is no
  /// `GET /shoutouts/{date}`, so this is a one-day range lookup under the
  /// hood — see the PHASE13 backend contract verification report, Section
  /// 6. [todayShoutoutId] is captured here because saving from
  /// `shoutout_page.dart` needs to know whether a shoutout already exists
  /// for today, and because `main.dart`'s `/shoutout` route still reads
  /// this state to prefill that screen.
  ///
  /// On failure, whatever was already showing is left untouched — only a
  /// friendly snackbar is shown, matching every other migrated feature's
  /// load failure handling in this app.
  Future<void> _loadTodayShoutout() async {
    try {
      final shoutout = await ShoutoutRepository.instance.getForDate(DateTime.now());
      if (!mounted) return;
      setState(() {
        todayShoutoutId = shoutout?.id;
        todayShoutoutTitle = shoutout?.title;
        todayShoutoutDescription = shoutout?.content;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyShoutoutError(e));
    }
  }

  /// Loads yesterday's shoutout (if any) the same way [_loadTodayShoutout]
  /// does. [yesterdayFeelBetter] now comes from the backend's persisted
  /// `felt_better` (PHASE13 fixes the old app's bug: it read
  /// `doc['feelBetter']` but nothing ever wrote it — see the PHASE13
  /// backend contract verification report, Section 5), so
  /// [showFeelBetterCongrats]/[showFeelBetterComfort] are derived from it
  /// right here too — otherwise a returning user whose answer already
  /// persisted would see the Yes/No prompt again instead of their actual
  /// outcome.
  Future<void> _loadYesterdayShoutout() async {
    try {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final shoutout = await ShoutoutRepository.instance.getForDate(yesterday);
      if (!mounted) return;
      setState(() {
        yesterdayShoutoutId = shoutout?.id;
        yesterdayShoutoutTitle = shoutout?.title;
        yesterdayFeelBetter = shoutout?.feltBetter;
        showFeelBetterCongrats = shoutout?.feltBetter == true;
        showFeelBetterComfort = shoutout?.feltBetter == false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyShoutoutError(e));
    }
  }

  /// Maps a Shoutout [ApiException] to a short, clean, user-facing
  /// message — same approach as [_friendlyJournalError]. Every status this
  /// doesn't specifically name falls back to [ApiException.message],
  /// already documented as safe to show directly.
  String _friendlyShoutoutError(ApiException e) {
    if (e is ConflictException) {
      return "That date's shoutout couldn't be saved — please try again.";
    }
    if (e is ValidationException) {
      return "That shoutout couldn't be saved — please shorten the title or text and try again.";
    }
    if (e is NetworkException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (e is UnauthorizedException) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong with your shoutout. Please try again.';
  }

  void _resetShoutoutLocal() {
    setState(() {
      todayShoutoutId = null;
      todayShoutoutTitle = null;
      todayShoutoutDescription = null;
      yesterdayShoutoutId = null;
      yesterdayShoutoutTitle = null;
    });
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    Future.delayed(duration, () async {
      setState(() {
        hasEntry = false;
        entryTitle = '';
        entryDescription = '';
        showCongrats = false;
        // Do not reset streak here — it's recomputed from the backend by
        // _loadTodayJournal() below, once the new day's data is loaded.
        showFeelBetterCongrats = false;
        showFeelBetterComfort = false;
        yesterdayFeelBetter = null;
      });
      _resetShoutoutLocal();
      _scheduleMidnightReset(); 
      _loadTodayJournal(); 
      _loadTodayShoutout(); 
    });
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    problemController.dispose();
    super.dispose();
  }

  // PHASE13: the old _saveShoutout() here (an unreferenced, dead method —
  // confirmed by the PHASE12 audit and `flutter analyze` — that wrote an
  // auto-id Firestore doc in a shape ({'problem': ..., 'timestamp': ...})
  // no read path ever consumed) has been deleted rather than migrated. See
  // the PHASE13 backend contract verification report and implementation
  // report for the full audit trail.

  /// Answers yesterday's "did you feel better?" follow-up via
  /// `POST /shoutouts/{id}/feel-better` (PHASE13 — replacing the old
  /// implementation, which only ever called `setState()` and never
  /// persisted anything: a confirmed bug, not a design choice, per the
  /// PHASE13 backend contract verification report, Section 5).
  ///
  /// [yesterdayShoutoutId] is required — if it's `null` (no shoutout was
  /// recorded yesterday, so there is nothing to answer), this does
  /// nothing rather than send an invalid request.
  ///
  /// The UI is only updated once the backend confirms the answer — never
  /// optimistically. The backend's `felt_better` is strictly one-shot: a
  /// second attempt for the same shoutout 409s. That is NOT treated as a
  /// failure here — it means this exact question was already answered (by
  /// this screen, another device, or a retry), so yesterday's shoutout is
  /// re-fetched and the UI is driven from whatever the backend actually
  /// has stored, exactly as [_loadYesterdayShoutout] would show on a fresh
  /// load, rather than fighting the backend's one-shot rule with a
  /// generic error.
  Future<void> _setYesterdayFeelBetter(bool value) async {
    final shoutoutId = yesterdayShoutoutId;
    if (shoutoutId == null) return;

    try {
      final updated = await ShoutoutRepository.instance.answerFeelBetter(shoutoutId, value);
      if (!mounted) return;
      setState(() {
        yesterdayFeelBetter = updated.feltBetter;
        showFeelBetterCongrats = updated.feltBetter == true;
        showFeelBetterComfort = updated.feltBetter == false;
      });
    } on ConflictException {
      // Already answered (one-shot) — re-fetch and show the persisted
      // outcome instead of a generic error, per PHASE13 Step 6.
      await _loadYesterdayShoutout();
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyShoutoutError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 251, 213, 213),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.pink[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/journal_bg.png',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 180,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 45,
                        child: Center(
                          child: Text(
                            'Journal Space',
                            style: const TextStyle(
                              fontFamily: 'Puppies Play',
                              fontSize: 70,
                              color: Color(0xFF7B3F1D),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Journal Section
                    Row(
                      children: [
                        const Text(
                          'Journal',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, 248, 200, 178),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.star, color: Color(0xFFFFB300), size: 22),
                              SizedBox(width: 6),
                              Text(
                                'Write your heart out, this space\nhears without judgement',
                                style: TextStyle(fontSize: 12, color: Color(0xFF5A3A1B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFDA8D7A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      readOnly: true,
                                      controller: TextEditingController(
                                        text: DateFormat('MM/dd/yyyy').format(selectedDate),
                                      ),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 2),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFFDA8D7A)),
                                          onPressed: () async {
                                            DateTime? picked = await showDatePicker(
                                              context: context,
                                              initialDate: selectedDate,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked != null) {
                                              setState(() {
                                                selectedDate = picked;
                                              });
                                              _loadJournalForDate(selectedDate);
                                            }
                                          },
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFDA8D7A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      await _loadJournalForDate(selectedDate);
                                      if (hasEntry) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => JournalEntryPage(
                                              date: selectedDate,
                                              streak: streak,
                                              title: entryTitle,
                                              description: entryDescription,
                                              readOnly: true,
                                            ),
                                          ),
                                        );
                                      } else {
                                        showCustomSnackBar(context, 'No journal entry for this date.');
                                      }
                                    },
                                    child: const Text('View', style: TextStyle(fontSize: 15, color: Colors.white)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'MM/DD/YYYY',
                                style: TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w400),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Scroll streak
                          LayoutBuilder(
                            builder: (context, constraints) {
                              double scrollWidth = constraints.maxWidth - 26; // 18px padding on each side
                              double scrollHeight = 1.5 * scrollWidth; // Adjust as needed for your image ratio

                              return Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Enlarged Scroll background
                                    Image.asset(
                                      'assets/scroll.png',
                                      width: scrollWidth,
                                      height: scrollHeight,
                                      fit: BoxFit.fill,
                                    ),
                                    // Content on top of scroll
                                    SizedBox(
                                      width: scrollWidth * 0.8, // Keep content within scroll area
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (showCongrats)
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: Colors.orange.shade200, width: 1),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                                                      SizedBox(width: 4),
                                                      Text(streak.toString(), style: TextStyle(fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                const Text(
                                                  'Great!\nEvery Feeling\nDeserves A Page',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                                ),
                                              ],
                                            )
                                          else
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Fire streak
                                                Container(
                                                  margin: const EdgeInsets.only(bottom: 18),
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(500),
                                                    border: Border.all(color: Colors.orange.shade200, width: 1),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                                                      SizedBox(width: 6),
                                                      Text(streak.toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                const Text(
                                                  'Pending...\nLet\'s complete',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 22),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                                                colors: [
                                                  Color(0xFFA86F1F), // 0%
                                                  Color(0xFFC98C2B), // 25%
                                                  Color(0xFFEFC162), // 50%
                                                  Color(0xFFD9943C), // 75%
                                                  Color(0xFF9B611C), // 100%
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(32),
                                            ),
                                            height: 30,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(32),
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 0),
                                              ),
                                              onPressed: DateTime.now().year == selectedDate.year && DateTime.now().month == selectedDate.month && DateTime.now().day == selectedDate.day
                                                  ? () async {
                                                      await _loadJournalForDate(selectedDate);
                                                      if (hasEntry) {
                                                        // Edit mode
                                                        final result = await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => JournalEntryPage(
                                                              date: selectedDate,
                                                              streak: streak,
                                                              title: entryTitle,
                                                              description: entryDescription,
                                                              readOnly: false,
                                                            ),
                                                          ),
                                                        );
                                                        if (result is Map) {
                                                          // PHASE8 Step 9: no optimistic setState here anymore —
                                                          // _saveJournal itself only updates the UI once the
                                                          // backend confirms the save, and rolls back with an
                                                          // error snackbar if it fails.
                                                          await _saveJournal(
                                                            (result['title'] as String?) ?? '',
                                                            (result['description'] as String?) ?? '',
                                                            selectedDate,
                                                          );
                                                        }
                                                      } else {
                                                        // Write mode
                                                        final result = await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => JournalEntryPage(
                                                              date: selectedDate,
                                                              streak: streak,
                                                            ),
                                                          ),
                                                        );
                                                        if (result is Map) {
                                                          await _saveJournal(
                                                            (result['title'] as String?) ?? '',
                                                            (result['description'] as String?) ?? '',
                                                            selectedDate,
                                                          );
                                                        }
                                                      }
                                                    }
                                                  : () {
                                                      showCustomSnackBar(context, "You can only write or  today's journal.");
                                                    },
                                              child: Text(hasEntry ? 'Edit' : "Let's Write", style: const TextStyle(fontSize: 16, color: Colors.black)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Shoutout Section
                    Row(
                      children: [
                        const Text(
                          'Shoutout',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7C7B0),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.star, color: Color(0xFFFFB300), size: 22),
                              SizedBox(width: 6),
                              Text(
                                'A safe space to unburden your\nheart.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF5A3A1B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Add a view-only textbox at the top, only if no shoutout for today
                          if (todayShoutoutTitle == null || todayShoutoutTitle!.isEmpty)
                            TextField(
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: 'What\'s Weighing on your mind? ',
                                filled: true,
                                fillColor: const Color(0xFFF9D7C7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              style: const TextStyle(fontSize: 16, color: Colors.black54),
                            ),
                          if (todayShoutoutTitle == null || todayShoutoutTitle!.isEmpty)
                            const SizedBox(height: 16),
                          if (todayShoutoutTitle != null && todayShoutoutTitle!.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Today\'s Shoutout:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(todayShoutoutTitle ?? '', style: const TextStyle(fontSize: 16)),
                                if (todayShoutoutDescription != null && todayShoutoutDescription!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(todayShoutoutDescription ?? '', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                                  ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          Center(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDA8D7A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(80),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 0),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                // Navigate to shoutout page for add/edit.
                                // PHASE13: 'userId' is passed as null —
                                // ShoutoutPage/ShoutoutRepository no longer
                                // use it for anything; the backend derives
                                // the acting user from the Bearer token.
                                // Kept as a key only because
                                // ShoutoutPage's constructor still declares
                                // a `required this.userId` parameter (of
                                // nullable type), unchanged to keep this
                                // surgical.
                                final result = await Navigator.pushNamed(context, '/shoutout', arguments: {
                                  'title': todayShoutoutTitle,
                                  'description': todayShoutoutDescription,
                                  'dateKey': _dateKey(DateTime.now()),
                                  'userId': null,
                                });
                                if (result == true) {
                                  _loadTodayShoutout();
                                  _loadYesterdayShoutout();
                                }
                              },
                              child: Text(
                                (todayShoutoutTitle != null && todayShoutoutTitle!.isNotEmpty) ? 'Edit' : 'Add',
                                style: const TextStyle(fontSize: 18, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (yesterdayShoutoutTitle != null && yesterdayShoutoutTitle!.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Color(0xFFDA8D7A)),
                              ),
                              child: showFeelBetterCongrats
                                  ? SizedBox(
                                      height: 180,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Great!',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            "That's A Small Win&\nEvery Win Matters ",
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            '💗',
                                            style: TextStyle(fontSize: 28),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  : showFeelBetterComfort
                                    ? SizedBox(
                                        height: 180,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "It's Ok To Not Be Okay! It Will Be Fine Soon",
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              '💗',
                                              style: TextStyle(fontSize: 28),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          const Text(
                                            'Do You Feel Better Now About',
                                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            yesterdayShoutoutTitle ?? '',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              color: Color(0xFFDA8D7A),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 90,
                                                height: 40,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Color(0xFFDA8D7A),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(32),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: () => _setYesterdayFeelBetter(true),
                                                  child: const Text(
                                                    'Yes',
                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 90,
                                                height: 40,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Color(0xFFDA8D7A),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(32),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: () => _setYesterdayFeelBetter(false),
                                                  child: const Text(
                                                    'No',
                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                            ),
                          if (yesterdayShoutoutTitle == null || yesterdayShoutoutTitle!.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Color(0xFFDA8D7A)),
                              ),
                              child: const Center(
                                child: Text(
                                  'No shoutout recorded yesterday.',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFDA8D7A)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 