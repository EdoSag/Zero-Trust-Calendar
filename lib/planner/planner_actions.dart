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
    final at = now ?? DateTime.now();
    // Done on a block being timed (the helper's change, or an answer to
    // a question asked before "Start now") is "Stop": the time that was
    // really worked counts, not the planned length.
    if (done && mark.runningAt(at)) return (await stop(block, now: at)).finished;
    var saved = block;
    if (done && block.start.isAfter(at)) {
      final end = DateTime(at.year, at.month, at.day, at.hour, at.minute);
      saved = block.copyWith(start: end.subtract(block.duration), end: end);
    }
    await _writer.saveBlock(
      _marked(
        saved,
        // A timer that was left running too long to count ends here.
        mark.copyWith(
          done: done,
          reason: done ? PlanReason.done : PlanReason.kept,
          started: null,
        ),
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
    return _tickOffWhenDone(mark.itemId, saved);
  }

  /// Ticks the task off in ZT Tasks when [doneBlock], just saved as done,
  /// was the last of its time, and returns its id then. A repeating task is
  /// left to ZT Tasks.
  Future<String?> _tickOffWhenDone(String taskId, CalendarEvent doneBlock) async {
    final task = _task(taskId);
    if (task == null || task.completed || task.repeats) return null;
    final others = [
      for (final b in _ref.read(plannerBlocksProvider))
        if (b.id != doneBlock.id) b,
    ];
    final doneMinutes = planDoneMinutes(task, others) + doneBlock.duration.inMinutes;
    if (doneMinutes < (task.minutes ?? _settings.defaultMinutes)) return null;
    await _ref.read(plannerTaskCompleterProvider)(task.id, true);
    return task.id;
  }

  static DateTime _minute(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);

  /// The task block being timed at [now], if any.
  CalendarEvent? running({DateTime? now}) {
    final at = now ?? DateTime.now();
    return _ref
        .read(plannerBlocksProvider)
        .where((b) => PlanMark.of(b)!.runningAt(at))
        .firstOrNull;
  }

  /// "Start now" on a task's block: work on it begins at [now]. The block
  /// moves to start now, keeps its length (a block already under way keeps
  /// its end, when a few minutes of it are left), and is locked there. One
  /// block is timed at a time: another one running is stopped first.
  /// Returns the block as saved.
  Future<CalendarEvent> start(CalendarEvent block, {DateTime? now}) async {
    final mark = PlanMark.of(block);
    if (mark == null || mark.isHabit || mark.done) {
      throw StateError('That block can\'t be started');
    }
    final at = _minute(now ?? DateTime.now());
    final other = running(now: at);
    if (other != null && other.id != block.id) await stop(other, now: at);
    final underWay = !block.start.isAfter(at) &&
        block.end.difference(at) >= const Duration(minutes: 5);
    final saved = _marked(
      block.copyWith(start: at, end: underWay ? block.end : at.add(block.duration)),
      mark.copyWith(locked: true, reason: PlanReason.locked, started: at),
    );
    await _writer.saveBlock(saved);
    return saved;
  }

  /// "Start now" on a task: its next block that isn't done starts now. A
  /// task with no such block gets one, as long as what is left of it (at
  /// least the shortest block, at most the longest).
  Future<CalendarEvent> startTask(PlannerTask task, {DateTime? now}) async {
    final at = _minute(now ?? DateTime.now());
    final blocks = planBlocksOf(task, _ref.read(plannerBlocksProvider));
    final next = blocks
        .where((b) => !PlanMark.of(b)!.done && b.end.isAfter(at))
        .firstOrNull;
    if (next != null) return start(next, now: at);
    final other = running(now: at);
    if (other != null) await stop(other, now: at);
    final settings = _settings;
    var minChunk = task.minChunk ?? settings.minChunk;
    final maxChunk = task.maxChunk ?? settings.maxChunk;
    if (maxChunk < minChunk) minChunk = maxChunk;
    final left = (task.minutes ?? settings.defaultMinutes) - planDoneMinutes(task, blocks);
    final block = _taskBlock(
      task,
      id: '${task.id}:s${at.millisecondsSinceEpoch ~/ 60000}',
      start: at,
      end: at.add(Duration(minutes: left.clamp(minChunk, maxChunk))),
      mark: (m) => m.copyWith(locked: true, reason: PlanReason.locked, started: at),
    );
    await _writer.saveBlock(block);
    return block;
  }

  /// "Stop": the block being timed ends at [now] and is done, so it shows
  /// the time that was really worked, and what is left of the task is
  /// planned again. Returns the block as saved, and the task's id when
  /// that was the last of its time (it is then ticked off, as in
  /// [setDone]).
  Future<({CalendarEvent block, String? finished})> stop(
    CalendarEvent block, {
    DateTime? now,
  }) async {
    final mark = PlanMark.of(block);
    final from = mark?.started;
    if (mark == null || from == null || mark.done) {
      throw StateError('That block isn\'t being timed');
    }
    var end = _minute(now ?? DateTime.now());
    // At least a minute, so the block is an event that can be shown.
    if (!end.isAfter(from)) end = from.add(const Duration(minutes: 1));
    final saved = _marked(
      block.copyWith(start: from, end: end),
      mark.copyWith(done: true, reason: PlanReason.done, started: null),
    );
    await _writer.saveBlock(saved);
    return (block: saved, finished: await _tickOffWhenDone(mark.itemId, saved));
  }

  /// "Log time": [minutes] already worked on [task], ending at [now], kept
  /// as a done block. Returns it, and the task's id when that was the last
  /// of its time.
  Future<({CalendarEvent block, String? finished})> logTime(
    PlannerTask task,
    int minutes, {
    DateTime? now,
  }) async {
    if (minutes <= 0) throw ArgumentError.value(minutes, 'minutes');
    final end = _minute(now ?? DateTime.now());
    final block = _taskBlock(
      task,
      id: '${task.id}:l${end.millisecondsSinceEpoch ~/ 60000}',
      start: end.subtract(Duration(minutes: minutes)),
      end: end,
      mark: (m) => m.copyWith(done: true, reason: PlanReason.done),
    );
    await _writer.saveBlock(block);
    return (block: block, finished: await _tickOffWhenDone(task.id, block));
  }

  /// A new block of [task], outside the engine's numbering. An id that is
  /// taken (two in one minute) gets a number after it.
  CalendarEvent _taskBlock(
    PlannerTask task, {
    required String id,
    required DateTime start,
    required DateTime end,
    required PlanMark Function(PlanMark) mark,
  }) {
    final taken = {for (final b in _ref.read(plannerBlocksProvider)) b.id};
    var unique = id;
    for (var n = 2; taken.contains(unique); n++) {
      unique = '$id.$n';
    }
    return CalendarEvent(
      id: unique,
      title: task.title,
      start: start,
      end: end,
      calendarId: plannerCalendarId,
      taskIds: [task.id],
      extra: {
        'plan': mark(
          PlanMark(
            kind: PlanBlockKind.task,
            itemId: task.id,
            occurrence: task.occurrence,
          ),
        ).toJson(),
      },
    );
  }

  /// Removes a block that [startTask] or [logTime] made (undo).
  Future<void> remove(CalendarEvent block) async {
    if (PlanMark.of(block) == null) return;
    await _writer.deleteBlock(block.id);
  }

  /// Opens a task again that [setDone] ticked off.
  Future<void> reopenTask(String taskId) =>
      _ref.read(plannerTaskCompleterProvider)(taskId, false);

  /// Ticks the block's task off in ZT Tasks.
  Future<void> finishTask(String taskId) =>
      _ref.read(plannerTaskCompleterProvider)(taskId, true);

  /// Gives the block's task [extra] more minutes. A block whose time has
  /// passed counts as done; one that is still running or still to come
  /// stays as it is, and so does one being timed, whatever its planned
  /// end: its time worked is known only at "Stop". [passed] says whether
  /// its time has passed, when the caller knows better than the clock.
  Future<void> needMoreTime(
    CalendarEvent block,
    int extra, {
    DateTime? now,
    bool? passed,
  }) async {
    final mark = PlanMark.of(block);
    if (mark == null) return;
    final task = _task(mark.itemId);
    if (task == null) throw StateError('That task is gone');
    await _ref.read(plannerTaskWriterProvider)(task.id, {
      'planMinutes': (task.minutes ?? _settings.defaultMinutes) + extra,
    });
    final at = now ?? DateTime.now();
    final over = passed ?? (!block.end.isAfter(at) && !mark.runningAt(at));
    if (!mark.done && over) {
      await _writer.saveBlock(
        _marked(block, mark.copyWith(done: true, reason: PlanReason.done, started: null)),
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
  ///
  /// A block being timed was started after its question was asked (none
  /// is asked while a timer runs). "Done" then stops the timer, "Need
  /// more time" leaves it running, and "Didn't do it" is dropped: it is
  /// being done now.
  Future<List<PlanAnswer>> applyAnswers(List<PlanAnswer> answers, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final failed = <PlanAnswer>[];
    for (final a in answers) {
      final block = _ref
          .read(plannerBlocksProvider)
          .where((b) => b.id == a.blockId)
          .firstOrNull;
      final mark = PlanMark.of(block);
      if (block == null || mark == null || mark.done) continue;
      final timed = mark.runningAt(at);
      try {
        switch (a.kind) {
          case PlanAnswerKind.done:
            await setDone(block, true, now: at);
          case PlanAnswerKind.more:
            // The task was deleted meanwhile: the Planner removes its block.
            if (_task(mark.itemId) == null) continue;
            // The question is asked when the block ends, so its time has
            // passed however long the answer waited.
            await needMoreTime(block, _settings.minChunk, now: at, passed: !timed);
          case PlanAnswerKind.skip:
            if (timed) continue;
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
