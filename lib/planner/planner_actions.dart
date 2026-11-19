import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import 'planner_answers.dart';
import 'planner_controller.dart';
import 'planner_model.dart';
import 'planner_plan.dart';

/// What the user does to one of the Planner's blocks: done, need more time,
/// not now, lock, move. Each saves the block (and sometimes the task or the
/// Planner's settings); the Planner then plans again by itself, because it
/// follows those.
class PlannerActions {
  PlannerActions(this._ref);
  final Ref _ref;

  PlannerWriter get _writer => _ref.read(plannerWriterProvider);

  PlannerSettings get _settings =>
      _ref.read(plannerSettingsProvider).value ?? const PlannerSettings();

  PlannerTask? _task(String id) =>
      (_ref.read(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
          .where((t) => t.id == id)
          .firstOrNull;

  static CalendarEvent _marked(CalendarEvent block, PlanMark mark) =>
      block.copyWith(extra: {...block.extra, 'plan': mark.toJson()});

  /// Marks [block] done, or not done after all (which also opens its task
  /// again, when that was ticked off).
  ///
  /// A block that hasn't started yet ("Already done") is moved to end now:
  /// the work was done before now, and the time it was planned for is free
  /// again.
  ///
  /// When that was the last of the task's time, the task itself is ticked
  /// off in ZT Tasks, and its id is returned so the screen can say so and
  /// offer to undo it. A repeating task is left to ZT Tasks, which knows how
  /// to roll it on to its next date.
  Future<String?> setDone(CalendarEvent block, bool done, {DateTime? now}) async {
    final mark = PlanMark.of(block);
    if (mark == null || mark.done == done) return null;
    var saved = block;
    final at = now ?? DateTime.now();
    if (done && block.start.isAfter(at)) {
      final end = DateTime(at.year, at.month, at.day, at.hour, at.minute);
      saved = block.copyWith(start: end.subtract(block.duration), end: end);
    }
    await _writer.saveBlock(
      _marked(
        saved,
        mark.copyWith(done: done, reason: done ? PlanReason.done : PlanReason.kept),
      ),
    );
    // A habit has no task to tick off or open again.
    if (mark.isHabit) return null;
    if (!done) {
      // The task was ticked off (by the last block being done, or in ZT
      // Tasks). This part isn't done after all, so neither is the task:
      // left ticked off, the Planner would drop the block instead of
      // planning its time again.
      final task = _task(mark.itemId);
      if (task != null && task.completed && !task.repeats) {
        await _ref.read(plannerTaskCompleterProvider)(task.id, false);
      }
      return null;
    }
    final task = _task(mark.itemId);
    if (task == null || task.completed || task.repeats) return null;
    final others = [
      for (final b in _ref.read(plannerBlocksProvider))
        if (b.id != block.id) b,
    ];
    final doneMinutes = planDoneMinutes(task, others) + block.duration.inMinutes;
    if (doneMinutes < (task.minutes ?? _settings.defaultMinutes)) return null;
    await _ref.read(plannerTaskCompleterProvider)(task.id, true);
    return task.id;
  }

  /// Opens a task again that [setDone] ticked off.
  Future<void> reopenTask(String taskId) =>
      _ref.read(plannerTaskCompleterProvider)(taskId, false);

  /// Ticks the block's task off in ZT Tasks.
  Future<void> finishTask(String taskId) =>
      _ref.read(plannerTaskCompleterProvider)(taskId, true);

  /// Gives the block's task [extra] more minutes. A block whose time has
  /// passed counts as done; one that is still running or still to come
  /// stays as it is.
  Future<void> needMoreTime(CalendarEvent block, int extra, {DateTime? now}) async {
    final mark = PlanMark.of(block);
    if (mark == null) return;
    final task = _task(mark.itemId);
    if (task == null) throw StateError('That task is gone');
    await _ref.read(plannerTaskWriterProvider)(task.id, {
      'planMinutes': (task.minutes ?? _settings.defaultMinutes) + extra,
    });
    if (!mark.done && !block.end.isAfter(now ?? DateTime.now())) {
      await _writer.saveBlock(
        _marked(block, mark.copyWith(done: true, reason: PlanReason.done)),
      );
    }
  }

  /// "Didn't do it": the block goes and its time is planned again.
  Future<void> didNot(CalendarEvent block) async {
    if (PlanMark.of(block) == null) return;
    await _writer.deleteBlock(block.id);
  }

  /// "Not now": the task isn't planned before [until]. This block goes, and
  /// the task's other blocks before [until] move by themselves.
  Future<void> notNow(CalendarEvent block, DateTime until, {DateTime? now}) async {
    final mark = PlanMark.of(block);
    if (mark == null) return;
    final settings = _settings;
    await _writer.saveSettings(
      settings.copyWith(
        skips: {...settings.skipsAfter(now ?? DateTime.now()), mark.itemId: until},
      ),
    );
    await _writer.deleteBlock(block.id);
  }

  /// Locks [block] where it is (the Planner then never moves it), or lets
  /// the Planner move it again.
  Future<void> setLocked(CalendarEvent block, bool locked) async {
    final mark = PlanMark.of(block);
    if (mark == null || mark.locked == locked) return;
    await _writer.saveBlock(
      _marked(
        block,
        mark.copyWith(
          locked: locked,
          reason: locked ? PlanReason.locked : PlanReason.kept,
        ),
      ),
    );
  }

  /// Puts [block] at [start] (to [end], or as long as it was) and locks it
  /// there: a block the user placed stays where they put it.
  Future<void> move(CalendarEvent block, DateTime start, [DateTime? end]) async {
    final mark = PlanMark.of(block);
    if (mark == null) return;
    await _writer.saveBlock(
      _marked(
        block.copyWith(start: start, end: end ?? start.add(block.duration)),
        mark.copyWith(locked: true, reason: PlanReason.locked),
      ),
    );
  }

  /// A habit's block skipped for the day, or kept after all. Either way
  /// it is history: the habit isn't planned again that day.
  Future<void> setHabitSkipped(CalendarEvent block, bool skipped) async {
    final mark = PlanMark.of(block);
    if (mark == null || !mark.isHabit) return;
    if (mark.done && mark.skipped == skipped) return;
    await _writer.saveBlock(
      _marked(block, mark.copyWith(done: true, skipped: skipped, reason: PlanReason.done)),
    );
  }

  /// Saves settings the way the Planner screen does: blocks still to come
  /// are placed afresh, here and on the other devices.
  Future<void> _saveSettings(PlannerSettings settings) =>
      _ref.read(plannerControllerProvider.notifier).saveSettings(settings);

  /// Adds [habit], or changes the one with its id.
  Future<void> saveHabit(PlannerHabit habit) {
    final settings = _settings;
    final i = settings.habits.indexWhere((h) => h.id == habit.id);
    return _saveSettings(
      settings.copyWith(
        habits: i == -1
            ? [...settings.habits, habit]
            : (List.of(settings.habits)..[i] = habit),
      ),
    );
  }

  /// Removes a habit. Its blocks still to come go with it; the ones that
  /// passed stay as a record.
  Future<void> deleteHabit(String id) {
    final settings = _settings;
    return _saveSettings(
      settings.copyWith(habits: [for (final h in settings.habits) if (h.id != id) h]),
    );
  }

  /// Sets the weekly focus time goal (0 turns it off). [title] names the
  /// focus blocks.
  Future<void> setFocusGoal(int minutesPerWeek, String title) => _saveSettings(
    _settings.copyWith(focusMinutesPerWeek: minutesPerWeek, focusTitle: title),
  );

  /// Puts a block back exactly as it was (undo).
  Future<void> restore(CalendarEvent block) => _writer.saveBlock(block);

  /// Applies the answers given on notifications, each on its own: one
  /// that fails doesn't stop the ones after it. An answer for a block that
  /// is gone or already done, or whose task is gone, is dropped. Returns the
  /// answers that could not be saved, to be kept for the next run.
  Future<List<PlanAnswer>> applyAnswers(List<PlanAnswer> answers) async {
    final failed = <PlanAnswer>[];
    for (final a in answers) {
      final block = _ref
          .read(plannerBlocksProvider)
          .where((b) => b.id == a.blockId)
          .firstOrNull;
      final mark = PlanMark.of(block);
      if (block == null || mark == null || mark.done) continue;
      try {
        switch (a.kind) {
          case PlanAnswerKind.done:
            await setDone(block, true);
          case PlanAnswerKind.more:
            // The task was deleted meanwhile: the Planner removes its block.
            if (_task(mark.itemId) == null) continue;
            await needMoreTime(block, _settings.minChunk, now: block.end);
          case PlanAnswerKind.skip:
            await didNot(block);
        }
      } on Object {
        failed.add(a);
      }
    }
    return failed;
  }
}

final plannerActionsProvider = Provider<PlannerActions>(PlannerActions.new);
