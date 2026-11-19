import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_actions.dart';
import 'package:zerotrust_calendar/planner/planner_answers.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'planner_support.dart';

/// Every hour of every day, so the tests don't depend on when they run.
final allDayHours = {
  workHoursId: {
    for (var d = 1; d <= 7; d++) d: const [(0, 1440)],
  },
};

final on = PlannerSettings(
  enabled: true,
  hours: allDayHours,
  tasks: PlannerTasksChoice.all,
);

PlannerTask task(String id, {int minutes = 60, bool repeats = false}) => PlannerTask(
  id: id,
  title: 'Task $id',
  minutes: minutes,
  repeats: repeats,
  dueRaw: repeats ? '2026-11-20T00:00:00.000' : null,
  createdAt: id,
);

/// A stored block of [taskId] from [start] for [minutes].
CalendarEvent block(
  String id,
  String taskId,
  DateTime start, {
  int minutes = 60,
  bool done = false,
  bool locked = false,
  String? occurrence,
}) => CalendarEvent(
  id: id,
  title: 'Task $taskId',
  start: start,
  end: start.add(Duration(minutes: minutes)),
  calendarId: plannerCalendarId,
  taskIds: [taskId],
  reminders: const [0],
  extra: {
    'plan': {
      'type': 'task',
      'taskId': taskId,
      'locked': locked,
      'done': done,
      'occurrence': ?occurrence,
    },
  },
);

/// A container on [account] with every stream loaded. The Planner's
/// controller runs only when a test asks it to.
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

/// The minute [now] is in.
DateTime minuteOf(DateTime now) =>
    DateTime(now.year, now.month, now.day, now.hour, now.minute);

