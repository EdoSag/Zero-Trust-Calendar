import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/data/event_done.dart';
import 'package:zerotrust_calendar/ui/calendars_page.dart';
import 'package:zerotrust_calendar/ui/event_details_page.dart';
import 'package:zerotrust_calendar/ui/month_view.dart';
import 'package:zerotrust_calendar/ui/navigation.dart';
import 'package:zerotrust_calendar/ui/planner_block_sheet.dart';
import 'package:zerotrust_calendar/ui/planner_risks.dart';
import 'package:zerotrust_calendar/ui/entry_widgets.dart';
import 'package:zerotrust_calendar/ui/home_page.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';
import 'package:zerotrust_calendar/ui/planner_setup_page.dart';
import 'package:zerotrust_calendar/ui/timeline_view.dart';

import 'planner_support.dart';

/// A 1080x2400 phone, like the devices the app ships to.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Rect screenOf(WidgetTester tester) =>
    Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

/// The button showing [label] is laid out inside the screen and a tap on
/// its centre reaches it (a button that failed layout is not drawn at all).
void expectTappableOnScreen(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(button, findsOneWidget, reason: '"$label" button is missing');
  final rect = tester.getRect(button);
  expect(rect.width, greaterThan(0), reason: '"$label" has no width');
  expect(rect.isFinite, isTrue, reason: '"$label" has no finite size');
  expect(screenOf(tester).contains(rect.center), isTrue,
      reason: '"$label" is off screen at $rect');
  expect(button.hitTestable(), findsOneWidget,
      reason: '"$label" is covered or cannot be tapped');
}

/// The rows showing [labels] (a block's actions) are on the screen, can be
/// tapped, and come one under the other in that order. Returns their rects.
List<Rect> expectRowsInOrder(WidgetTester tester, List<String> labels) {
  final rects = <Rect>[];
  for (final label in labels) {
    final row = find.ancestor(of: find.text(label), matching: find.byType(ListTile));
    expect(row, findsOneWidget, reason: 'the "$label" row is missing');
    final rect = tester.getRect(row);
    expect(rect.height, greaterThan(40), reason: '"$label" has no height');
    expect(screenOf(tester).contains(rect.center), isTrue,
        reason: '"$label" is off screen at $rect');
    expect(row.hitTestable(), findsOneWidget, reason: '"$label" cannot be tapped');
    if (rects.isNotEmpty) {
      expect(rect.top, greaterThanOrEqualTo(rects.last.bottom),
          reason: '"$label" is not below the row before it');
    }
    rects.add(rect);
  }
  return rects;
}

/// Work every day, all day: the tests don't depend on when they run.
final everyDay = {
  workHoursId: {
    for (var d = 1; d <= 7; d++) d: const [(0, 1440)],
  },
};

final on = PlannerSettings(enabled: true, hours: everyDay);

PlannerTask task(String id, String title, {bool? auto, int? minutes}) =>
    PlannerTask(id: id, title: title, auto: auto, minutes: minutes, createdAt: id);

/// A block of [taskId] from [hour] for one hour, today or [days] later.
CalendarEvent block(
  String id,
  String taskId,
  String title,
  int hour, {
  bool done = false,
  int days = 0,
}) {
  final now = DateTime.now();
  return CalendarEvent(
    id: id,
    title: title,
    start: DateTime(now.year, now.month, now.day + days, hour),
    end: DateTime(now.year, now.month, now.day + days, hour + 1),
    calendarId: plannerCalendarId,
    taskIds: [taskId],
    reminders: const [0],
    extra: {
      'plan': {'type': 'task', 'taskId': taskId, 'locked': false, 'done': done},
    },
  );
}

