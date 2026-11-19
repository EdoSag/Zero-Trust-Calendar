import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/data/shared_calendars.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_access.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/planner/task_time_finder.dart';
import 'package:zerotrust_calendar/ui/find_task_time_page.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';

import 'planner_support.dart';

/// Monday 23 November 2026, 8:00.
final mondayMorning = DateTime(2026, 11, 23, 8);
DateTime mon(int h, [int m = 0]) => DateTime(2026, 11, 23, h, m);
DateTime tue(int h, [int m = 0]) => DateTime(2026, 11, 24, h, m);

/// Work Monday to Friday 9:00 to 17:00, the Planner off.
final workWeek = PlannerSettings(hours: PlannerSettings.defaultHours(DateTime.monday));

CalendarEvent meeting(String id, DateTime start, DateTime end, {String calendarId = 'default'}) =>
    CalendarEvent(id: id, title: id, start: start, end: end, calendarId: calendarId);

const calendars = [ZtCalendarInfo.personal];

/// Every hour of every day, so the screen tests don't depend on when they run.
final allDayHours = {
  workHoursId: {
    for (var d = 1; d <= 7; d++) d: const [(0, 1440)],
  },
};

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Rect screenOf(WidgetTester tester) =>
    Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

void main() {
  group('which plans include the Planner', () {
    test('Plus with the feature, Unlimited (every feature), not free, unknown when locked', () {
      expect(plannerAllowedFor(null), isNull);
      expect(plannerAllowedFor(ZtPlan.free), isFalse);
      expect(plannerAllowedFor(const ZtPlan(id: 'plus')), isFalse,
          reason: 'until the SQL adds the feature to Plus');
      expect(plannerAllowedFor(const ZtPlan(id: 'plus', features: {'planner'})), isTrue);
      expect(plannerAllowedFor(const ZtPlan(id: 'unlimited', features: {'*'})), isTrue);
    });
  });

  group('find a time for a task', () {
    test('suggests the earliest free time on each day, in work hours, soonest first', () {
      final times = findTaskTimes(
        now: mondayMorning,
        minutes: 60,
        settings: workWeek,
        hoursId: workHoursId,
        events: [meeting('standup', mon(9), mon(9, 30))],
        calendars: calendars,
        count: 3,
      );
      // After the meeting and its 10-minute break, on the 15-minute grid.
      expect(times, [
        (mon(9, 45), mon(10, 45)),
        (tue(9), tue(10)),
        (DateTime(2026, 11, 25, 9), DateTime(2026, 11, 25, 10)),
      ]);
    });

    test('starts at least 30 minutes from now and skips days with no room', () {
      final times = findTaskTimes(
        now: mon(16, 10),
        minutes: 30,
        settings: workWeek,
        hoursId: workHoursId,
        events: [meeting('all day tue', tue(9), tue(17))],
        calendars: calendars,
        count: 2,
      );
      // Monday: 16:45 is the first start 30 minutes away, and it would end
      // after work. Tuesday is full.
      expect(times, [
        (DateTime(2026, 11, 25, 9), DateTime(2026, 11, 25, 9, 30)),
        (DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 9, 30)),
      ]);
    });

    test('the Planner\'s blocks still to come are busy, done ones and free calendars are not', () {
      final block = CalendarEvent(
        id: 'p',
        title: 'p',
        start: mon(9),
        end: mon(11),
        calendarId: plannerCalendarId,
        extra: {
          'plan': {'type': 'task', 'taskId': 'x', 'locked': false, 'done': false},
        },
      );
      final done = block.copyWith(
        id: 'q',
        start: tue(9),
        end: tue(11),
        extra: {
          'plan': {'type': 'task', 'taskId': 'x', 'locked': false, 'done': true},
        },
      );
      final times = findTaskTimes(
        now: mondayMorning,
        minutes: 60,
        settings: workWeek.copyWith(freeCalendarIds: {'gym'}),
        hoursId: workHoursId,
        events: [block, done, meeting('gym', mon(11), mon(12), calendarId: 'gym')],
        calendars: calendars,
        count: 2,
      );
      expect(times, [(mon(11), mon(12)), (tue(9), tue(10))]);
    });

    test('"Any time" searches 8:00 to 22:00 every day', () {
      final times = findTaskTimes(
        now: DateTime(2026, 11, 28, 6), // Saturday
        minutes: 60,
        settings: workWeek,
        hoursId: null,
        events: const [],
        calendars: calendars,
        count: 1,
      );
      expect(times.single.$1, DateTime(2026, 11, 28, 8));
    });
  });

  group('the Planner without Plus', () {
    Future<ProviderContainer> start(FakeAccount account) async {
      final container = ProviderContainer(overrides: account.overrides);
      addTearDown(container.dispose);
      container.listen(plannerControllerProvider, (_, _) {});
      await container.read(eventsProvider.future);
      await container.read(calendarsProvider.future);
      await container.read(plannerSettingsProvider.future);
      await container.read(plannerTasksProvider.future);
      await pumpEventQueue();
      return container;
    }

    final on = PlannerSettings(enabled: true, hours: allDayHours, tasks: PlannerTasksChoice.all);
    PlannerTask task(String id) =>
        PlannerTask(id: id, title: 'Task $id', minutes: 60, createdAt: id);

    test('is paused when the plan lacks it, keeps its blocks, and plans once it has it', () async {
      final account = FakeAccount(settings: on, tasks: [task('a')])..plannerAllowed = true;
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      await planner.runNow();
      expect(account.blocks, hasLength(1));

      // Plus ended: nothing is written, the block stays.
      account.plannerAllowed = false;
      container.invalidate(plannerAllowedProvider);
      account.log.clear();
      account.tasks = [task('a'), task('b')];
      account.emit();
      await pumpEventQueue();
      await planner.runNow();
      expect(account.log, isEmpty);
      expect(account.blocks, hasLength(1));
      expect(container.read(plannerControllerProvider).waiting, PlannerWaiting.needsPlus);

      // Not known (offline): it plans as before.
      account.plannerAllowed = null;
      container.invalidate(plannerAllowedProvider);
      await planner.runNow();
      expect(account.blocks, hasLength(2));
      expect(container.read(plannerControllerProvider).waiting, isNull);
    });
  });

  testWidgets('on the free plan the Planner offers Find a time and explains Plus, '
      'with no setup', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount()..plannerAllowed = false;
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pumpAndSettle();
    expect(find.text('Set up the Planner'), findsNothing);
    final card = find.byKey(const ValueKey('planner-plus'));
    await tester.scrollUntilVisible(card, 200);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(find.text('The automatic Planner is part of Plus'), findsOneWidget);
    final button = find.byKey(const ValueKey('planner-find-time'));
    expect(find.descendant(of: card, matching: button), findsOneWidget);
    expect(screenOf(tester).contains(tester.getCenter(button)), isTrue);
    // The button spans the card, under its text.
    expect(tester.getSize(button).width, greaterThan(tester.getSize(card).width * 0.8));
    expect(
      tester.getTopLeft(button).dy,
      greaterThan(tester.getBottomLeft(find.textContaining('Plus isn\'t on sale yet')).dy),
    );
  });

  testWidgets('with Plus the setup comes first and Find a time is under it', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount();
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pumpAndSettle();
    final setup = find.text('Set up the Planner');
    final findTime = find.byKey(const ValueKey('planner-find-time'));
    await tester.scrollUntilVisible(findTime, 200);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-plus')), findsNothing);
    expect(tester.getTopLeft(findTime).dy, greaterThan(tester.getBottomLeft(setup).dy));
  });

  testWidgets('a Planner that was on shows that it is paused, above the week', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: PlannerSettings(enabled: true, hours: allDayHours),
    )..plannerAllowed = false;
    await tester.pumpWidget(account.app(const PlannerPage()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('planner-plus'));
    expect(card, findsOneWidget);
    expect(find.text('The Planner is paused'), findsOneWidget);
    expect(
      tester.getBottomLeft(card).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Next 7 days')).dy),
    );
    expect(account.log, isEmpty);
  });

  testWidgets('Find a time: pick a task, pick a time, and it is added linked to the task', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final saved = <CalendarEvent>[];
    final account = FakeAccount(
      settings: workWeek,
      tasks: [
        PlannerTask(id: 'b', title: 'Clean garage', createdAt: 'b'),
        PlannerTask(id: 'a', title: 'Write report', minutes: 90, due: tue(0), createdAt: 'a'),
        PlannerTask(id: 'c', title: 'Done already', completed: true, createdAt: 'c'),
      ],
      events: [meeting('standup', mon(9), mon(9, 30))],
    )..plannerAllowed = false;
    await tester.pumpWidget(
      account.app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => FindTaskTimePage(now: mondayMorning)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        more: [findTimeEventSaverProvider.overrideWithValue((e) async => saved.add(e))],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Open tasks only, the one with a due date first.
    expect(find.text('Done already'), findsNothing);
    final report = find.byKey(const ValueKey('find-time-task-a'));
    final garage = find.byKey(const ValueKey('find-time-task-b'));
    expect(tester.getTopLeft(garage).dy, greaterThanOrEqualTo(tester.getBottomLeft(report).dy));
    await tester.tap(report);
    await tester.pumpAndSettle();

    // Its own length, the first time after the meeting.
    expect(
      find.descendant(of: find.byKey(const ValueKey('find-time-length')), matching: find.text('1 h 30 min')),
      findsOneWidget,
    );
    final first = find.byKey(const ValueKey('find-time-slot-0'));
    expect(find.descendant(of: first, matching: find.textContaining('9:45')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('find-time-slot-1'))).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(first).dy),
    );
    expect(screenOf(tester).contains(tester.getCenter(first)), isTrue);

    await tester.tap(first);
    await tester.pumpAndSettle();
    final event = saved.single;
    expect(event.title, 'Write report');
    expect(event.taskIds, ['a']);
    expect(event.start, mon(9, 45));
    expect(event.end, mon(11, 15));
    expect(event.calendarId, CalendarEvent.defaultCalendarId);
    expect(PlanMark.of(event), isNull, reason: 'an ordinary event: nothing moves it');
    expect(find.text('open'), findsOneWidget);
    expect(find.textContaining('Added to your calendar'), findsOneWidget);
  });

  testWidgets('Find a time waits for shared calendars before offering times', (tester) async {
    usePhoneScreen(tester);
    final loading = Completer<List<SharedCalendar>>();
    final account = FakeAccount(
      settings: workWeek,
      tasks: [PlannerTask(id: 'a', title: 'Write report', minutes: 60, createdAt: 'a')],
    )..sharedCalendars = loading;
    await tester.pumpWidget(account.app(FindTaskTimePage(now: mondayMorning)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('find-time-task-a')));
    await tester.pump();
    expect(find.byKey(const ValueKey('find-time-slot-0')), findsNothing);
    final spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);
    // Where the times will be: under their heading.
    expect(
      tester.getTopLeft(spinner).dy,
      greaterThan(tester.getBottomLeft(find.text('Free times')).dy),
    );
    loading.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-time-slot-0')), findsOneWidget);
  });

  testWidgets('Find a time reads right to left in Hebrew', (tester) async {
    usePhoneScreen(tester);
    final account = FakeAccount(
      settings: workWeek,
      tasks: [PlannerTask(id: 'a', title: 'לכתוב דוח', minutes: 60, createdAt: 'a')],
    );
    await tester.pumpWidget(account.app(FindTaskTimePage(now: mondayMorning), locale: const Locale('he')));
    await tester.pumpAndSettle();
    expect(find.text('איזו משימה?'), findsOneWidget);
    final row = find.byKey(const ValueKey('find-time-task-a'));
    // The title on the right of its arrow.
    expect(
      tester.getCenter(find.descendant(of: row, matching: find.text('לכתוב דוח'))).dx,
      greaterThan(tester.getCenter(find.descendant(of: row, matching: find.byIcon(Icons.chevron_right))).dx),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('זמנים פנויים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
