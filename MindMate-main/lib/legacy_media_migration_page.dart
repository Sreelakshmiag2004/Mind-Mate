import 'package:flutter/material.dart';

import 'data/services/legacy_media_migration_service.dart';

/// PHASE14I-D — the user-facing trigger/progress screen for
/// [LegacyMediaMigrationService], reached from a "Migrate to cloud" action
/// on [VaultPage]'s header (see `vault.dart`).
///
/// This screen is deliberately a thin presentation layer over the service:
/// every decision about WHAT gets migrated, in WHAT order, whether an item
/// counts as migrated/alreadyMigrated/skipped/failed, and how duplicate-
/// safety/resumability work is entirely [LegacyMediaMigrationService]'s
/// job (see that class's own doc for the full contract) — this widget
/// only calls [LegacyMediaMigrationService.run], renders the
/// [LegacyMigrationItemResult]s it reports via `onItemResult` as they
/// arrive, and forwards a Cancel button press through the existing
/// `isCancelled` callback. No migration logic (ordering, duplicate
/// checks, content-type/size validation, retry/idempotency) is
/// duplicated here.
///
/// Never reached automatically: nothing pushes this route except an
/// explicit tap on the Vault header's migrate button, and nothing inside
/// this widget calls [LegacyMediaMigrationService.run] except
/// [_startMigration], itself only ever invoked from a button's
/// `onPressed`. There is no `initState` auto-start and no background
/// timer/isolate here.
class LegacyMediaMigrationPage extends StatefulWidget {
  // Deliberately NOT `const`: `LegacyMediaMigrationService.instance` is a
  // lazily-initialized getter (see that class's own doc), not a
  // compile-time constant, so this constructor can't be one either.
  LegacyMediaMigrationPage({super.key, LegacyMediaMigrationService? service})
    : _service = service ?? LegacyMediaMigrationService.instance;

  /// Injectable for tests (see `test/legacy_media_migration_page_test.dart`)
  /// — defaults to the real app-wide singleton, matching every other
  /// screen/repository's `?? X.instance` pattern in this codebase.
  final LegacyMediaMigrationService _service;

  @override
  State<LegacyMediaMigrationPage> createState() =>
      _LegacyMediaMigrationPageState();
}

class _LegacyMediaMigrationPageState extends State<LegacyMediaMigrationPage> {
  /// `true` only while a `run()` call is actually in flight — this is what
  /// gates the Start/Cancel buttons and the "nothing has run yet" empty
  /// state. Never set anywhere except inside [_startMigration].
  bool _isRunning = false;

  /// `true` once [_startMigration] has been called at least once — used
  /// only to change the primary button's label from "Start Migration" to
  /// "Run Migration Again" (PHASE14I-D requires re-running to stay
  /// possible; this is purely a UI copy detail, not a behavior gate —
  /// [_startMigration] itself never refuses to run again).
  bool _hasStarted = false;

  /// Polled by the service between items (see
  /// [LegacyMediaMigrationService.run]'s "Cancellation" doc: it is never
  /// checked mid-item) — set by [_requestCancel], reset at the start of
  /// every fresh [_startMigration] call so a later re-run is never
  /// pre-cancelled by a stale request.
  bool _cancelRequested = false;

  /// Every result reported so far in the CURRENT run, in arrival order —
  /// appended to live, from `onItemResult`, so progress renders
  /// incrementally rather than only once the whole run finishes.
  final List<LegacyMigrationItemResult> _liveResults = [];

  /// Set only once [run] itself resolves (naturally finished OR
  /// cancelled) — its presence is what switches the UI from "in
  /// progress" to "finished" and reveals the completion summary.
  LegacyMigrationSummary? _summary;

