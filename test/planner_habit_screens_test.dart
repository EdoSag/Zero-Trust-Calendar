import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/ui/planner_block_sheet.dart';
import 'package:zerotrust_calendar/ui/planner_habit_page.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';

import 'planner_support.dart';

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Rect screenOf(WidgetTester tester) =>
    Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

/// The rows showing [labels] are on screen, can be tapped, and come one
/// under the other in that order.
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

final gym = PlannerHabit(
  id: 'gym',
  title: 'Gym',
  minutes: 60,
  days: const {1, 3, 5},
  ideal: 18 * 60,
  earliest: 6 * 60,
  latest: 22 * 60,
);

final on = PlannerSettings(enabled: true, hours: everyDay, habits: [gym]);

/// A habit block tomorrow (or [days] from today) from [hour] for an hour.
CalendarEvent habitBlock(String id, String habitId, String title, int hour, {int days = 1}) {
  final now = DateTime.now();
  return CalendarEvent(
    id: id,
    title: title,
    start: DateTime(now.year, now.month, now.day + days, hour),
    end: DateTime(now.year, now.month, now.day + days, hour + 1),
    calendarId: plannerCalendarId,
    extra: {
      'plan': {'type': 'habit', 'habitId': habitId, 'locked': false, 'done': false},
    },
  );
}

/// Opens [page] over a home screen, as the app does.
Future<void> openPage(WidgetTester tester, FakeAccount account, Widget page, {Locale? locale}) async {
  await tester.pumpWidget(account.app(const Scaffold(body: Text('home')), locale: locale));
  await tester.pumpAndSettle();
  tester.state<NavigatorState>(find.byType(Navigator)).push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  await tester.pumpAndSettle();
}

Widget blockView(FakeAccount account, String id, {Locale? locale}) => account.app(
  Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: PlannerBlockView(blockId: id),
    ),
  ),
  locale: locale,
);

