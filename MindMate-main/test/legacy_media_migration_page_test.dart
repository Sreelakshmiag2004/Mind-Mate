import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/services/legacy_media_migration_service.dart';
import 'package:mindmate/legacy_media_migration_page.dart';
import 'package:mocktail/mocktail.dart';

/// PHASE14I-D. [LegacyMediaMigrationPage] is a thin presentation layer
/// over [LegacyMediaMigrationService] — these tests exercise the WIDGET
/// only, against a mocked service, exactly like `media_repository_test.dart`
/// exercises `MediaRepository` against a mocked `ApiClient`: no real Hive
/// box, filesystem, or network call is ever involved.
class MockLegacyMediaMigrationService extends Mock
    implements LegacyMediaMigrationService {}

LegacyMigrationItemResult _result({
  LegacyMediaKind kind = LegacyMediaKind.image,
  String legacyId = 'img1',
  String title = 'Sunset.jpg',
  LegacyMigrationOutcome outcome = LegacyMigrationOutcome.migrated,
}) => LegacyMigrationItemResult(
  kind: kind,
  legacyId: legacyId,
  legacySource: '${kind.legacySourcePrefix}:$legacyId',
  title: title,
  outcome: outcome,
);

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  late MockLegacyMediaMigrationService service;

  setUp(() {
    service = MockLegacyMediaMigrationService();
  });

  group('no automatic migration', () {
    testWidgets('run() is never called just from building the page', (
      tester,
    ) async {
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (_) async =>
            const LegacyMigrationSummary(results: [], cancelled: false),
      );

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      await tester.pump(
        const Duration(seconds: 1),
      ); // give any stray timer/future a chance to fire

      verifyNever(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      );
    });
  });

  group('starts only after an explicit user action', () {
    testWidgets('tapping "Start Migration" calls service.run() exactly once', (
      tester,
    ) async {
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (_) async =>
            const LegacyMigrationSummary(results: [], cancelled: false),
      );

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pumpAndSettle();

      verify(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).called(1);
    });

    testWidgets(
      'the Start button is disabled while a run is already in progress',
      (tester) async {
        final completer = Completer<LegacyMigrationSummary>();
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pump();

        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('startMigrationButton')),
        );
        expect(button.onPressed, isNull);

        completer.complete(
          const LegacyMigrationSummary(results: [], cancelled: false),
        );
        await tester.pumpAndSettle();
      },
    );
  });

  group('live progress from onItemResult', () {
    testWidgets(
      'a reported item appears in the list as soon as onItemResult fires',
      (tester) async {
        final completer = Completer<LegacyMigrationSummary>();
        void Function(LegacyMigrationItemResult)? onItemResult;
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer((invocation) {
          onItemResult =
              invocation.namedArguments[#onItemResult]
                  as void Function(LegacyMigrationItemResult);
          return completer.future;
        });

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pump();

        expect(find.text('Sunset.jpg'), findsNothing);

        onItemResult!(
          _result(
            title: 'Sunset.jpg',
            outcome: LegacyMigrationOutcome.migrated,
          ),
        );
        await tester.pump();

        expect(find.text('Sunset.jpg'), findsOneWidget);
        expect(find.byKey(const Key('migrationProgressLabel')), findsOneWidget);

        completer.complete(
          const LegacyMigrationSummary(results: [], cancelled: false),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the live counts update as each item is reported', (
      tester,
    ) async {
      final completer = Completer<LegacyMigrationSummary>();
      void Function(LegacyMigrationItemResult)? onItemResult;
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((invocation) {
        onItemResult =
            invocation.namedArguments[#onItemResult]
                as void Function(LegacyMigrationItemResult);
        return completer.future;
      });

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pump();

      onItemResult!(
        _result(legacyId: 'a', outcome: LegacyMigrationOutcome.migrated),
      );
      onItemResult!(
        _result(legacyId: 'b', outcome: LegacyMigrationOutcome.migrated),
      );
      onItemResult!(
        _result(legacyId: 'c', outcome: LegacyMigrationOutcome.failed),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('migratedCount')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('failedCount')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      completer.complete(
        const LegacyMigrationSummary(results: [], cancelled: false),
      );
      await tester.pumpAndSettle();
    });
  });

  group('outcome states are represented correctly', () {
    testWidgets(
      'migrated, alreadyMigrated, skipped, and failed items are each labeled distinctly',
      (tester) async {
        final summary = LegacyMigrationSummary(
          results: [
            _result(
              legacyId: 'a',
              title: 'A',
              outcome: LegacyMigrationOutcome.migrated,
            ),
            _result(
              legacyId: 'b',
              title: 'B',
              outcome: LegacyMigrationOutcome.alreadyMigrated,
            ),
            _result(
              kind: LegacyMediaKind.voice,
              legacyId: 'c',
              title: 'C',
              outcome: LegacyMigrationOutcome.skippedFileMissing,
            ),
            _result(
              kind: LegacyMediaKind.video,
              legacyId: 'd',
              title: 'D',
              outcome: LegacyMigrationOutcome.failed,
            ),
          ],
          cancelled: false,
        );
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer((_) async => summary);

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Migrated'),
          findsWidgets,
        ); // count chip + row label
        expect(find.text('Image · Migrated'), findsOneWidget);
        expect(find.text('Image · Already migrated'), findsOneWidget);
        expect(
          find.text('Voice note · Skipped — file missing'),
          findsOneWidget,
        );
        expect(find.text('Video · Failed'), findsOneWidget);

        expect(
          find.descendant(
            of: find.byKey(const Key('migratedCount')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('alreadyMigratedCount')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('skippedCount')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('failedCount')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('never renders a raw error object or stack trace', (
      tester,
    ) async {
      final summary = LegacyMigrationSummary(
        results: [
          LegacyMigrationItemResult(
            kind: LegacyMediaKind.image,
            legacyId: 'a',
            legacySource: 'image:a',
            title: 'A',
            outcome: LegacyMigrationOutcome.failed,
            error: StateError(
              'some internal detail nobody should see: at file.dart:42',
            ),
          ),
        ],
        cancelled: false,
      );
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((_) async => summary);

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('some internal detail'), findsNothing);
      expect(find.textContaining('file.dart'), findsNothing);
      expect(find.text('Image · Failed'), findsOneWidget);
    });
  });

  group('cancellation', () {
    testWidgets(
      'tapping Cancel makes isCancelled return true on the next check',
      (tester) async {
        final completer = Completer<LegacyMigrationSummary>();
        bool Function()? isCancelled;
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer((invocation) {
          isCancelled =
              invocation.namedArguments[#isCancelled] as bool Function();
          return completer.future;
        });

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pump();

        expect(isCancelled!(), isFalse);

        await tester.tap(find.byKey(const Key('cancelMigrationButton')));
        await tester.pump();

        expect(isCancelled!(), isTrue);

        completer.complete(
          const LegacyMigrationSummary(results: [], cancelled: true),
        );
        await tester.pumpAndSettle();

        expect(find.text('Migration cancelled'), findsOneWidget);
      },
    );

    testWidgets('the Cancel button is only shown while a run is in progress', (
      tester,
    ) async {
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (_) async =>
            const LegacyMigrationSummary(results: [], cancelled: false),
      );

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      expect(find.byKey(const Key('cancelMigrationButton')), findsNothing);

      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cancelMigrationButton')),
        findsNothing,
      ); // run already finished
    });
  });

  group('completion summary', () {
    testWidgets(
      'shows total processed and finishes cleanly when not cancelled',
      (tester) async {
        final summary = LegacyMigrationSummary(
          results: [
            _result(legacyId: 'a', outcome: LegacyMigrationOutcome.migrated),
            _result(
              legacyId: 'b',
              outcome: LegacyMigrationOutcome.alreadyMigrated,
            ),
          ],
          cancelled: false,
        );
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer((_) async => summary);

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('migrationCompletionSummary')),
          findsOneWidget,
        );
        expect(find.text('Migration finished'), findsOneWidget);
        expect(find.text('Processed 2 items.'), findsOneWidget);
      },
    );
  });

  group('re-running the migration', () {
    testWidgets(
      'after a completed run, the button reads "Run Migration Again" and can be tapped',
      (tester) async {
        when(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenAnswer(
          (_) async =>
              const LegacyMigrationSummary(results: [], cancelled: false),
        );

        await tester.pumpWidget(
          _wrap(LegacyMediaMigrationPage(service: service)),
        );
        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pumpAndSettle();

        expect(find.text('Run Migration Again'), findsOneWidget);

        await tester.tap(find.byKey(const Key('startMigrationButton')));
        await tester.pumpAndSettle();

        verify(
          () => service.run(
            onItemResult: any(named: 'onItemResult'),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).called(2);
      },
    );

    testWidgets('starting a new run clears the previous run\'s results', (
      tester,
    ) async {
      var callCount = 0;
      when(
        () => service.run(
          onItemResult: any(named: 'onItemResult'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        callCount++;
        if (callCount == 1) {
          return LegacyMigrationSummary(
            results: [
              _result(
                legacyId: 'a',
                title: 'First run item',
                outcome: LegacyMigrationOutcome.migrated,
              ),
            ],
            cancelled: false,
          );
        }
        return const LegacyMigrationSummary(results: [], cancelled: false);
      });

      await tester.pumpWidget(
        _wrap(LegacyMediaMigrationPage(service: service)),
      );
      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pumpAndSettle();
      expect(find.text('First run item'), findsOneWidget);

      await tester.tap(find.byKey(const Key('startMigrationButton')));
      await tester.pump(); // mid-second-run, before it resolves

      expect(find.text('First run item'), findsNothing);

      await tester.pumpAndSettle();
    });
  });
}
