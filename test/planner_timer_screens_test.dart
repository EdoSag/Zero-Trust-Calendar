import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/ui/home_page.dart';
import 'package:zerotrust_calendar/ui/planner_block_sheet.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';
import 'package:zerotrust_calendar/ui/planner_timer.dart';

import 'planner_screens_test.dart'
    show block, expectRowsInOrder, on, screenOf, task, usePhoneScreen;
import 'planner_support.dart';

/// [b] as "Start now" leaves it: at [from], locked, being timed.
CalendarEvent timed(CalendarEvent b, DateTime from) => b.copyWith(
  start: from,
  end: from.add(b.duration),
  extra: {
    'plan': PlanMark.of(b)!.copyWith(locked: true, started: from).toJson(),
  },
);

void main() {
  Widget blockView(FakeAccount account, {Locale? locale}) => account.app(
    const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: PlannerBlockView(blockId: 'a:1'),
      ),
    ),
    locale: locale,
  );

  testWidgets('a block still to come: "Start now" is its first action, starts the timer, '
      'and then "Stop" is the button on top', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 120)],
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    );
    await tester.pumpWidget(blockView(account));
    await tester.pumpAndSettle();
    expectRowsInOrder(tester, [
      'Start now',
      'Already done',
      'Task finished',
      'Need more time',
      'Not now',
      'Lock here',
      'Move',
      'Open ZT Tasks',
    ]);
    expect(find.text('Moves this block to now and times your work.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Stop'), findsNothing);

    final before = DateTime.now();
    await tester.tap(find.text('Start now'));
    await tester.pumpAndSettle();
    final started = account.blocks.single;
    final mark = PlanMark.of(started)!;
    expect(mark.locked, isTrue);
    expect(mark.started, isNotNull);
    expect(started.start.difference(before).inMinutes.abs(), lessThanOrEqualTo(1));
    expect(started.duration, const Duration(hours: 1), reason: 'the block keeps its length');
    expect(find.text('Started. Stop it when you finish.'), findsOneWidget);

    // The view now shows the timer: Stop on top, then what still makes
    // sense while working. Nothing that would move the block.
    final stop = find.widgetWithText(FilledButton, 'Stop');
    expect(stop, findsOneWidget);
    expect(screenOf(tester).contains(tester.getRect(stop).center), isTrue);
    expect(stop.hitTestable(), findsOneWidget);
    expect(find.text('You are working on it now.'), findsOneWidget);
    final since = find.byKey(const ValueKey('planner-block-running'));
    expect(since, findsOneWidget);
    expect(tester.widget<Text>(since).data, startsWith('Started '));
    expect(tester.widget<Text>(since).data, endsWith('less than a minute'));
    expect(tester.getRect(since).bottom, lessThanOrEqualTo(tester.getRect(stop).top));
    final rows = expectRowsInOrder(tester, ['Task finished', 'Need more time', 'Open ZT Tasks']);
    expect(tester.getRect(stop).bottom, lessThanOrEqualTo(rows.first.top));
    for (final gone in ['Start now', 'Already done', 'Not now', 'Lock here', 'Unlock', 'Move']) {
      expect(find.text(gone), findsNothing, reason: '"$gone" while being timed');
    }
    expect(find.widgetWithText(FilledButton, 'Done'), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });

  testWidgets('"Stop" keeps the time worked, says so, and Undo lets the timer run on', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .subtract(const Duration(minutes: 25));
    final running = timed(block('a:1', 'a', 'Write report', 12), from);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 120)],
      events: [running],
    );
    await tester.pumpWidget(blockView(account));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('planner-block-running'))).data,
      endsWith('25 minutes'),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pumpAndSettle();
    final stopped = account.blocks.single;
    expect(PlanMark.of(stopped)!.done, isTrue);
    expect(PlanMark.of(stopped)!.started, isNull);
    expect(stopped.start, from);
    expect(stopped.duration.inMinutes, inInclusiveRange(25, 26));
    expect(find.textContaining('Stopped. Time worked: 2'), findsOneWidget);
    expect(account.tasks.single.completed, isFalse);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.runningAt(DateTime.now()), isTrue);
    expect(account.blocks.single.end, running.end);
    expect(find.widgetWithText(FilledButton, 'Stop'), findsOneWidget);
  });

  for (final locale in const [Locale('en'), Locale('he')]) {
    testWidgets('the calendar shows what is being timed across the top, with Stop at '
        'the end of the row (${locale.languageCode})', (tester) async {
      usePhoneScreen(tester);
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day, now.hour, now.minute)
          .subtract(const Duration(minutes: 10));
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', 'Write report', auto: true, minutes: 120)],
        events: [timed(block('a:1', 'a', 'Write report', 12), from)],
      );
      account.calendars = [
        ZtCalendarInfo.personal,
        const ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
      ];
      await tester.pumpWidget(account.app(const HomePage(), locale: locale));
      await tester.pumpAndSettle();

      final he = locale.languageCode == 'he';
      final bar = find.byKey(const ValueKey('planner-running'));
      expect(bar, findsOneWidget);
      final rect = tester.getRect(bar);
      final screen = screenOf(tester);
      // Full width, right under the app bar, and not tall.
      expect(rect.left, 0);
      expect(rect.right, screen.right);
      expect(rect.top, lessThan(160));
      expect(rect.height, lessThan(80));
      final title = find.descendant(
        of: bar,
        matching: find.textContaining('Write report'),
      );
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).data, he ? 'בעבודה על: Write report' : 'Working on: Write report');
      final stop = find.byKey(const ValueKey('planner-running-stop'));
      expect(stop.hitTestable(), findsOneWidget);
      final stopRect = tester.getRect(stop);
      // A button, not a full-width bar; inside the row; after the title.
      expect(stopRect.width, lessThan(160));
      expect(rect.contains(stopRect.center), isTrue);
      if (he) {
        expect(stopRect.right, lessThan(tester.getRect(title).left));
        expect(stopRect.left, greaterThanOrEqualTo(0));
      } else {
        expect(stopRect.left, greaterThan(tester.getRect(title).right));
        expect(stopRect.right, lessThanOrEqualTo(screen.right));
      }

      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(PlanMark.of(account.blocks.single)!.done, isTrue);
      expect(find.byKey(const ValueKey('planner-running')), findsNothing);
    });
  }

  testWidgets('nothing is shown across the top when no block is being timed', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true)],
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    );
    await tester.pumpWidget(account.app(const Scaffold(body: PlannerRunningBar())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-running')), findsNothing);
    expect(tester.getSize(find.byType(PlannerRunningBar)).height, 0);
  });

  testWidgets('a planned task\'s sheet starts the timer and logs time; another task\'s '
      'sheet offers neither', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [
        task('a', 'Write report', auto: true, minutes: 120),
        task('b', 'Call the bank', minutes: 15),
      ],
    );
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pumpAndSettle();

    Future<void> openSheet(String id) async {
      final tune = find.descendant(
        of: find.byKey(ValueKey('planner-task-$id')),
        matching: find.byIcon(Icons.tune),
      );
      await tester.ensureVisible(tune);
      await tester.pumpAndSettle();
      await tester.tap(tune);
      await tester.pumpAndSettle();
    }

    await openSheet('a');
    final rows = expectRowsInOrder(tester, ['Start now', 'Log time worked', 'Length']);
    expect(rows, hasLength(3));
    expect(find.text('Adds time you already spent on this task, ending now.'), findsOneWidget);

    await tester.tap(find.text('Log time worked'));
    await tester.pumpAndSettle();
    expect(find.text('How long did you work?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-log-30')));
    await tester.pumpAndSettle();
    final logged = account.blocks.where((b) => PlanMark.of(b)!.done).single;
    expect(logged.duration, const Duration(minutes: 30));
    expect(PlanMark.of(logged)!.itemId, 'a');
    expect(logged.end.difference(DateTime.now()).inMinutes.abs(), lessThanOrEqualTo(1));
    expect(find.text('Time worked added: 30 minutes'), findsOneWidget);
    // The sheet closed, and the task's row shows the time done.
    expect(find.text('Log time worked'), findsNothing);
    expect(find.textContaining('30 minutes done'), findsOneWidget);

    // Undo takes the logged time away again.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(account.blocks.where((b) => PlanMark.of(b)!.done), isEmpty);

    // Start from the sheet: the bar appears on the Planner's screen.
    await openSheet('a');
    await tester.tap(find.text('Start now'));
    await tester.pumpAndSettle();
    expect(account.blocks.where((b) => PlanMark.of(b)!.runningAt(DateTime.now())), hasLength(1));
    expect(find.byKey(const ValueKey('planner-running')), findsOneWidget);
    // Its sheet now offers Stop in place of Start.
    await openSheet('a');
    expectRowsInOrder(tester, ['Stop', 'Log time worked', 'Length']);
    expect(find.byKey(const ValueKey('planner-task-start')), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // A task the Planner doesn't plan: a block of it would be removed again.
    await tester.tap(find.textContaining('Other tasks'));
    await tester.pumpAndSettle();
    await openSheet('b');
    expect(find.text('Length'), findsOneWidget);
    expect(find.text('Start now'), findsNothing);
    expect(find.text('Log time worked'), findsNothing);
  });

  testWidgets('"Planned blocks count as busy" is a switch under the busy calendars, '
      'off by default, and saves', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on);
    await tester.pumpWidget(account.app(const PlannerBusyCalendarsPage()));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('planner-blocks-busy'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    final allDay = find.widgetWithText(SwitchListTile, 'All-day events count as busy');
    final heading = find.text('For other people');
    expect(tester.getRect(allDay).bottom, lessThanOrEqualTo(tester.getRect(heading).top));
    expect(tester.getRect(heading).bottom, lessThanOrEqualTo(tester.getRect(toggle).top));
    expect(screenOf(tester).contains(tester.getRect(toggle).center), isTrue);
    expect(find.textContaining('Booking pages and Find a time'), findsOneWidget);

    account.log.clear();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(account.settings.blocksBusy, isTrue);
    expect(account.log.where((e) => e == 'settings'), hasLength(1));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    // No block is saved or removed for it.
    expect(account.log.where((e) => e.startsWith('save') || e.startsWith('delete')), isEmpty);
  });
}
