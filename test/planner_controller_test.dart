import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';

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

PlannerTask task(String id, {int minutes = 60, bool completed = false}) => PlannerTask(
  id: id,
  title: 'Task $id',
  minutes: minutes,
  completed: completed,
  createdAt: id,
);

/// A container on [account], with the Planner's controller running and
/// every stream loaded.
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

void main() {
  test('plans the tasks, saves the blocks, and then leaves them alone', () async {
    final account = FakeAccount(settings: on, tasks: [task('a'), task('b', minutes: 90)]);
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);

    await planner.runNow();
    expect(account.blocks, hasLength(2));
    expect(account.blocks.map((b) => PlanMark.of(b)!.itemId).toSet(), {'a', 'b'});
    expect(account.blocks.map((b) => b.duration.inMinutes).toSet(), {60, 90});
    final status = container.read(plannerControllerProvider);
    expect(status.waiting, isNull);
    expect(status.error, isNull);
    expect(status.last!.result.risks, isEmpty);

    // The same data again: nothing is written (no ping-pong between devices).
    account.log.clear();
    await pumpEventQueue();
    await planner.runNow();
    await planner.runNow();
    expect(account.log, isEmpty);
  });

  test('does not plan before the first sync has finished', () async {
    final account = FakeAccount(settings: on, tasks: [task('a')], synced: false);
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    await planner.runNow();
    expect(account.log, isEmpty);
    expect(container.read(plannerControllerProvider).waiting, PlannerWaiting.loading);

    account.synced = true;
    container.invalidate(plannerSyncedProvider);
    await planner.runNow();
    expect(account.blocks, hasLength(1));
  });

  test('a new phone does not delete blocks while its tasks are still arriving', () async {
    // The blocks came with Calendar's own sync; the copy of ZT Tasks is
    // still on its first pull, so the task list is empty for now.
    final now = DateTime.now();
    final existing = CalendarEvent(
      id: 'a:1',
      title: 'Task a',
      start: DateTime(now.year, now.month, now.day + 1, 10),
      end: DateTime(now.year, now.month, now.day + 1, 11),
      calendarId: plannerCalendarId,
      taskIds: const ['a'],
      reminders: const [0],
      extra: const {
        'plan': {'type': 'task', 'taskId': 'a', 'locked': false, 'done': false},
      },
    );
    final account = FakeAccount(settings: on, events: [existing], tasksRefreshOk: null);
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    await planner.runNow();
    expect(account.log, isEmpty, reason: 'planned from a task list that is still loading');
    expect(account.blocks.single.id, 'a:1');

    // Offline and nothing ever pulled: still not a list to plan from.
    account.tasksRefreshOk = false;
    account.emit();
    await pumpEventQueue();
    await planner.runNow();
    expect(account.log, isEmpty);

    // The pull finished and the task is there: the block stays.
    account.tasks = [task('a')];
    account.tasksRefreshOk = true;
    account.emit();
    await pumpEventQueue();
    await planner.runNow();
    expect(account.log, isEmpty);
    expect(account.blocks.single.id, 'a:1');

    // The pull finished and the task really is gone: so is the block.
    account.tasks = [];
    account.emit();
    await pumpEventQueue();
    await planner.runNow();
    expect(account.log, ['delete a:1']);
  });

  test('turning the Planner on makes its calendar, turning it off removes '
      'the blocks that are not done', () async {
    final account = FakeAccount(
      settings: PlannerSettings(hours: allDayHours, tasks: PlannerTasksChoice.all),
      tasks: [task('a'), task('b')],
    );
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);

    // Off: nothing is planned.
    await planner.runNow();
    expect(account.log, isEmpty);
    expect(container.read(plannerControllerProvider).waiting, PlannerWaiting.off);

    await planner.saveSettings(account.settings.copyWith(enabled: true));
    await pumpEventQueue();
    expect(account.calendars.map((c) => c.id), contains(plannerCalendarId));
    expect(account.calendars.last.name, 'Planned');
    await planner.runNow();
    expect(account.blocks, hasLength(2));

    // One block is done: it is history and stays.
    final done = account.blocks.first;
    account.events = [
      for (final e in account.events)
        e.id == done.id
            ? e.copyWith(
                extra: {'plan': PlanMark.of(e)!.copyWith(done: true).toJson()},
              )
            : e,
    ];
    account.emit();
    await pumpEventQueue();

    account.log.clear();
    await planner.saveSettings(account.settings.copyWith(enabled: false));
    await pumpEventQueue();
    expect(account.blocks.map((b) => b.id), [done.id]);
    expect(account.settings.enabled, isFalse);
    // And it stays off.
    account.log.clear();
    await planner.runNow();
    expect(account.log, isEmpty);
  });

  test('the preview plans without saving anything', () async {
    final account = FakeAccount(
      settings: PlannerSettings(hours: allDayHours),
      tasks: [task('a'), task('b')],
    );
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    // "Only tasks I switch on", none on yet: nothing to plan.
    expect(planner.preview(account.settings)!.save, isEmpty);
    // One picked in the setup.
    final picked = planner.preview(account.settings, switchOn: {'b'})!;
    expect(picked.save.map((b) => PlanMark.of(b)!.itemId), ['b']);
    // All tasks.
    final all = planner.preview(account.settings.copyWith(tasks: PlannerTasksChoice.all))!;
    expect(all.save, hasLength(2));
    expect(account.log, isEmpty);
    expect(account.blocks, isEmpty);
  });

  test('a change to the settings plans every movable block afresh', () async {
    final account = FakeAccount(settings: on, tasks: [task('a', minutes: 240)]);
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    await planner.runNow();
    // Four hours in blocks of at most two.
    expect(account.blocks.map((b) => b.duration.inMinutes), [120, 120]);

    await planner.saveSettings(account.settings.copyWith(maxChunk: 60));
    await pumpEventQueue();
    await planner.runNow();
    // Kept blocks would not be checked against the new limit: the rebuild
    // after a settings change is what makes them four blocks of one hour.
    expect(account.blocks.map((b) => b.duration.inMinutes), [60, 60, 60, 60]);
  });

  test('settings changed on another device plan the blocks afresh here too', () async {
    final account = FakeAccount(settings: on, tasks: [task('a', minutes: 240)]);
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    await planner.runNow();
    expect(account.blocks.map((b) => b.duration.inMinutes), [120, 120]);

    // The new settings arrive by sync: nothing here called saveSettings.
    account.settings = account.settings.copyWith(maxChunk: 60);
    account.emit();
    await pumpEventQueue();
    await planner.runNow();
    expect(account.blocks.map((b) => b.duration.inMinutes), [60, 60, 60, 60]);

    // Planned with these settings now: the next run leaves everything alone.
    await pumpEventQueue();
    account.log.clear();
    await planner.runNow();
    expect(account.log, isEmpty);

    // A switch that moves no block (the reminder) is not a reason to
    // place them afresh.
    final before = [for (final b in account.blocks) b.start];
    account.settings = account.settings.copyWith(remindAtStart: false);
    account.emit();
    await pumpEventQueue();
    await planner.runNow();
    expect([for (final b in account.blocks) b.start], before);
  });

  test('settings changed while the app was closed are followed when it opens', () async {
    final account = FakeAccount(settings: on, tasks: [task('a', minutes: 240)]);
    final first = await start(account);
    await first.read(plannerControllerProvider.notifier).runNow();
    expect(account.blocks.map((b) => b.duration.inMinutes), [120, 120]);
    first.dispose();

    // Saved (here or elsewhere) but never planned with: the app closed
    // before the Planner ran.
    account.settings = account.settings.copyWith(maxChunk: 60);
    final second = await start(account);
    await second.read(plannerControllerProvider.notifier).runNow();
    expect(account.blocks.map((b) => b.duration.inMinutes), [60, 60, 60, 60]);
  });

  test('turning the Planner off while it is saving blocks leaves none behind', () async {
    final account = FakeAccount(
      settings: on,
      tasks: [task('a'), task('b'), task('c')],
    );
    final container = await start(account);
    final planner = container.read(plannerControllerProvider.notifier);
    Future<void>? turningOff;
    account.onSaveBlock = (id) async {
      // The user turns the Planner off while the first block is on its way.
      turningOff ??= planner.saveSettings(account.settings.copyWith(enabled: false));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    };
    await planner.runNow();
    await turningOff;
    await pumpEventQueue();

    expect(account.settings.enabled, isFalse);
    expect(account.blocks, isEmpty, reason: 'blocks were written after the cleanup');
    // The run stopped after the block it was on.
    expect(account.log.where((l) => l.startsWith('save')), hasLength(1));
    expect(container.read(plannerControllerProvider).waiting, PlannerWaiting.off);

    // Off stays off, and on again plans as usual.
    account.onSaveBlock = null;
    account.log.clear();
    await planner.runNow();
    expect(account.log, isEmpty);
    await planner.saveSettings(account.settings.copyWith(enabled: true));
    await pumpEventQueue();
    await planner.runNow();
    expect(account.blocks, hasLength(3));
  });
}
