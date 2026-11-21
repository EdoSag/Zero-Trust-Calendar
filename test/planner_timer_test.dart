import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/find_a_time.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_actions.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/planner/planner_plan.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'planner_actions_test.dart' show block, minuteOf, on, start, task;
import 'planner_support.dart';

const calendars = [
  ZtCalendarInfo.personal,
  ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
];

void main() {
  final now = minuteOf(DateTime.now());
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);

  group('Planned blocks count as busy', () {
    test('the switch is written only when on, and moves no block', () {
      const off = PlannerSettings(enabled: true);
      final busy = off.copyWith(blocksBusy: true);
      expect(off.toJson().containsKey('blocksBusy'), isFalse);
      expect(busy.toJson()['blocksBusy'], isTrue);
      expect(PlannerSettings.fromJson(busy.toJson()).blocksBusy, isTrue);
      // Settings from before the switch read as off.
      expect(PlannerSettings.fromJson(off.toJson()).blocksBusy, isFalse);
      expect(busy.planSignature, off.planSignature);
      // Not mistaken for a key of a newer version.
      expect(PlannerSettings.fromJson(busy.toJson()).extra, isEmpty);
    });

    test('off: only locked and done blocks keep others away. On: every block does', () {
      final movable = block('a:1', 'a', tomorrow);
      final locked = block('b:1', 'b', tomorrow.add(const Duration(hours: 2)), locked: true);
      final done = block('c:1', 'c', tomorrow.add(const Duration(hours: 4)), done: true);
      final skippedHabit = CalendarEvent(
        id: 'h:1',
        title: 'Walk',
        start: tomorrow.add(const Duration(hours: 6)),
        end: tomorrow.add(const Duration(hours: 7)),
        calendarId: plannerCalendarId,
        extra: {
          'plan': {'type': 'habit', 'habitId': 'h', 'done': true, 'skipped': true},
        },
      );
      final events = [movable, locked, done, skippedHabit];
      (DateTime, DateTime) span(CalendarEvent e) => (e.start, e.end);

      expect(
        busyBlocks(events: events, calendars: calendars, from: today),
        [span(locked), span(done)],
      );
      expect(
        busyBlocks(events: events, calendars: calendars, from: today, plannedBusy: true),
        // A habit skipped for the day is only a record: still free.
        [span(movable), span(locked), span(done)],
      );
    });
  });

  group('Start now', () {
    test('moves a block still to come to now, locks it, and the Planner leaves it', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', tomorrow, minutes: 120)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);

      final started = await actions.start(account.blocks.single, now: now);
      await pumpEventQueue();
      final mark = PlanMark.of(started)!;
      expect(started.start, now);
      expect(started.end, now.add(const Duration(minutes: 120)), reason: 'its length is kept');
      expect(mark.locked, isTrue);
      expect(mark.started, now);
      expect(mark.runningAt(now.add(const Duration(minutes: 30))), isTrue);
      expect(actions.running(now: now)!.id, 'a:1');

      account.log.clear();
      await container.read(plannerControllerProvider.notifier).runNow();
      expect(account.blocks.single.start, now);
      expect(account.log, isEmpty, reason: 'the Planner changed a block being timed');
    });

    test('a block already under way keeps its end', () async {
      final began = now.subtract(const Duration(minutes: 10));
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', began)],
      );
      final container = await start(account);
      final started = await container
          .read(plannerActionsProvider)
          .start(account.blocks.single, now: now);
      expect(started.start, now);
      expect(started.end, began.add(const Duration(minutes: 60)));
    });

    test('only one block is timed: starting another stops the first', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120), task('b')],
        events: [
          block('a:1', 'a', tomorrow, minutes: 120),
          block('b:1', 'b', tomorrow.add(const Duration(hours: 3))),
        ],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      await actions.start(account.blocks.first, now: now);
      await pumpEventQueue();
      final later = now.add(const Duration(minutes: 25));
      await actions.start(account.blocks.firstWhere((b) => b.id == 'b:1'), now: later);
      await pumpEventQueue();

      final a = account.blocks.firstWhere((b) => b.id == 'a:1');
      expect(PlanMark.of(a)!.done, isTrue);
      expect((a.start, a.end), (now, later), reason: 'the first shows the 25 minutes worked');
      expect(actions.running(now: later)!.id, 'b:1');
    });

    test('on a task: its next block starts; a task with none gets one', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 90), task('b', minutes: 300)],
        events: [block('a:1', 'a', tomorrow, minutes: 90)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      PlannerTask byId(String id) => account.tasks.firstWhere((t) => t.id == id);

      final a = await actions.startTask(byId('a'), now: now);
      expect(a.id, 'a:1');
      expect(a.start, now);
      await pumpEventQueue();

      // No block yet for b: a new one, as long as the longest block.
      final b = await actions.startTask(byId('b'), now: now.add(const Duration(minutes: 5)));
      await pumpEventQueue();
      expect(b.id, isNot('a:1'));
      expect(PlanMark.of(b)!.itemId, 'b');
      expect(b.taskIds, ['b']);
      expect(b.calendarId, plannerCalendarId);
      expect(b.duration.inMinutes, on.maxChunk);
      expect(PlanMark.of(b)!.started, now.add(const Duration(minutes: 5)));
      expect(account.blocks.where((x) => x.id == b.id), hasLength(1));
    });

    test('a habit\'s block and a done block can\'t be started', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', now.subtract(const Duration(hours: 3)), done: true)],
      );
      final container = await start(account);
      await expectLater(
        container.read(plannerActionsProvider).start(account.blocks.single, now: now),
        throwsStateError,
      );
    });
  });

  group('Stop', () {
    test('the block shows the time really worked, is done, and the rest is planned again', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', tomorrow, minutes: 120)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      final began = now.subtract(const Duration(minutes: 45));
      await actions.start(account.blocks.single, now: began);
      await pumpEventQueue();

      final (block: stopped, :finished) = await actions.stop(account.blocks.single, now: now);
      await pumpEventQueue();
      expect((stopped.start, stopped.end), (began, now));
      final mark = PlanMark.of(stopped)!;
      expect(mark.done, isTrue);
      expect(mark.started, isNull);
      expect(mark.reason, PlanReason.done);
      expect(finished, isNull, reason: '75 minutes are left');
      expect(account.tasks.single.completed, isFalse);
      expect(actions.running(now: now), isNull);

      // The 75 minutes left are planned again.
      await container.read(plannerControllerProvider.notifier).runNow();
      final rest = account.blocks.where((b) => !PlanMark.of(b)!.done);
      expect(rest.fold(0, (sum, b) => sum + b.duration.inMinutes), 75);
      expect(planDoneMinutes(account.tasks.single, account.blocks), 45);
    });

    test('the last of the task\'s time ticks the task off, and undo opens it again', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 30)],
        events: [block('a:1', 'a', tomorrow, minutes: 30)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      final began = now.subtract(const Duration(minutes: 45));
      await actions.start(account.blocks.single, now: began);
      await pumpEventQueue();
      final timed = account.blocks.single;

      final (block: _, :finished) = await actions.stop(timed, now: now);
      await pumpEventQueue();
      expect(finished, 'a');
      expect(account.tasks.single.completed, isTrue);

      // Undo, as the screen does it: the timer runs on and the task is open.
      await actions.restore(timed);
      await actions.reopenTask(finished!);
      await pumpEventQueue();
      expect(PlanMark.of(account.blocks.single)!.runningAt(now), isTrue);
      expect(account.tasks.single.completed, isFalse);
    });

    test('stopped in the minute it started, the block is still a minute long', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      await actions.start(account.blocks.single, now: now);
      await pumpEventQueue();
      final (block: stopped, finished: _) = await actions.stop(account.blocks.single, now: now);
      expect(stopped.duration, const Duration(minutes: 1));
    });

    test('"Done" on a block being timed ends the timer too', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      await actions.start(account.blocks.single, now: now.subtract(const Duration(minutes: 20)));
      await pumpEventQueue();
      await actions.setDone(account.blocks.single, true, now: now);
      await pumpEventQueue();
      final mark = PlanMark.of(account.blocks.single)!;
      expect(mark.done, isTrue);
      expect(mark.started, isNull);
      expect(actions.running(now: now), isNull);
    });

    test('a block that isn\'t being timed can\'t be stopped', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      await expectLater(
        container.read(plannerActionsProvider).stop(account.blocks.single, now: now),
        throwsStateError,
      );
    });
  });

  group('Log time', () {
    test('adds a done block ending now, which counts toward the task', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', tomorrow, minutes: 120)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);

      final (block: logged, :finished) = await actions.logTime(account.tasks.single, 45, now: now);
      await pumpEventQueue();
      expect(finished, isNull);
      expect((logged.start, logged.end), (now.subtract(const Duration(minutes: 45)), now));
      expect(PlanMark.of(logged)!.done, isTrue);
      expect(logged.taskIds, ['a']);
      expect(planDoneMinutes(account.tasks.single, account.blocks), 45);

      // Less is left to plan: 75 minutes, not 120.
      await container.read(plannerControllerProvider.notifier).runNow();
      final rest = account.blocks.where((b) => !PlanMark.of(b)!.done);
      expect(rest.fold(0, (sum, b) => sum + b.duration.inMinutes), 75);
      // The logged block is history: the Planner keeps it as it is.
      final kept = account.blocks.firstWhere((b) => b.id == logged.id);
      expect((kept.start, kept.end), (logged.start, logged.end));

      // Undo removes it.
      await actions.remove(logged);
      await pumpEventQueue();
      expect(account.blocks.where((b) => b.id == logged.id), isEmpty);
    });

    test('the last of the task\'s time ticks the task off; twice in a minute makes two', () async {
      final account = FakeAccount(settings: on, tasks: [task('a', minutes: 60)]);
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      final (block: first, finished: none) = await actions.logTime(
        account.tasks.single,
        30,
        now: now,
      );
      await pumpEventQueue();
      expect(none, isNull);
      final (block: second, :finished) = await actions.logTime(account.tasks.single, 30, now: now);
      await pumpEventQueue();
      expect(second.id, isNot(first.id));
      expect(finished, 'a');
      expect(account.tasks.single.completed, isTrue);
    });

    test('no time is not logged', () async {
      final account = FakeAccount(settings: on, tasks: [task('a')]);
      final container = await start(account);
      await expectLater(
        container.read(plannerActionsProvider).logTime(account.tasks.single, 0, now: now),
        throwsArgumentError,
      );
    });
  });

  group('A block being timed and the plan', () {
    PlannerOutcome planAt(DateTime at, List<CalendarEvent> events, {PastBlocks? past}) =>
        computePlan(
          now: at,
          settings: past == null ? on : on.copyWith(pastBlocks: past),
          events: events,
          calendars: calendars,
          tasks: [task('a', minutes: 60)],
        );

    CalendarEvent timed(DateTime from, {int minutes = 30}) {
      final b = block('a:1', 'a', from, minutes: minutes, locked: true);
      return b.copyWith(
        extra: {'plan': PlanMark.of(b)!.copyWith(started: from).toJson()},
      );
    }

    test('past its planned end it is still in progress: kept, not asked about, not '
        'counted as done, also after midnight', () {
      // Started 23:30 for half an hour; it is 00:40 the next day.
      final from = DateTime(2026, 11, 23, 23, 30);
      final at = DateTime(2026, 11, 24, 0, 40);
      for (final past in PastBlocks.values) {
        final outcome = planAt(at, [timed(from)], past: past);
        expect(outcome.delete, isEmpty, reason: '$past');
        expect(outcome.save.where((b) => b.id == 'a:1'), isEmpty,
            reason: '$past: its stored times and mark stay until it is stopped');
        // The 70 minutes worked so far cover the task's hour: nothing more
        // is planned for it.
        expect(outcome.save, isEmpty, reason: '$past');
      }
    });

    test('left running for more than 12 hours, it is an ordinary passed block again', () {
      final from = DateTime(2026, 11, 23, 9);
      final mark = PlanMark.of(timed(from))!;
      expect(mark.runningAt(DateTime(2026, 11, 23, 20, 59)), isTrue);
      expect(mark.runningAt(DateTime(2026, 11, 23, 21)), isFalse);
      // The next day it is unanswered since an earlier day: planned again.
      final outcome = planAt(DateTime(2026, 11, 24, 10), [timed(from)]);
      expect(outcome.delete, ['a:1']);
    });

    test('the mark keeps what it doesn\'t know and clears only what it is told to', () {
      final b = block('a:1', 'a', tomorrow);
      final mark = PlanMark.of(
        b.copyWith(
          extra: {
            'plan': {...(b.extra['plan']! as Map), 'future': 7},
          },
        ),
      )!;
      final started = mark.copyWith(started: now);
      expect(started.started, now);
      expect(started.extra['future'], 7);
      // Other changes leave the timer alone.
      expect(started.copyWith(locked: true).started, now);
      final stopped = started.copyWith(started: null);
      expect(stopped.started, isNull);
      expect(stopped.toJson().containsKey('started'), isFalse);
      expect(stopped.extra['future'], 7);
      // A mark from before timing reads as not running.
      expect(mark.started, isNull);
      expect(mark.runningAt(now), isFalse);
    });
  });
}
