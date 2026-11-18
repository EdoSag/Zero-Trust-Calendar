import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/ui/calendars_page.dart';
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
    expectTappableOnScreen(tester, 'Task finished');
    expectTappableOnScreen(tester, 'Open ZT Tasks');
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Task finished')).bottom,
      lessThanOrEqualTo(tester.getRect(find.widgetWithText(FilledButton, 'Open ZT Tasks')).top),
    );
    expect(find.text('Edit'), findsNothing);
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