void main() {
  // A block that started ten minutes ago, and one that is still to come.
  final now = minuteOf(DateTime.now());
  final running = now.subtract(const Duration(minutes: 10));
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);

  group('Done', () {
    test('the last part of a task ticks the task off in ZT Tasks', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', running)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);

      final finished = await actions.setDone(account.blocks.single, true);
      await pumpEventQueue();
      expect(finished, 'a');
      final mark = PlanMark.of(account.blocks.single)!;
      expect(mark.done, isTrue);
      expect(mark.reason, PlanReason.done);
      // The block stays where it was: it is history now.
      expect(account.blocks.single.start, running);
      expect(account.log, ['save a:1', 'complete a true']);
      expect(account.tasks.single.completed, isTrue);

      // Undo, as the screen does it: the block as it was, the task open.
      await actions.restore(block('a:1', 'a', running));
      await actions.reopenTask('a');
      await pumpEventQueue();
      expect(PlanMark.of(account.blocks.single)!.done, isFalse);
      expect(account.tasks.single.completed, isFalse);
    });

    test('one part of several leaves the task open', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', running), block('a:2', 'a', tomorrow)],
      );
      final container = await start(account);
      final finished = await container
          .read(plannerActionsProvider)
          .setDone(account.blocks.first, true);
      await pumpEventQueue();
      expect(finished, isNull);
      expect(account.log, ['save a:1']);
      expect(PlanMark.of(account.blocks.first)!.done, isTrue);
      expect(PlanMark.of(account.blocks.last)!.done, isFalse);
      expect(account.tasks.single.completed, isFalse);

      // The second part, done later, is the last one.
      final last = await container
          .read(plannerActionsProvider)
          .setDone(account.blocks.last, true, now: tomorrow.add(const Duration(hours: 1)));
      expect(last, 'a');
    });

    test('a repeating task is never ticked off from Calendar', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', repeats: true)],
        events: [block('a:1', 'a', running, occurrence: '2026-11-20T00:00:00.000')],
      );
      final container = await start(account);
      final finished = await container
          .read(plannerActionsProvider)
          .setDone(account.blocks.single, true);
      await pumpEventQueue();
      expect(finished, isNull);
      expect(account.log, ['save a:1']);
      expect(PlanMark.of(account.blocks.single)!.done, isTrue);
      expect(PlanMark.of(account.blocks.single)!.occurrence, '2026-11-20T00:00:00.000');
    });

    test('"Already done" on a block still to come moves it to end now', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120)],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      await container
          .read(plannerActionsProvider)
          .setDone(account.blocks.single, true, now: now.add(const Duration(seconds: 40)));
      await pumpEventQueue();
      final b = account.blocks.single;
      expect(PlanMark.of(b)!.done, isTrue);
      expect(b.end, now);
      expect(b.start, now.subtract(const Duration(hours: 1)));
      // The Planner then plans only the hour that is left, after now.
      await container.read(plannerControllerProvider.notifier).runNow();
      final open = [
        for (final e in account.blocks)
          if (!PlanMark.of(e)!.done) e,
      ];
      expect(open, hasLength(1));
      expect(open.single.duration.inMinutes, 60);
      expect(open.single.start.isAfter(now), isTrue);
    });

    test('"Not done after all" opens the block again', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', running, done: true)],
      );
      final container = await start(account);
      final finished = await container
          .read(plannerActionsProvider)
          .setDone(account.blocks.single, false);
      await pumpEventQueue();
      expect(finished, isNull);
      final mark = PlanMark.of(account.blocks.single)!;
      expect(mark.done, isFalse);
      expect(mark.reason, PlanReason.kept);
      expect(account.log, ['save a:1']);
    });

    test('"Not done after all" on the last part opens the task again, '
        'so its time is planned and not dropped', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', now.subtract(const Duration(hours: 2)))],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      // The last part is done, so the task is ticked off.
      expect(await actions.setDone(account.blocks.single, true), 'a');
      await pumpEventQueue();
      expect(account.tasks.single.completed, isTrue);

      // Later, from the block's sheet (the message with Undo is long gone).
      account.log.clear();
      await actions.setDone(account.blocks.single, false);
      await pumpEventQueue();
      expect(account.log, ['save a:1', 'complete a false']);
      expect(account.tasks.single.completed, isFalse);

      // The Planner keeps planning the task: an hour of it is on the
      // calendar, not done.
      await container.read(plannerControllerProvider.notifier).runNow();
      await pumpEventQueue();
      await container.read(plannerControllerProvider.notifier).runNow();
      final open = [
        for (final b in account.blocks)
          if (!PlanMark.of(b)!.done) b,
      ];
      expect(open, hasLength(1));
      expect(open.single.duration.inMinutes, 60);
    });

    test('a repeating task is not reopened from Calendar either', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', repeats: true)],
        events: [
          block('a:1', 'a', running, done: true, occurrence: '2026-11-20T00:00:00.000'),
        ],
      );
      final container = await start(account);
      await container.read(plannerActionsProvider).setDone(account.blocks.single, false);
      await pumpEventQueue();
      expect(account.log, ['save a:1']);
    });
  });

  group('Need more time', () {
    test('adds to the task, counts a passed block as done, '
        'and the Planner plans the extra', () async {
      final passed = now.subtract(const Duration(hours: 2));
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', passed)],
      );
      final container = await start(account);
      await container.read(plannerActionsProvider).needMoreTime(account.blocks.single, 30);
      await pumpEventQueue();
      expect(account.tasks.single.minutes, 90);
      expect(PlanMark.of(account.blocks.single)!.done, isTrue);
      expect(account.tasks.single.completed, isFalse);

      await container.read(plannerControllerProvider.notifier).runNow();
      expect(account.blocks, hasLength(2));
      final extra = account.blocks.last;
      expect(PlanMark.of(extra)!.done, isFalse);
      expect(extra.duration.inMinutes, 30);
      expect(extra.start.isAfter(now), isTrue);
    });

    test('a block that is running or still to come stays as it is', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a'), task('b')],
        events: [block('a:1', 'a', running), block('b:1', 'b', tomorrow)],
      );
      final container = await start(account);
      final actions = container.read(plannerActionsProvider);
      await actions.needMoreTime(account.blocks.first, 60);
      await actions.needMoreTime(account.blocks.last, 15);
      await pumpEventQueue();
      expect(account.tasks.map((t) => t.minutes), [120, 75]);
      expect(account.blocks.map((b) => PlanMark.of(b)!.done), [false, false]);
      expect(account.log.where((l) => l.startsWith('save')), isEmpty);
    });

    test('a task with no length set starts from the default', () async {
      final account = FakeAccount(
        settings: on.copyWith(defaultMinutes: 45),
        tasks: [const PlannerTask(id: 'a', title: 'Task a')],
        events: [block('a:1', 'a', tomorrow, minutes: 45)],
      );
      final container = await start(account);
      await container.read(plannerActionsProvider).needMoreTime(account.blocks.single, 30);
      expect(account.tasks.single.minutes, 75);
    });
  });

  test('"Didn\'t do it" gives the time back, and it is planned again', () async {
    final passed = now.subtract(const Duration(hours: 2));
    final account = FakeAccount(
      settings: on,
      tasks: [task('a')],
      events: [block('a:1', 'a', passed)],
    );
    final container = await start(account);
    await container.read(plannerActionsProvider).didNot(account.blocks.single);
    await pumpEventQueue();
    expect(account.blocks, isEmpty);
    expect(account.log, ['delete a:1']);

    await container.read(plannerControllerProvider.notifier).runNow();
    expect(account.blocks, hasLength(1));
    expect(account.blocks.single.duration.inMinutes, 60);
    expect(account.blocks.single.start.isAfter(now), isTrue);
    expect(PlanMark.of(account.blocks.single)!.done, isFalse);
  });

  group('Not now', () {
    test('keeps the task away until the time chosen, and only that task', () async {
      final account = FakeAccount(settings: on, tasks: [task('a'), task('b')]);
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      await planner.runNow();
      // Both are planned for today or early tomorrow.
      final first = account.blocks.firstWhere((b) => PlanMark.of(b)!.itemId == 'a');
      final other = account.blocks.firstWhere((b) => PlanMark.of(b)!.itemId == 'b');
      final until = DateTime(now.year, now.month, now.day + 3);
      expect(first.start.isBefore(until), isTrue);

      await container.read(plannerActionsProvider).notNow(first, until);
      await pumpEventQueue();
      expect(account.settings.skips, {'a': until});
      await planner.runNow();
      final moved = account.blocks.firstWhere((b) => PlanMark.of(b)!.itemId == 'a');
      expect(moved.start.isBefore(until), isFalse);
      expect(moved.start.difference(until).inHours, lessThan(24));
      // The other task takes the time that came free, or stays put.
      final otherNow = account.blocks.firstWhere((b) => PlanMark.of(b)!.itemId == 'b');
      expect(otherNow.start.isAfter(other.start), isFalse);

      // The same answer again plans nothing new.
      account.log.clear();
      await planner.runNow();
      expect(account.log, isEmpty);
    });

    test('times that have passed are dropped when the next one is saved', () async {
      final old = now.subtract(const Duration(days: 2));
      final account = FakeAccount(
        settings: on.copyWith(skips: {'gone': old}),
        tasks: [task('a')],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      final until = DateTime(now.year, now.month, now.day + 2);
      await container.read(plannerActionsProvider).notNow(account.blocks.single, until);
      await pumpEventQueue();
      expect(account.settings.skips, {'a': until});
      expect(account.blocks, isEmpty);
    });

    test('the settings keep the times through sync, as wall-clock times', () {
      final until = DateTime(2026, 11, 25);
      final settings = on.copyWith(skips: {'a': until}, askAtEnd: false);
      final json = settings.toJson();
      expect(json['skips'], {'a': '2026-11-25T00:00:00.000'});
      final back = PlannerSettings.fromJson(json);
      expect(back.skips, {'a': until});
      expect(back.askAtEnd, isFalse);
      // Settings written before this version ask at the end, with no skips.
      final before = PlannerSettings.fromJson({'enabled': true});
      expect(before.askAtEnd, isTrue);
      expect(before.skips, isEmpty);
      expect(before.toJson().containsKey('skips'), isFalse);
      // A newer version's unknown keys and broken values do no harm.
      final odd = PlannerSettings.fromJson({
        'skips': {'a': 'soon', 'b': 5, 'c': '2026-12-01T09:30:00.000'},
      });
      expect(odd.skips, {'c': DateTime(2026, 12, 1, 9, 30)});
    });
  });

  group('Lock and move', () {
    test('a locked block stays when a meeting lands on it; unlocked, it moves', () async {
      final account = FakeAccount(settings: on, tasks: [task('a')]);
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      final actions = container.read(plannerActionsProvider);
      // A block two days out, so nothing about "starting soon" applies.
      await planner.runNow();
      await actions.notNow(account.blocks.single, DateTime(now.year, now.month, now.day + 2));
      await pumpEventQueue();
      await planner.runNow();
      final placed = account.blocks.single;

      await actions.setLocked(placed, true);
      await pumpEventQueue();
      expect(PlanMark.of(account.blocks.single)!.locked, isTrue);
      expect(PlanMark.of(account.blocks.single)!.reason, PlanReason.locked);

      // A meeting right on top of it.
      account.events = [
        ...account.events,
        CalendarEvent(id: 'meeting', title: 'Meeting', start: placed.start, end: placed.end),
      ];
      account.emit();
      await pumpEventQueue();
      account.log.clear();
      await planner.runNow();
      expect(account.blocks.single.start, placed.start, reason: 'a locked block moved');
      expect(account.log, isEmpty);
      // The Planner says the two overlap, so the block's sheet can too.
      expect(container.read(plannerControllerProvider).last!.result.conflicts, [placed.id]);

      await actions.setLocked(account.blocks.single, false);
      await pumpEventQueue();
      await planner.runNow();
      expect(PlanMark.of(account.blocks.single)!.locked, isFalse);
      expect(account.blocks.single.start, isNot(placed.start));
      expect(account.blocks.single.start.isBefore(placed.end), isFalse);
    });

    test('a block that is moved is locked where it was put', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', tomorrow)],
      );
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      final to = DateTime(now.year, now.month, now.day + 4, 16, 30);
      await container.read(plannerActionsProvider).move(account.blocks.single, to);
      await pumpEventQueue();
      var b = account.blocks.single;
      expect(b.start, to);
      expect(b.duration.inMinutes, 60);
      expect(PlanMark.of(b)!.locked, isTrue);
      await planner.runNow();
      b = account.blocks.single;
      expect(b.start, to, reason: 'the Planner moved a block the user placed');

      // A drag on the bottom edge makes it longer; still one block, locked.
      await container
          .read(plannerActionsProvider)
          .move(b, to, to.add(const Duration(minutes: 90)));
      await pumpEventQueue();
      await planner.runNow();
      expect(account.blocks.single.duration.inMinutes, 90);
      expect(account.blocks, hasLength(1));
    });
  });

  group('Answers from the notification', () {
    test('are applied before the Planner plans', () async {
      final passed = now.subtract(const Duration(hours: 3));
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 120), task('b'), task('c')],
        events: [
          block('a:1', 'a', passed),
          block('b:1', 'b', passed.add(const Duration(hours: 1))),
          block('c:1', 'c', passed.add(const Duration(hours: 2)), minutes: 30),
        ],
      );
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      await account.answers.add(const PlanAnswer('a:1', PlanAnswerKind.done));
      await account.answers.add(const PlanAnswer('b:1', PlanAnswerKind.skip));
      await account.answers.add(const PlanAnswer('c:1', PlanAnswerKind.more));
      await account.answers.add(const PlanAnswer('gone:1', PlanAnswerKind.done));

      await planner.runNow();
      await pumpEventQueue();
      expect(await account.answers.take(), isEmpty);
      CalendarEvent? stored(String id) =>
          account.blocks.where((b) => b.id == id).firstOrNull;
      // Done: one part of two, so the task stays open.
      expect(PlanMark.of(stored('a:1'))!.done, isTrue);
      expect(account.tasks.firstWhere((t) => t.id == 'a').completed, isFalse);
      // Didn't do it: the block is gone.
      expect(stored('b:1'), isNull);
      // Need more time: done, and the shortest block's worth more.
      expect(PlanMark.of(stored('c:1'))!.done, isTrue);
      expect(account.tasks.firstWhere((t) => t.id == 'c').minutes, 90);

      // The next run plans from what the answers left.
      await planner.runNow();
      final open = [
        for (final b in account.blocks)
          if (!PlanMark.of(b)!.done) '${PlanMark.of(b)!.itemId} ${b.duration.inMinutes}',
      ]..sort();
      expect(open, ['a 60', 'b 60', 'c 60']);
    });

    test('one that cannot be applied does not lose the others', () async {
      final passed = now.subtract(const Duration(hours: 3));
      final account = FakeAccount(
        settings: on,
        // Task "gone" was deleted in ZT Tasks while Calendar was locked; its
        // block is still on the calendar.
        tasks: [task('a', minutes: 120), task('b', minutes: 120)],
        events: [
          block('gone:1', 'gone', passed),
          block('a:1', 'a', passed.add(const Duration(hours: 1))),
          block('b:1', 'b', passed.add(const Duration(hours: 2))),
        ],
      );
      final container = await start(account);
      final planner = container.read(plannerControllerProvider.notifier);
      await account.answers.add(const PlanAnswer('gone:1', PlanAnswerKind.more));
      await account.answers.add(const PlanAnswer('a:1', PlanAnswerKind.done));
      await account.answers.add(const PlanAnswer('b:1', PlanAnswerKind.done));
      // Saving a:1 fails once (storage hiccup).
      var failures = 1;
      account.onSaveBlock = (id) async {
        if (id == 'a:1' && failures-- > 0) throw StateError('disk full');
      };

      await planner.runNow();
      await pumpEventQueue();
      CalendarEvent? stored(String id) =>
          account.blocks.where((b) => b.id == id).firstOrNull;
      // The answer after the two that could not be applied was applied.
      expect(PlanMark.of(stored('b:1'))!.done, isTrue);
      expect(PlanMark.of(stored('a:1'))!.done, isFalse);
      // The one that failed waits; the one for the deleted task is dropped.
      final waiting = await account.answers.take();
      expect(waiting, const [PlanAnswer('a:1', PlanAnswerKind.done)]);
      await account.answers.putBack(waiting);

      // The next run applies it.
      await planner.runNow();
      await pumpEventQueue();
      expect(PlanMark.of(stored('a:1'))!.done, isTrue);
      expect(await account.answers.take(), isEmpty);
    });

    test('"Done" on the last part ticks the task off', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', now.subtract(const Duration(hours: 2)))],
      );
      final container = await start(account);
      await account.answers.add(const PlanAnswer('a:1', PlanAnswerKind.done));
      await container.read(plannerControllerProvider.notifier).runNow();
      await pumpEventQueue();
      expect(account.tasks.single.completed, isTrue);
      expect(account.log, ['save a:1', 'complete a true']);
    });

    test('wait while the calendar is still syncing', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a')],
        events: [block('a:1', 'a', now.subtract(const Duration(hours: 2)))],
        synced: false,
      );
      final container = await start(account);
      await account.answers.add(const PlanAnswer('a:1', PlanAnswerKind.done));
      await container.read(plannerControllerProvider.notifier).runNow();
      expect(account.log, isEmpty);
      // Still there for the run after the sync.
      expect(await account.answers.take(), hasLength(1));
    });

    test('mean nothing once the Planner is off', () async {
      final account = FakeAccount(
        settings: PlannerSettings(hours: allDayHours),
        tasks: [task('a')],
      );
      final container = await start(account);
      await account.answers.add(const PlanAnswer('a:1', PlanAnswerKind.done));
      await container.read(plannerControllerProvider.notifier).runNow();
      await pumpEventQueue();
      expect(await account.answers.take(), isEmpty);
      expect(account.log, isEmpty);
    });
  });

  test('moving a due date keeps the time of day and every other field', () {
    final at = DateTime(2026, 11, 18, 12);
    final timed = PlannerTask.withDueDay(
      {'title': 'Report', 'dueDate': '2026-11-20T16:30:00.000', 'planMinutes': 60, 'x': 1},
      DateTime(2026, 11, 24),
      at,
    );
    expect(timed['dueDate'], '2026-11-24T16:30:00.000');
    expect(timed['title'], 'Report');
    expect(timed['planMinutes'], 60);
    expect(timed['x'], 1);
    expect(timed['updatedAt'], at.toIso8601String());
    // A date with no time stays a date with no time.
    final dateOnly = PlannerTask.withDueDay(
      {'dueDate': '2026-11-20T00:00:00.000'},
      DateTime(2026, 11, 24, 9, 15),
      at,
    );
    expect(dateOnly['dueDate'], '2026-11-24T00:00:00.000');
    expect(PlannerTask.fromItem('t', dateOnly)!.dueHasTime, isFalse);
  });
}
