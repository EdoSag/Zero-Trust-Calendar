import 'package:flutter/foundation.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import '../model/calendar_event.dart';
import 'planner_model.dart';

/// One run of the Planner: what the engine decided and what that means for
/// the stored events.
@immutable
class PlannerOutcome {
  const PlannerOutcome({
    required this.result,
    required this.save,
    required this.delete,
    required this.tasks,
    this.habits = const {},
    required this.at,
  });

  /// The engine's answer (the whole plan, risks, conflicts).
  final PlanResult result;

  /// Blocks to add or change, as events of the Planned calendar.
  final List<CalendarEvent> save;

  /// Ids of blocks to remove.
  final List<String> delete;

  /// The tasks that were planned, by id.
  final Map<String, PlannerTask> tasks;

  /// The habits that were planned (focus time among them), by id.
  final Map<String, PlannerHabit> habits;

  /// The time the plan was made for.
  final DateTime at;

  bool get changesNothing => save.isEmpty && delete.isEmpty;

  /// The plan as events (stored blocks with [save] and [delete] applied),
  /// soonest first: what the calendar shows once the plan is saved.
  List<CalendarEvent> blocksAfter(List<CalendarEvent> stored) {
    final byId = {
      for (final e in stored)
        if (PlanMark.of(e) != null && !delete.contains(e.id)) e.id: e,
      for (final e in save) e.id: e,
    };
    return byId.values.toList()..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }
}

/// The engine's settings for [settings].
PlanSettings planSettingsOf(PlannerSettings settings) => PlanSettings(
  bufferAfterEvents: settings.breakAfterMeetings,
  maxTaskMinutesPerDay: settings.maxMinutesPerDay,
  defaultMinChunk: settings.minChunk,
  defaultMaxChunk: settings.maxChunk < settings.minChunk
      ? settings.minChunk
      : settings.maxChunk,
  pastBlocks: settings.pastBlocks,
);

/// The engine's hours for [settings]: work first, so a task that names
/// hours the settings don't have falls back to work hours.
List<PlanHours> planHoursOf(PlannerSettings settings) => [
  for (final id in {workHoursId, personalHoursId, ...settings.hours.keys})
    PlanHours(id, {
      for (final d in (settings.hours[id] ?? const <int, List<MinuteRange>>{}).entries)
        d.key: [for (final (s, e) in d.value) PlanRange(s, e)],
    }),
];

/// The times the Planner keeps clear: timed events of every calendar that
/// counts (not hidden, not marked free), repeating events expanded, and
/// all-day events when [PlannerSettings.allDayBusy] is on or they are out of
/// office. The Planner's own
/// blocks are not busy times: the engine gets those as blocks.
List<PlanBusy> planBusyOf({
  required PlannerSettings settings,
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required DateTime from,
  required DateTime to,
}) {
  final skip = {
    ...settings.freeCalendarIds,
    for (final c in calendars)
      if (c.hidden) c.id,
  };
  return [
    for (final e in events)
      if (PlanMark.of(e) == null &&
          !skip.contains(e.calendarId) &&
          (!e.allDay || settings.allDayBusy || e.outOfOffice))
        for (final (s, end) in e.occurrencesBetween(from, to))
          if (end.isAfter(s))
            PlanBusy(PlanTime.wall(s), PlanTime.wall(end), buffered: !e.allDay),
  ];
}

/// The engine's task for [t].
PlanTask planTaskOf(PlannerTask t, PlannerSettings settings, {int order = 0}) {
  var minChunk = t.minChunk ?? settings.minChunk;
  final maxChunk = t.maxChunk ?? settings.maxChunk;
  if (maxChunk < minChunk) minChunk = maxChunk;
  final due = t.dueBy;
  // "Not now" keeps the task away until a time; the later of that and the
  // task's own start date counts.
  final skip = settings.skips[t.id];
  final start = t.notBefore;
  final notBefore = skip != null && (start == null || skip.isAfter(start)) ? skip : start;
  return PlanTask(
    id: t.id,
    minutes: t.minutes ?? settings.defaultMinutes,
    priority: t.priority,
    due: due == null ? null : PlanTime.wall(due),
    notBefore: notBefore == null ? null : PlanTime.wall(notBefore),
    minChunk: minChunk,
    maxChunk: maxChunk,
    hoursId: t.hoursId,
    order: order,
  );
}