void main() {
  testWidgets('the drawer opens the Planner, which explains itself before it is on', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount();
    await tester.pumpWidget(account.app(const HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(ListTile, 'Planner');
    expect(entry, findsOneWidget);
    // In the drawer, above Settings.
    expect(
      tester.getCenter(entry).dy,
      lessThan(tester.getCenter(find.widgetWithText(ListTile, 'Settings')).dy),
    );
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(PlannerPage), findsOneWidget);
    expect(find.text('Let Calendar plan your tasks'), findsOneWidget);
    expectTappableOnScreen(tester, 'Set up the Planner');
    expect(account.log, isEmpty);
  });

  testWidgets('the setup goes through hours, tasks, defaults and a preview, '
      'and saves nothing until it is turned on', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      tasks: [task('a', 'Write report'), task('b', 'Call the bank', minutes: 15)],
    );
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up the Planner'));
    await tester.pumpAndSettle();
    expect(find.byType(PlannerSetupPage), findsOneWidget);

    // 1. Hours: work hours listed above personal hours, Next at the bottom.
    expect(find.text('Your hours'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Work hours')).dy,
      lessThan(tester.getTopLeft(find.text('Personal hours')).dy),
    );
    expectTappableOnScreen(tester, 'Next');
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
    expect(next.bottom, greaterThan(screenOf(tester).height * 0.85),
        reason: 'Next sits at the bottom of the screen');
    expect(next.width, greaterThan(screenOf(tester).width * 0.8),
        reason: 'Next is a full-width button');
    // English: the work week is Monday to Friday.
    final monday = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Monday').first,
    );
    final sunday = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Sunday').first,
    );
    expect(monday.value, isTrue);
    expect(sunday.value, isFalse);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 2. Tasks: "Only tasks I switch on" is the default, with the open
    // tasks to pick from.
    expect(find.text('Which tasks'), findsOneWidget);
    expect(find.text('Only tasks I switch on'), findsOneWidget);
    expect(find.text('All tasks'), findsOneWidget);
    final pick = find.widgetWithText(CheckboxListTile, 'Call the bank');
    expect(tester.widget<CheckboxListTile>(pick).value, isFalse);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(pick).value, isTrue);
    expectTappableOnScreen(tester, 'Back');
    expect(
      tester.getRect(find.widgetWithText(TextButton, 'Back')).top,
      greaterThanOrEqualTo(tester.getRect(find.widgetWithText(FilledButton, 'Next')).bottom),
      reason: 'Back sits under Next',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 3. Defaults.
    expect(find.text('Defaults'), findsOneWidget);
    final usual = find.widgetWithText(ListTile, 'Usual task length');
    expect(find.descendant(of: usual, matching: find.text('30 minutes')), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Longest block'),
        matching: find.text('2 hours'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 4. Preview: the picked task is planned, the other is not, and
    // nothing has been written.
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('Call the bank'), findsOneWidget);
    expect(find.text('Write report'), findsNothing);
    expect(account.log, isEmpty);
    expectTappableOnScreen(tester, 'Turn on the Planner');
    await tester.tap(find.text('Turn on the Planner'));
    await tester.pumpAndSettle();

    expect(account.settings.enabled, isTrue);
    expect(account.log.first, 'task b {planAuto: true}');
    expect(account.log, containsAll(['calendar', 'settings']));
    // Back on the Planner, now on, and after a moment the block is saved.
    expect(find.byType(PlannerSetupPage), findsNothing);
    expect(find.text('Tasks to plan'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(account.blocks.map((b) => b.title), ['Call the bank']);
    expect(account.blocks.single.duration.inMinutes, 15);
  });

  testWidgets('the Planner lists planned tasks with a switch, the week and its settings', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 60), task('c', 'Clean garage')],
      // Tomorrow, so the test reads the same at any time of day.
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    );
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final screen = screenOf(tester);

    // The week: tomorrow's bar is taller than today's empty one, and to
    // its right.
    final now = DateTime.now();
    final today = find.byKey(ValueKey('planner-bar-${dayKeyOf(now)}'));
    final tomorrow = find.byKey(
      ValueKey('planner-bar-${dayKeyOf(DateTime(now.year, now.month, now.day + 1))}'),
    );
    expect(tester.getSize(tomorrow).height, greaterThan(tester.getSize(today).height));
    expect(tester.getCenter(today).dx, lessThan(tester.getCenter(tomorrow).dx));
    // Nothing was rewritten: the block was where the plan wants it.
    expect(account.log, isEmpty);
    expect(find.text('1 hour planned'), findsOneWidget);

    // The planned task: title on the left, its switch (on) on the right.
    final tile = find.byKey(const ValueKey('planner-task-a'));
    expect(tile, findsOneWidget);
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.getCenter(toggle).dx, greaterThan(screen.width * 0.75));
    expect(
      tester.getTopLeft(find.descendant(of: tile, matching: find.text('Write report'))).dx,
      lessThan(tester.getTopLeft(toggle).dx),
    );
    expect(screen.contains(tester.getCenter(toggle)), isTrue);
    expect(find.descendant(of: tile, matching: find.textContaining('1 hour')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('next: Tomorrow')), findsOneWidget);
    // Below the planned tasks, the ones that are not switched on.
    final others = find.text('Other tasks (1)');
    expect(tester.getTopLeft(others).dy, greaterThan(tester.getBottomLeft(tile).dy - 1));

    // Switching the task off is written to ZT Tasks.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(account.log, contains('task a {planAuto: false}'));
    // It moves under "Other tasks", switched off.
    expect(find.byKey(const ValueKey('planner-task-a')), findsNothing);
    await tester.tap(find.text('Other tasks (2)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(const ValueKey('planner-task-a')),
              matching: find.byType(Switch),
            ),
          )
          .value,
      isFalse,
    );
    // And a moment later its block is gone from the calendar.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(account.blocks, isEmpty);

    // Settings further down.
    await tester.scrollUntilVisible(find.text('Most planned time per day'), 300);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Most planned time per day'),
        matching: find.text('6 hours'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Turn off the Planner'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off the Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off the Planner?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Turn off the Planner'));
    await tester.pumpAndSettle();
    expect(account.settings.enabled, isFalse);
    expect(find.text('Let Calendar plan your tasks'), findsOneWidget);
  });

  testWidgets('blocks show on the calendar with the planner mark, and open their own sheet', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 120)],
      events: [
        block('a:1', 'a', 'Write report', 12),
        block('a:2', 'a', 'Write report', 15),
        CalendarEvent(
          id: 'meeting',
          title: 'Team meeting',
          start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 13),
          end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 14),
        ),
      ],
    )..calendars = [
      ZtCalendarInfo.personal,
      const ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
    ];
    await tester.pumpWidget(account.app(const HomePage()));
    await tester.pumpAndSettle();
    // Month view: both blocks, numbered.
    expect(find.textContaining('Write report (1 of 2)'), findsWidgets);

    // Day view: the blocks in time order around the meeting, each marked.
    final container = ProviderScope.containerOf(tester.element(find.byType(HomePage)));
    await container
        .read(calendarSettingsProvider.notifier)
        .update((s) => s.copyWith(view: CalendarView.day));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsOneWidget);
    final first = find.text('Write report (1 of 2)');
    final second = find.text('Write report (2 of 2)');
    final meeting = find.text('Team meeting');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(meeting).dy));
    expect(tester.getTopLeft(meeting).dy, lessThan(tester.getTopLeft(second).dy));
    expect(find.byIcon(plannerIcon), findsNWidgets(2));
    // The mark sits before the title, inside the block.
    final mark = find.byIcon(plannerIcon).first;
    expect(tester.getCenter(mark).dx, lessThan(tester.getTopLeft(first).dx));
    expect((tester.getCenter(mark).dy - tester.getCenter(first).dy).abs(), lessThan(12));

    // A tap opens the block's sheet, not the event editor.
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('Part 1 of 2'), findsOneWidget);
    expect(find.text('The Planner moves this block when your calendar changes.'), findsOneWidget);
    // Its actions are rows, one under the other, all on the screen.
    expectRowsInOrder(tester, ['Task finished', 'Need more time', 'Move', 'Open ZT Tasks']);
    expect(find.text('Edit'), findsNothing);
  });

  /// The block's own view, as the sheet and the page for a block show it.
  Widget blockView(FakeAccount account, {Locale? locale}) => account.app(
    const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: PlannerBlockView(blockId: 'a:1'),
      ),
    ),
    locale: locale,
  );

  testWidgets('a block still to come: every action is on screen, and "Lock here" locks it', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 60)],
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    );
    await tester.pumpWidget(blockView(account));
    await tester.pumpAndSettle();
    expectRowsInOrder(tester, [
      'Already done',
      'Task finished',
      'Need more time',
      'Not now',
      'Lock here',
      'Move',
      'Open ZT Tasks',
    ]);
    // "Done" is for a block that has started.
    expect(find.widgetWithText(FilledButton, 'Done'), findsNothing);
    expect(find.text('The Planner moves this block when your calendar changes.'), findsOneWidget);

    await tester.tap(find.text('Lock here'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.locked, isTrue);
    expect(account.log, ['save a:1']);
    // The view stays open and now shows the lock and the way back.
    expect(find.text('Locked at this time'), findsOneWidget);
    expect(find.text('You locked it at this time.'), findsOneWidget);
    expect(find.text('The Planner moves this block when your calendar changes.'), findsNothing);
    expectRowsInOrder(tester, ['Not now', 'Unlock', 'Move']);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.locked, isFalse);
  });

  testWidgets('a running block: "Done" is the button on top, the last part finishes '
      'the task, and Undo puts both back', (tester) async {
    usePhoneScreen(tester);
    final now = DateTime.now();
    final started = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .subtract(const Duration(minutes: 10));
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 60)],
      events: [
        block('a:1', 'a', 'Write report', 12).copyWith(
          start: started,
          end: started.add(const Duration(hours: 1)),
        ),
      ],
    );
    await tester.pumpWidget(blockView(account));
    await tester.pumpAndSettle();
    expectTappableOnScreen(tester, 'Done');
    final done = tester.getRect(find.widgetWithText(FilledButton, 'Done'));
    // Full width, above the rows.
    expect(done.width, greaterThan(screenOf(tester).width - 60));
    final rows = expectRowsInOrder(tester, [
      'Task finished',
      'Need more time',
      'Not now',
      'Move',
      'Open ZT Tasks',
    ]);
    expect(done.bottom, lessThanOrEqualTo(rows.first.top));
    // Locking is for blocks still to come; this one is already running.
    expect(find.text('Lock here'), findsNothing);
    expect(find.text('Already done'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.done, isTrue);
    expect(account.tasks.single.completed, isTrue);
    expect(find.text('Task finished. Saved in ZT Tasks.'), findsOneWidget);
    // Done blocks are history: one way back, nothing else.
    expectRowsInOrder(tester, ['Not done after all', 'Open ZT Tasks']);
    expect(find.text('Move'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.done, isFalse);
    expect(account.tasks.single.completed, isFalse);
    expect(account.blocks.single.start, started);
  });

  testWidgets('"Not now" asks until when, and "Need more time" how much', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 60)],
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    );
    await tester.pumpWidget(blockView(account));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Need more time'));
    await tester.pumpAndSettle();
    expect(find.text('How much more time?'), findsOneWidget);
    for (final choice in ['15 minutes', '30 minutes', '1 hour', '2 hours']) {
      expect(find.text(choice).hitTestable(), findsOneWidget, reason: choice);
    }
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(account.tasks.single.minutes, 90);
    expect(find.text('Added to the task: 30 minutes'), findsOneWidget);
    // The block is still to come, so it is not marked done.
    expect(PlanMark.of(account.blocks.single)!.done, isFalse);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('When should it be planned again?'), findsOneWidget);
    // The block is tomorrow, so the choices are about that day.
    for (final choice in ['Later that day', 'The day after', 'A week later']) {
      expect(find.text(choice).hitTestable(), findsOneWidget, reason: choice);
    }
    expect(find.text('Later today'), findsNothing);
    await tester.tap(find.text('The day after'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(account.settings.skips, {'a': DateTime(now.year, now.month, now.day + 2)});
    expect(account.blocks, isEmpty);
    expect(find.textContaining('Not planned before:'), findsOneWidget);
    expect(find.text('This block is no longer planned.'), findsOneWidget);
  });

  testWidgets('a block is dragged in the day view and locked where it lands', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'Write report', auto: true, minutes: 60)],
      events: [block('a:1', 'a', 'Write report', 12, days: 1)],
    )..calendars = [
      ZtCalendarInfo.personal,
      const ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
    ];
    final before = account.blocks.single;
    await tester.pumpWidget(account.app(const HomePage()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(HomePage)));
    container.read(focusedDayProvider.notifier).set(before.start);
    await container
        .read(calendarSettingsProvider.notifier)
        .update((s) => s.copyWith(view: CalendarView.day));
    await tester.pumpAndSettle();
    final title = find.text('Write report');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(title));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = account.blocks.single;
    expect(after.start.isAfter(before.start), isTrue, reason: 'the block did not move');
    expect(after.start.minute % 15, 0);
    expect(after.duration, before.duration);
    expect(PlanMark.of(after)!.locked, isTrue);
    expect(find.textContaining('and locked there'), findsOneWidget);
    // The lock shows on the block.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(account.blocks.single.start, before.start);
    expect(PlanMark.of(account.blocks.single)!.locked, isFalse);
  });

  testWidgets('tasks that do not fit show in a banner on the calendar, with fixes', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final soon = DateTime.now().add(const Duration(hours: 2));
    final account = FakeAccount(
      settings: on,
      tasks: [
        PlannerTask(
          id: 'a',
          title: 'Tax papers',
          minutes: 480,
          auto: true,
          due: soon,
          dueHasTime: true,
          createdAt: 'a',
        ),
        task('b', 'Read contract', auto: true, minutes: 30),
      ],
    )..calendars = [
      ZtCalendarInfo.personal,
      const ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
    ];
    await tester.pumpWidget(account.app(const HomePage()));
    // The Planner plans a moment after the calendar opens.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(account.blocks, isNotEmpty);

    final banner = find.byType(PlannerRiskBanner);
    final text = find.text('1 task is at risk');
    expect(text, findsOneWidget);
    final rect = tester.getRect(banner);
    final screen = screenOf(tester);
    // Across the top, right under the app bar, above the calendar.
    expect(rect.left, 0);
    expect(rect.width, screen.width);
    expect(rect.top, tester.getRect(find.byType(AppBar)).bottom);
    expect(rect.height, inInclusiveRange(36, 64));
    expect(rect.bottom, lessThanOrEqualTo(tester.getRect(find.byType(MonthView)).top));
    expect(text.hitTestable(), findsOneWidget);

    await tester.tap(text);
    await tester.pumpAndSettle();
    expect(find.text('Tasks at risk'), findsOneWidget);
    final tile = find.byKey(const ValueKey('planner-risk-a'));
    expect(tile.hitTestable(), findsOneWidget);
    expect(screen.contains(tester.getRect(tile).center), isTrue);
    expect(find.descendant(of: tile, matching: find.text('Tax papers')), findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.textContaining('planned after the due date')),
      findsOneWidget,
    );
    // The task that fits is not listed.
    expect(find.byKey(const ValueKey('planner-risk-b')), findsNothing);
    expectTappableOnScreen(tester, 'Open the Planner');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    for (final fix in [
      'Change the length',
      'Move the due date',
      'Stop planning this task',
      'Open ZT Tasks',
    ]) {
      expect(find.text(fix).hitTestable(), findsOneWidget, reason: fix);
    }
    expect(find.text('Now 8 hours'), findsOneWidget);
    await tester.tap(find.text('Stop planning this task'));
    await tester.pumpAndSettle();
    expect(account.log, contains('task a {planAuto: false}'));
    // The Planner plans again without it: nothing is at risk any more.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Every task fits now.'), findsOneWidget);
    expect(find.text('1 task is at risk'), findsNothing);
    expect(tester.getSize(find.byType(PlannerRiskBanner)), Size.zero);
  });

  testWidgets('the block\'s actions read right to left in Hebrew', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'לכתוב דוח', auto: true, minutes: 60)],
      events: [block('a:1', 'a', 'לכתוב דוח', 12, days: 1)],
    );
    await tester.pumpWidget(blockView(account, locale: const Locale('he')));
    await tester.pumpAndSettle();
    final rows = expectRowsInOrder(tester, [
      'כבר בוצע',
      'המשימה הושלמה',
      'צריך עוד זמן',
      'לא עכשיו',
      'נעילה כאן',
      'העברה',
    ]);
    expect(rows, hasLength(6));
    // Right to left: each row's icon is to the right of its label.
    final row = find.ancestor(of: find.text('לא עכשיו'), matching: find.byType(ListTile));
    final icon = find.descendant(of: row, matching: find.byIcon(Icons.snooze));
    expect(tester.getCenter(icon).dx, greaterThan(tester.getTopRight(find.text('לא עכשיו')).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ordinary event can be marked as done, and shows crossed out', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final now = DateTime.now();
    final lunch = CalendarEvent(
      id: 'lunch',
      title: 'Lunch with Dana',
      start: DateTime(now.year, now.month, now.day, 12),
      end: DateTime(now.year, now.month, now.day, 13),
    );
    final account = FakeAccount(events: [lunch]);
    await tester.pumpWidget(account.app(const EventDetailsPage(eventId: 'lunch')));
    await tester.pumpAndSettle();
    final tick = find.byTooltip('Mark as done');
    expect(tick.hitTestable(), findsOneWidget);
    // In the app bar, before Edit and Delete.
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.contains(tester.getCenter(tick)), isTrue);
    expect(tester.getCenter(tick).dx, lessThan(tester.getCenter(find.byTooltip('Edit')).dx));
    TextDecoration? decoration() => tester
        .widget<SelectableText>(find.widgetWithText(SelectableText, 'Lunch with Dana'))
        .style!
        .decoration;
    expect(decoration(), isNot(TextDecoration.lineThrough));

    // Marked as done (as it is once the tick is saved).
    account.events = [withEventDone(lunch, lunch.start, true)];
    account.emit();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mark as not done').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Mark as done'), findsNothing);
    expect(decoration(), TextDecoration.lineThrough);
  });

  testWidgets('the Planner reads right to left in Hebrew', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: on,
      tasks: [task('a', 'לכתוב דוח', auto: true, minutes: 60)],
      events: [block('a:1', 'a', 'לכתוב דוח', 12)],
    );
    await tester.pumpWidget(account.app(const PlannerPage(), locale: const Locale('he')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final screen = screenOf(tester);
    expect(find.text('מתכנן'), findsOneWidget);
    expect(find.text('משימות לתכנון'), findsOneWidget);
    final tile = find.byKey(const ValueKey('planner-task-a'));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    // Right to left: the switch is on the left, the title to its right.
    expect(tester.getCenter(toggle).dx, lessThan(screen.width * 0.25));
    expect(
      tester.getTopRight(find.descendant(of: tile, matching: find.text('לכתוב דוח'))).dx,
      greaterThan(tester.getTopRight(toggle).dx),
    );
    expect(find.textContaining('שעה'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Planned calendar cannot be deleted while the Planner is on', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on)
      ..calendars = [
        ZtCalendarInfo.personal,
        const ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
        const ZtCalendarInfo(id: 'work', name: 'Work', color: 0xFF3B82F6),
      ];
    await tester.pumpWidget(account.app(const CalendarsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planned'));
    await tester.pumpAndSettle();
    expect(find.text('Edit calendar'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Any other calendar still can be.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
  });
}