void main() {
  testWidgets('the Planner lists habits and focus time above its settings, '
      'and a lunch habit is added from the ready-made ones', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on);
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final header = find.text('Habits');
    await tester.scrollUntilVisible(header, 200);
    // The section at the top of the screen.
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    final gymTile = find.byKey(const ValueKey('planner-habit-gym'));
    final focus = find.byKey(const ValueKey('planner-focus'));
    final add = find.byKey(const ValueKey('planner-add-habit'));
    expect(gymTile, findsOneWidget);
    expect(find.descendant(of: gymTile, matching: find.text('Gym')), findsOneWidget);
    expect(
      find.descendant(of: gymTile, matching: find.textContaining('1 hour · around')),
      findsOneWidget,
    );
    // Header, the habit, focus time, then the add button, one under the other.
    expect(tester.getTopLeft(gymTile).dy, greaterThanOrEqualTo(tester.getBottomLeft(header).dy));
    expect(tester.getTopLeft(focus).dy, greaterThanOrEqualTo(tester.getBottomLeft(gymTile).dy));
    expect(tester.getTopLeft(add).dy, greaterThanOrEqualTo(tester.getBottomLeft(focus).dy));
    expect(screenOf(tester).contains(tester.getCenter(add)), isTrue);
    expect(find.descendant(of: focus, matching: find.textContaining('Off')), findsOneWidget);
    // Above the settings.
    await tester.scrollUntilVisible(find.text('Work hours'), 300);
    expect(tester.getTopLeft(find.text('Work hours')).dy, greaterThan(tester.getBottomLeft(add).dy));

    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Something else'), findsOneWidget);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    expect(find.byType(PlannerHabitPage), findsOneWidget);
    expect(find.text('Add a habit'), findsOneWidget);
    // The form, top to bottom, and Save at the bottom of the screen.
    final rows = [
      find.byKey(const ValueKey('habit-title')),
      find.byKey(const ValueKey('habit-days')),
      find.byKey(const ValueKey('habit-length')),
      find.byKey(const ValueKey('habit-ideal')),
      find.byKey(const ValueKey('habit-window')),
      find.byKey(const ValueKey('habit-no-room')),
    ];
    for (var i = 1; i < rows.length; i++) {
      expect(tester.getTopLeft(rows[i]).dy, greaterThanOrEqualTo(tester.getBottomLeft(rows[i - 1]).dy));
    }
    final save = find.byKey(const ValueKey('habit-save'));
    expect(tester.getBottomLeft(save).dy, greaterThan(screenOf(tester).height * 0.85));
    expect(tester.getSize(save).width, greaterThan(200));
    expect(
      find.descendant(of: find.byKey(const ValueKey('habit-length')), matching: find.text('30 minutes')),
      findsOneWidget,
    );
    expect(find.text('Shorten it, down to 15 minutes'), findsOneWidget);

    // No days: nothing to save.
    for (var d = 1; d <= 7; d++) {
      await tester.tap(find.byKey(ValueKey('habit-day-$d')));
    }
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('habit-day-2')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(PlannerHabitPage), findsNothing);
    final saved = account.settings.habits;
    expect(saved.map((h) => h.title), ['Gym', 'Lunch']);
    expect(saved.last.days, {2});
    expect(saved.last.minMinutes, 15);
    // And the Planner lists it, after Gym and above focus time.
    final lunchTile = find.byKey(ValueKey('planner-habit-${saved.last.id}'));
    await tester.scrollUntilVisible(gymTile, -100);
    await tester.ensureVisible(gymTile);
    await tester.pumpAndSettle();
    expect(find.descendant(of: lunchTile, matching: find.text('Lunch')), findsOneWidget);
    expect(tester.getTopLeft(lunchTile).dy, greaterThanOrEqualTo(tester.getBottomLeft(gymTile).dy));
    expect(tester.getTopLeft(focus).dy, greaterThanOrEqualTo(tester.getBottomLeft(lunchTile).dy));
  });

  testWidgets('a habit is edited, paused and deleted', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on);
    await openPage(tester, account, PlannerHabitPage(habit: gym));
    expect(find.text('Edit habit'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('habit-title')), 'Swim');
    await tester.tap(find.byKey(const ValueKey('habit-paused')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit-save')));
    await tester.pumpAndSettle();
    expect(account.settings.habits.single.title, 'Swim');
    expect(account.settings.habits.single.paused, isTrue);
    expect(account.settings.habits.single.days, {1, 3, 5});

    await openPage(tester, account, PlannerHabitPage(habit: account.settings.habits.single));
    await tester.tap(find.byKey(const ValueKey('habit-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this habit?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(account.settings.habits, isEmpty);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the focus time goal is picked on the Planner and plans focus blocks', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on.copyWith(habits: const []));
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('planner-focus'));
    await tester.scrollUntilVisible(focus, 300);
    await tester.pumpAndSettle();
    await tester.tap(focus);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 hours').last);
    await tester.pumpAndSettle();
    expect(account.settings.focusMinutesPerWeek, 600);
    expect(account.settings.focusTitle, 'Focus time');
    expect(
      find.descendant(of: focus, matching: find.text('10 hours a week, in work hours')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final focusBlocks = [
      for (final b in account.blocks)
        if (PlanMark.of(b)!.itemId == PlannerHabit.focusId) b,
    ];
    expect(focusBlocks, isNotEmpty);
    expect(focusBlocks.first.title, 'Focus time');
    // Seven work days a week here: 10 hours over 7 days, rounded up. Today's
    // block may be shortened when the day is almost over, so look at a later
    // day's.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final later = focusBlocks.firstWhere((b) => !b.start.isBefore(tomorrow));
    expect(later.duration.inMinutes, 90);
  });

  testWidgets('a habit block offers Done, Skip today, Lock, Move and Edit habit, '
      'never "Open ZT Tasks", and skipping is undone', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on, events: [habitBlock('g:1', 'gym', 'Gym', 18)]);
    await tester.pumpWidget(blockView(account, 'g:1'));
    await tester.pumpAndSettle();
    expectRowsInOrder(tester, ['Already done', 'Skip today', 'Lock here', 'Move', 'Edit habit']);
    expect(find.text('Open ZT Tasks'), findsNothing);
    expect(find.text('Need more time'), findsNothing);
    expect(find.text('Not now'), findsNothing);

    await tester.tap(find.text('Skip today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final mark = PlanMark.of(account.blocks.single)!;
    expect(mark.done, isTrue);
    expect(mark.skipped, isTrue);
    expect(find.text('Skipped'), findsWidgets);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(PlanMark.of(account.blocks.single)!.done, isFalse);
    expect(PlanMark.of(account.blocks.single)!.skipped, isFalse);
  });

  testWidgets('a skipped habit can be kept after all', (tester) async {
    usePhoneScreen(tester);
    final skipped = habitBlock('g:1', 'gym', 'Gym', 18, days: 0);
    final account = FakeAccount(
      settings: on,
      events: [
        skipped.copyWith(
          extra: {
            'plan': {'type': 'habit', 'habitId': 'gym', 'locked': false, 'done': true, 'skipped': true},
          },
        ),
      ],
    );
    await tester.pumpWidget(blockView(account, 'g:1'));
    await tester.pumpAndSettle();
    expectRowsInOrder(tester, ['Did it after all', 'Edit habit']);
    await tester.tap(find.text('Did it after all'));
    await tester.pumpAndSettle();
    final mark = PlanMark.of(account.blocks.single)!;
    expect(mark.done, isTrue);
    expect(mark.skipped, isFalse);
  });

  testWidgets('the habit editor and a habit block read right to left in Hebrew', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(settings: on, events: [habitBlock('g:1', 'gym', 'כושר', 18)]);
    await tester.pumpWidget(blockView(account, 'g:1', locale: const Locale('he')));
    await tester.pumpAndSettle();
    expectRowsInOrder(tester, ['כבר בוצע', 'דילוג היום', 'נעילה כאן', 'העברה', 'עריכת הרגל']);
    final row = find.ancestor(of: find.text('דילוג היום'), matching: find.byType(ListTile));
    final icon = find.descendant(of: row, matching: find.byIcon(Icons.event_busy));
    expect(tester.getCenter(icon).dx, greaterThan(tester.getTopRight(find.text('דילוג היום')).dx));

    await openPage(tester, account, PlannerHabitPage(habit: gym), locale: const Locale('he'));
    expect(find.text('עריכת הרגל'), findsOneWidget);
    final length = find.byKey(const ValueKey('habit-length'));
    final label = find.descendant(of: length, matching: find.text('אורך'));
    final value = find.descendant(of: length, matching: find.text('שעה'));
    expect(value, findsOneWidget);
    // Label on the right, value on the left.
    expect(tester.getCenter(label).dx, greaterThan(tester.getCenter(value).dx));
    expect(tester.takeException(), isNull);
  });
}