  Future<void> _startMigration() async {
    setState(() {
      _isRunning = true;
      _hasStarted = true;
      _cancelRequested = false;
      _summary = null;
      _liveResults.clear();
    });

    final summary = await widget._service.run(
      onItemResult: (result) {
        if (!mounted) return;
        setState(() => _liveResults.add(result));
      },
      isCancelled: () => _cancelRequested,
    );

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _summary = summary;
    });
  }

  void _requestCancel() {
    setState(() => _cancelRequested = true);
  }

  /// The results to render: the just-finished run's own list once it
  /// exists (so a re-run's "Clear" moment at [_startMigration]'s top
  /// never causes a stale summary to flash first — `setState` there
  /// clears [_liveResults] and [_summary] in the same frame), otherwise
  /// the live, in-progress list.
  List<LegacyMigrationItemResult> get _displayedResults =>
      _summary?.results ?? _liveResults;

  @override
  Widget build(BuildContext context) {
    // Reuses LegacyMigrationSummary's own counting getters (migratedCount/
    // alreadyMigratedCount/skippedCount/failedCount/hasFailures) instead
    // of re-deriving counts here — the exact "do not duplicate migration
    // logic in the UI" instruction applies just as much to counting
    // outcomes as it does to deciding them.
    final liveSummary = LegacyMigrationSummary(
      results: _displayedResults,
      cancelled: _summary?.cancelled ?? _cancelRequested,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Migrate Vault Media')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Move your existing Vault photos, voice notes, and videos '
                '(images first, then voice notes, then videos) to secure '
                'cloud storage. Nothing on this device is deleted — your '
                'existing Vault items stay exactly where they are.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  ElevatedButton.icon(
                    key: const Key('startMigrationButton'),
                    onPressed: _isRunning ? null : _startMigration,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _hasStarted ? 'Run Migration Again' : 'Start Migration',
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_isRunning)
                    OutlinedButton(
                      key: const Key('cancelMigrationButton'),
                      onPressed: _cancelRequested ? null : _requestCancel,
                      child: Text(_cancelRequested ? 'Cancelling…' : 'Cancel'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_isRunning)
                _ProgressHeader(
                  latest: _liveResults.isEmpty ? null : _liveResults.last,
                ),
              if (_summary != null) _CompletionSummary(summary: _summary!),
              if (_isRunning || _summary != null) ...[
                const SizedBox(height: 12),
                _OutcomeCountsRow(summary: liveSummary),
                const SizedBox(height: 12),
                Expanded(child: _ResultsList(results: _displayedResults)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Currently migrating: `<kind>`" — the closest honest approximation of
/// "the item being processed" this UI can show: [LegacyMediaMigrationService.
/// run] only reports a result once an item's outcome is already decided
/// (there is no separate "now starting item X" event, and this phase
/// deliberately does not add one to the service — see the service's own
/// "do not duplicate/extend migration logic" constraint), so the most
/// recently reported item's kind is what "currently processing" means
/// here, while the run overall is still in flight.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.latest});

  final LegacyMigrationItemResult? latest;

  @override
  Widget build(BuildContext context) {
    final label = latest == null
        ? 'Starting migration…'
        : 'Processing ${_kindLabel(latest!.kind).toLowerCase()}: ${latest!.title}';
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            key: const Key('migrationProgressLabel'),
            style: const TextStyle(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The finished-run summary — total processed plus each outcome's count.
/// Deliberately never renders [LegacyMigrationItemResult.error] itself
/// (which may be a raw, non-[ApiException] object such as a
/// `FileSystemException` or a bare `StateError`): only the fixed,
/// human-written labels below are ever shown, so a stack trace or an
/// internal exception message can never reach this screen.
class _CompletionSummary extends StatelessWidget {
  const _CompletionSummary({required this.summary});

  final LegacyMigrationSummary summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.results.length;
    return Container(
      key: const Key('migrationCompletionSummary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.cancelled ? 'Migration cancelled' : 'Migration finished',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text('Processed $total item${total == 1 ? '' : 's'}.'),
        ],
      ),
    );
  }
}

/// One row of the four outcome counts — used both while a run is in
/// progress (live-updating) and after it finishes (the final tally).
class _OutcomeCountsRow extends StatelessWidget {
  const _OutcomeCountsRow({required this.summary});

  final LegacyMigrationSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _CountChip(
          key: const Key('migratedCount'),
          label: 'Migrated',
          count: summary.migratedCount,
          color: Colors.green,
        ),
        _CountChip(
          key: const Key('alreadyMigratedCount'),
          label: 'Already migrated',
          count: summary.alreadyMigratedCount,
          color: Colors.blueGrey,
        ),
        _CountChip(
          key: const Key('skippedCount'),
          label: 'Skipped',
          count: summary.skippedCount,
          color: Colors.orange,
        ),
        _CountChip(
          key: const Key('failedCount'),
          label: 'Failed',
          count: summary.failedCount,
          color: Colors.red,
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    super.key,
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: color,
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

/// The live/final per-item list — each row's icon+label distinguishes
/// migrated/alreadyMigrated/skipped/failed at a glance, per this phase's
/// own requirement. Never shows [LegacyMigrationItemResult.error] — see
/// [_CompletionSummary]'s doc for why.
class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results});

  final List<LegacyMigrationItemResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(child: Text('No items processed yet.'));
    }
    return ListView.builder(
      key: const Key('migrationResultsList'),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[results.length - 1 - index]; // most recent first
        final (icon, color, label) = _outcomeVisual(result.outcome);
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text(result.title),
          subtitle: Text('${_kindLabel(result.kind)} · $label'),
        );
      },
    );
  }
}

String _kindLabel(LegacyMediaKind kind) {
  switch (kind) {
    case LegacyMediaKind.image:
      return 'Image';
    case LegacyMediaKind.voice:
      return 'Voice note';
    case LegacyMediaKind.video:
      return 'Video';
  }
}

(IconData, Color, String) _outcomeVisual(LegacyMigrationOutcome outcome) {
  switch (outcome) {
    case LegacyMigrationOutcome.migrated:
      return (Icons.cloud_done_outlined, Colors.green, 'Migrated');
    case LegacyMigrationOutcome.alreadyMigrated:
      return (Icons.cloud_queue, Colors.blueGrey, 'Already migrated');
    case LegacyMigrationOutcome.pending:
      return (Icons.hourglass_empty, Colors.grey, 'Pending');
    case LegacyMigrationOutcome.skippedFileMissing:
      return (
        Icons.warning_amber_outlined,
        Colors.orange,
        'Skipped — file missing',
      );
    case LegacyMigrationOutcome.skippedUnsupportedType:
      return (
        Icons.warning_amber_outlined,
        Colors.orange,
        'Skipped — unsupported file type',
      );
    case LegacyMigrationOutcome.skippedTooLarge:
      return (
        Icons.warning_amber_outlined,
        Colors.orange,
        'Skipped — file too large',
      );
    case LegacyMigrationOutcome.failed:
      return (Icons.error_outline, Colors.red, 'Failed');
  }
}