/// Plans [tasks] around [events] and says which blocks to save and delete.
///
/// Pure: the same inputs give the same outcome on every device. [events] is
/// every event the calendar has (own, shared, subscribed), the Planner's own
/// blocks among them; [now] is the phone's local time.
///
/// [rebuild] places every movable block afresh. It is needed after a change
/// to the Planner's settings, because a block that is left where it is isn't
/// checked again against the limits.
PlannerOutcome computePlan({
  required DateTime now,
  required PlannerSettings settings,
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required List<PlannerTask> tasks,
  bool rebuild = false,
}) {
  final engineSettings = planSettingsOf(settings);
  final today = DateTime(now.year, now.month, now.day);
  final planned = [
    for (final t in tasks)
      if (t.plannedUnder(settings.tasks)) t,
  ]..sort((a, b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  final byId = {for (final t in planned) t.id: t};
  final habits = plannedHabitsOf(settings);
  final habitsById = {for (final h in habits) h.id: h};

  final stored = <String, CalendarEvent>{};
  final existing = <PlanBlock>[];
  final timed = <String>{};
  for (final e in events) {
    final mark = PlanMark.of(e);
    if (mark == null) continue;
    if (!e.end.isAfter(e.start) || e.allDay) continue;
    stored[e.id] = e;
    final task = mark.isHabit ? null : byId[mark.itemId];
    // A block done for an earlier date of a repeating task is history: it
    // keeps its id but no longer counts toward the task.
    final earlier = mark.done &&
        task != null &&
        mark.occurrence != null &&
        mark.occurrence != task.occurrence;
    // A block being timed ("Start now") is in progress until it is
    // stopped, also after the time it was planned to end: the engine
    // sees it reach just past now, so it is neither asked about nor
    // planned again, and the time worked so far counts.
    final running = mark.runningAt(now);
    if (running) timed.add(e.id);
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    existing.add(
      PlanBlock(
        id: e.id,
        itemId: earlier ? '${mark.itemId}@${mark.occurrence}' : mark.itemId,
        kind: mark.kind,
        start: PlanTime.wall(running && e.start.isAfter(now) ? now : e.start),
        end: PlanTime.wall(running && e.end.isBefore(nextMinute) ? nextMinute : e.end),
        locked: mark.locked,
        // A habit whose time has passed counts as kept unless it was
        // skipped: it isn't asked about, and it stays in the calendar as
        // a record.
        done: mark.done || (mark.isHabit && !e.end.isAfter(now)),
      ),
    );
  }

  final result = plan(
    now: PlanTime.wall(now),
    hours: planHoursOf(settings),
    settings: engineSettings,
    busy: planBusyOf(
      settings: settings,
      events: events,
      calendars: calendars,
      from: today,
      to: DateTime(today.year, today.month, today.day + engineSettings.horizonDays + 1),
    ),
    tasks: [
      for (final (i, t) in planned.indexed) planTaskOf(t, settings, order: i),
    ],
    habits: [
      for (final (i, h) in habits.indexed) h.toPlan(order: i),
    ],
    existing: existing,
    rebuild: rebuild,
  );

  final reminders = settings.remindAtStart ? const [0] : const <int>[];
  final save = <CalendarEvent>[];
  for (final b in result.blocks) {
    final old = stored[b.id];
    final oldMark = PlanMark.of(old);
    // A block being timed keeps the times it is stored with: stopping it
    // writes the real ones.
    final keep = old != null && timed.contains(b.id);
    final start = keep ? old.start : PlanTime.local(b.start);
    final end = keep ? old.end : PlanTime.local(b.end);
    if (old == null || oldMark == null) {
      if (b.kind == PlanBlockKind.habit) {
        final habit = habitsById[b.itemId];
        if (habit == null) continue;
        save.add(
          CalendarEvent(
            id: b.id,
            title: habit.title,
            start: start,
            end: end,
            calendarId: plannerCalendarId,
            reminders: reminders,
            extra: {
              'plan': PlanMark(
                kind: b.kind,
                itemId: habit.id,
                locked: b.locked,
                done: b.done,
                reason: b.reason,
              ).toJson(),
            },
          ),
        );
        continue;
      }
      final task = byId[b.itemId];
      if (task == null) continue;
      save.add(
        CalendarEvent(
          id: b.id,
          title: task.title,
          start: start,
          end: end,
          calendarId: plannerCalendarId,
          taskIds: [task.id],
          reminders: reminders,
          extra: {
            'plan': PlanMark(
              kind: b.kind,
              itemId: task.id,
              locked: b.locked,
              done: b.done,
              reason: b.reason,
              occurrence: task.occurrence,
            ).toJson(),
          },
        ),
      );
      continue;
    }
    // Done blocks are history: only the engine turning a passed block into
    // a done one changes them.
    final task = oldMark.isHabit ? null : byId[oldMark.itemId];
    final habit = oldMark.isHabit ? habitsById[oldMark.itemId] : null;
    final becameDone = b.done && !oldMark.done;
    if (oldMark.done && !becameDone) continue;
    final moved = old.start != start || old.end != end;
    final mark = oldMark.copyWith(
      locked: b.locked,
      done: b.done,
      reason: moved ? b.reason : oldMark.reason,
      occurrence: task == null ? oldMark.occurrence : task.occurrence,
    );
    final title = task?.title ?? habit?.title ?? old.title;
    final wanted = b.done ? old.reminders : reminders;
    if (!moved &&
        old.title == title &&
        mark.locked == oldMark.locked &&
        mark.done == oldMark.done &&
        mark.occurrence == oldMark.occurrence &&
        listEquals(old.reminders, wanted)) {
      continue;
    }
    save.add(
      old.copyWith(
        title: title,
        start: start,
        end: end,
        reminders: wanted,
        extra: {...old.extra, 'plan': mark.toJson()},
      ),
    );
  }

  return PlannerOutcome(
    result: result,
    save: save,
    delete: [
      for (final id in result.delete)
        if (stored.containsKey(id)) id,
    ],
    tasks: byId,
    habits: habitsById,
    at: now,
  );
}

/// The blocks of one task (and occurrence), soonest first, so a block can be
/// shown as "2 of 3". Keys are [PlanMark.group].
Map<String, List<CalendarEvent>> planGroups(Iterable<CalendarEvent> events) {
  final groups = <String, List<CalendarEvent>>{};
  for (final e in events) {
    final mark = PlanMark.of(e);
    if (mark != null) (groups[mark.group] ??= []).add(e);
  }
  for (final list in groups.values) {
    list.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }
  return groups;
}

/// The blocks of [task]'s current occurrence among [blocks].
List<CalendarEvent> planBlocksOf(PlannerTask task, Iterable<CalendarEvent> blocks) => [
  for (final b in blocks)
    if (PlanMark.of(b) case final m?
        when m.itemId == task.id && m.occurrence == task.occurrence)
      b,
];

/// Minutes of [task] that are done: the length of its done blocks.
int planDoneMinutes(PlannerTask task, Iterable<CalendarEvent> blocks) => [
  for (final b in planBlocksOf(task, blocks))
    if (PlanMark.of(b)!.done) b.duration.inMinutes,
].fold(0, (a, b) => a + b);
