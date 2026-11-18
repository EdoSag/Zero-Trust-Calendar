import 'package:flutter/foundation.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import '../model/calendar_event.dart';

/// The Planner: tasks from ZT Tasks fitted into the free time around
/// the calendar's events, by the `zt_scheduler` engine, on this device.
///
/// Its blocks are ordinary events in one calendar with the fixed id
/// [plannerCalendarId], so sync, reminders, the widgets and "Show on this
/// phone" handle them like any event. What makes an event a block is its
/// extra `plan` field ([PlanMark]).

/// The calendar the Planner's blocks live in. A fixed id, so two devices
/// turning the Planner on don't make two.
const plannerCalendarId = 'planner';

/// Violet, from the calendar palette.
const plannerColor = 0xFF8B5CF6;

/// The id of the work hours and of the personal hours.
const workHoursId = 'work';
const personalHoursId = 'personal';

/// The `plan` field of an event in the Planned calendar.
@immutable
class PlanMark {
  const PlanMark({
    required this.kind,
    required this.itemId,
    this.locked = false,
    this.done = false,
    this.reason,
    this.occurrence,
    this.extra = const {},
  });

  final PlanBlockKind kind;

  /// The ZT Tasks task (or, later, the habit) the block belongs to.
  final String itemId;

  /// The user put the block here: the Planner never moves it.
  final bool locked;
  final bool done;

  /// Why the block is where it is, as the engine said when it placed or
  /// last moved it. Not rewritten while the block stays put.
  final PlanReason? reason;

  /// For a repeating task: the due date (as ZT Tasks stores it) of the
  /// occurrence the block belongs to. ZT Tasks rolls a repeating task on to
  /// its next date when it is ticked off; blocks done for an earlier date
  /// then no longer count toward the task. Null for other tasks.
  final String? occurrence;

  /// Keys a newer version wrote; written back unchanged.
  final Map<String, Object?> extra;

  static const _known = {
    'type', 'taskId', 'habitId', 'locked', 'done', 'reason', 'occurrence',
  };

  /// The mark of [event], or null when it isn't a Planner block.
  static PlanMark? of(CalendarEvent? event) {
    if (event == null || event.calendarId != plannerCalendarId) return null;
    final raw = event.extra['plan'];
    if (raw is! Map) return null;
    final kind = raw['type'] == 'habit' ? PlanBlockKind.habit : PlanBlockKind.task;
    final id = raw[kind == PlanBlockKind.habit ? 'habitId' : 'taskId'];
    if (id is! String || id.isEmpty) return null;
    return PlanMark(
      kind: kind,
      itemId: id,
      locked: raw['locked'] == true,
      done: raw['done'] == true,
      reason: PlanReason.values.asNameMap()[raw['reason']],
      occurrence: raw['occurrence'] is String ? raw['occurrence'] as String : null,
      extra: {
        for (final e in raw.entries)
          if (e.key is String && !_known.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'type': kind.name,
    if (kind == PlanBlockKind.habit) 'habitId': itemId else 'taskId': itemId,
    'locked': locked,
    'done': done,
    if (reason != null) 'reason': reason!.name,
    if (occurrence != null) 'occurrence': occurrence,
  };

  static const _unset = Object();

  PlanMark copyWith({
    bool? locked,
    bool? done,
    PlanReason? reason,
    Object? occurrence = _unset,
  }) => PlanMark(
    kind: kind,
    itemId: itemId,
    locked: locked ?? this.locked,
    done: done ?? this.done,
    reason: reason ?? this.reason,
    occurrence: identical(occurrence, _unset) ? this.occurrence : occurrence as String?,
    extra: extra,
  );

  /// Blocks numbered together ("2 of 3"): one task, one occurrence.
  String get group => '$itemId|${occurrence ?? ''}';
}

/// Which tasks the Planner plans.
enum PlannerTasksChoice {
  /// Only tasks with Auto-schedule switched on.
  switchedOn,

  /// Every open task, except ones switched off by hand.
  all,
}

/// A range of minutes of the day, `[start, end)`.
typedef MinuteRange = (int start, int end);

/// The Planner's settings: one synced item, so every device plans the same
/// way.
@immutable
class PlannerSettings {
  const PlannerSettings({
    this.enabled = false,
    this.hours = const {},
    this.tasks = PlannerTasksChoice.switchedOn,
    this.defaultMinutes = 30,
    this.minChunk = 30,
    this.maxChunk = 120,
    this.breakAfterMeetings = 10,
    this.maxMinutesPerDay = 360,
    this.freeCalendarIds = const {},
    this.allDayBusy = false,
    this.pastBlocks = PastBlocks.askThenReplan,
    this.remindAtStart = true,
    this.askAtEnd = true,
    this.skips = const {},
    this.updatedAt,
    this.extra = const {},
  });

  /// The one settings item's id.
  static const itemId = 'planner-settings';

  /// Off until the setup is finished, and again after "Turn off".
  final bool enabled;

  /// When work and personal tasks may be planned: hours id, then weekday
  /// ([DateTime.monday] .. [DateTime.sunday]), then ranges in order.
  final Map<String, Map<int, List<MinuteRange>>> hours;
  final PlannerTasksChoice tasks;

  /// The length of a task that has none set.
  final int defaultMinutes;

  /// Shortest and longest block, in minutes.
  final int minChunk;
  final int maxChunk;
  final int breakAfterMeetings;

  /// Most planned task time in one day.
  final int maxMinutesPerDay;

  /// Calendars whose events don't keep the Planner away.
  final Set<String> freeCalendarIds;

  /// All-day events count as busy for the whole day.
  final bool allDayBusy;
  final PastBlocks pastBlocks;

  /// A notification when a block starts.
  final bool remindAtStart;

  /// A notification when a block ends, asking whether it was done.
  final bool askAtEnd;

  /// "Not now": task id to the time (local) before which the task isn't
  /// planned. Times that have passed mean nothing and are dropped the next
  /// time the settings are saved.
  final Map<String, DateTime> skips;

  /// [skips] without the ones that have passed at [now].
  Map<String, DateTime> skipsAfter(DateTime now) => {
    for (final e in skips.entries)
      if (e.value.isAfter(now)) e.key: e.value,
  };

  /// Last edit time from sync (not stored in the JSON).
  final DateTime? updatedAt;

  /// Keys a newer version wrote; written back unchanged.
  final Map<String, Object?> extra;

  static const _known = {
    'kind', '_v', 'enabled', 'hours', 'tasks', 'defaultMinutes', 'minChunk',
    'maxChunk', 'breakAfterMeetings', 'maxMinutesPerDay', 'freeCalendars',
    'allDayBusy', 'pastBlocks', 'remindAtStart', 'askAtEnd', 'skips',
  };

  /// Work hours 9:00 to 17:00 on the five work days, personal hours in the
  /// evenings of those days and during the day on the other two.
  /// [weekStart] is the first day of the week ([DateTime.sunday] in Israel,
  /// [DateTime.monday] in most places); the work week is its first five
  /// days.
  static Map<String, Map<int, List<MinuteRange>>> defaultHours(int weekStart) {
    final workDays = {for (var i = 0; i < 5; i++) (weekStart - 1 + i) % 7 + 1};
    return {
      workHoursId: {
        for (final d in workDays) d: const [(9 * 60, 17 * 60)],
      },
      personalHoursId: {
        for (var d = 1; d <= 7; d++)
          d: workDays.contains(d)
              ? const [(18 * 60, 21 * 60)]
              : const [(10 * 60, 18 * 60)],
      },
    };
  }

  List<MinuteRange> rangesOn(String hoursId, int weekday) =>
      hours[hoursId]?[weekday] ?? const [];

  /// Minutes of [hoursId] in a week.
  int weeklyMinutes(String hoursId) => [
    for (final list in (hours[hoursId] ?? const {}).values)
      for (final (s, e) in list) e - s,
  ].fold(0, (a, b) => a + b);

  PlannerSettings copyWith({
    bool? enabled,
    Map<String, Map<int, List<MinuteRange>>>? hours,
    PlannerTasksChoice? tasks,
    int? defaultMinutes,
    int? minChunk,
    int? maxChunk,
    int? breakAfterMeetings,
    int? maxMinutesPerDay,
    Set<String>? freeCalendarIds,
    bool? allDayBusy,
    PastBlocks? pastBlocks,
    bool? remindAtStart,
    bool? askAtEnd,
    Map<String, DateTime>? skips,
  }) => PlannerSettings(
    enabled: enabled ?? this.enabled,
    hours: hours ?? this.hours,
    tasks: tasks ?? this.tasks,
    defaultMinutes: defaultMinutes ?? this.defaultMinutes,
    minChunk: minChunk ?? this.minChunk,
    maxChunk: maxChunk ?? this.maxChunk,
    breakAfterMeetings: breakAfterMeetings ?? this.breakAfterMeetings,
    maxMinutesPerDay: maxMinutesPerDay ?? this.maxMinutesPerDay,
    freeCalendarIds: freeCalendarIds ?? this.freeCalendarIds,
    allDayBusy: allDayBusy ?? this.allDayBusy,
    pastBlocks: pastBlocks ?? this.pastBlocks,
    remindAtStart: remindAtStart ?? this.remindAtStart,
    askAtEnd: askAtEnd ?? this.askAtEnd,
    skips: skips ?? this.skips,
    updatedAt: updatedAt,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'enabled': enabled,
    'hours': {
      for (final h in hours.entries)
        h.key: {
          for (final d in h.value.entries)
            if (d.value.isNotEmpty)
              '${d.key}': [
                for (final (s, e) in d.value) [s, e],
              ],
        },
    },
    'tasks': tasks.name,
    'defaultMinutes': defaultMinutes,
    'minChunk': minChunk,
    'maxChunk': maxChunk,
    'breakAfterMeetings': breakAfterMeetings,
    'maxMinutesPerDay': maxMinutesPerDay,
    'freeCalendars': freeCalendarIds.toList()..sort(),
    'allDayBusy': allDayBusy,
    'pastBlocks': pastBlocks.name,
    'remindAtStart': remindAtStart,
    'askAtEnd': askAtEnd,
    if (skips.isNotEmpty)
      'skips': {
        for (final id in skips.keys.toList()..sort()) id: _wallIso(skips[id]!),
      },
  };

  /// A local time as written in the settings: the date and time of day with
  /// no zone, so "not before tomorrow" means the same on every device.
  static String _wallIso(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute).toIso8601String();

  static PlannerSettings fromJson(Map<String, Object?> json, [DateTime? updatedAt]) {
    const d = PlannerSettings();
    int minutes(String key, int fallback, {int min = 0, int max = 24 * 60}) {
      final v = json[key];
      return v is num ? v.toInt().clamp(min, max) : fallback;
    }

    final hours = <String, Map<int, List<MinuteRange>>>{};
    if (json['hours'] case final Map raw) {
      for (final h in raw.entries) {
        if (h.key is! String || h.value is! Map) continue;
        final days = <int, List<MinuteRange>>{};
        for (final day in (h.value as Map).entries) {
          final weekday = int.tryParse('${day.key}');
          if (weekday == null || weekday < 1 || weekday > 7) continue;
          final ranges = <MinuteRange>[
            if (day.value case final List list)
              for (final r in list)
                if (r is List && r.length == 2 && r[0] is num && r[1] is num)
                  if ((r[0] as num) >= 0 &&
                      (r[1] as num) <= 24 * 60 &&
                      (r[0] as num) < (r[1] as num))
                    ((r[0] as num).toInt(), (r[1] as num).toInt()),
          ]..sort((a, b) => a.$1.compareTo(b.$1));
          if (ranges.isNotEmpty) days[weekday] = ranges;
        }
        hours[h.key as String] = days;
      }
    }
    final minChunk = minutes('minChunk', d.minChunk, min: 15, max: 8 * 60);
    return PlannerSettings(
      enabled: json['enabled'] == true,
      hours: hours,
      tasks: PlannerTasksChoice.values.asNameMap()[json['tasks']] ?? d.tasks,
      defaultMinutes: minutes('defaultMinutes', d.defaultMinutes, min: 5, max: 8 * 60),
      minChunk: minChunk,
      maxChunk: minutes('maxChunk', d.maxChunk, min: minChunk, max: 8 * 60),
      breakAfterMeetings: minutes('breakAfterMeetings', d.breakAfterMeetings, max: 120),
      maxMinutesPerDay: minutes('maxMinutesPerDay', d.maxMinutesPerDay, min: 30),
      freeCalendarIds: {
        if (json['freeCalendars'] case final List list)
          for (final id in list)
            if (id is String) id,
      },
      allDayBusy: json['allDayBusy'] == true,
      pastBlocks: PastBlocks.values.asNameMap()[json['pastBlocks']] ?? d.pastBlocks,
      remindAtStart: json['remindAtStart'] != false,
      askAtEnd: json['askAtEnd'] != false,
      skips: {
        if (json['skips'] case final Map raw)
          for (final e in raw.entries)
            if (e.key is String && e.value is String)
              if (DateTime.tryParse(e.value as String) case final t?)
                e.key as String: DateTime(t.year, t.month, t.day, t.hour, t.minute),
      },
      updatedAt: updatedAt,
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }
}

/// What the Planner needs of a ZT Tasks task: the fields ZT Tasks already
/// has (title, priority, dates) and the optional `plan*` fields.
@immutable
class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.title,
    this.minutes,
    this.priority = PlanPriority.medium,
    this.due,
    this.dueHasTime = false,
    this.notBefore,
    this.minChunk,
    this.maxChunk,
    this.auto,
    this.hoursId = workHoursId,
    this.completed = false,
    this.repeats = false,
    this.dueRaw,
    this.createdAt = '',
  });

  final String id;
  final String title;

  /// `planMinutes`: how long the task takes, or null when not set (the
  /// Planner then uses the default and calls it a guess).
  final int? minutes;
  final PlanPriority priority;

  /// When it has to be finished. A due date without a time means the end of
  /// that day.
  final DateTime? due;
  final bool dueHasTime;

  /// The task's start date: not planned before it.
  final DateTime? notBefore;
  final int? minChunk;
  final int? maxChunk;

  /// `planAuto`: true switched on, false switched off, null never chosen.
  final bool? auto;
  final String hoursId;
  final bool completed;
  final bool repeats;

  /// The due date exactly as ZT Tasks stores it.
  final String? dueRaw;

  /// The occurrence a repeating task is on now ([PlanMark.occurrence]).
  String? get occurrence => repeats ? dueRaw : null;

  /// As stored: only used to keep tasks in a steady order.
  final String createdAt;

  /// Whether the Planner plans this task under [choice].
  bool plannedUnder(PlannerTasksChoice choice) =>
      !completed &&
      (choice == PlannerTasksChoice.all ? auto != false : auto == true);

  /// The same task with Auto-schedule switched [on] or off.
  PlannerTask withAuto(bool on) => PlannerTask(
    id: id,
    title: title,
    minutes: minutes,
    priority: priority,
    due: due,
    dueHasTime: dueHasTime,
    notBefore: notBefore,
    minChunk: minChunk,
    maxChunk: maxChunk,
    auto: on,
    hoursId: hoursId,
    completed: completed,
    repeats: repeats,
    dueRaw: dueRaw,
    createdAt: createdAt,
  );

  /// The moment the task has to be finished by, or null.
  DateTime? get dueBy {
    final d = due;
    if (d == null) return null;
    return dueHasTime ? d : DateTime(d.year, d.month, d.day + 1);
  }

  /// A live task's JSON, or null for lists, sections, archived and deleted
  /// tasks. Tasks are ZT Tasks' default collection: items without a `kind`.
  static PlannerTask? fromItem(String id, Map<String, Object?>? json) {
    if (json == null || json['kind'] != null) return null;
    if (json['deletedAt'] != null || json['isArchived'] == true) return null;
    DateTime? date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    int? minutes(Object? raw) =>
        raw is num && raw > 0 ? raw.toInt().clamp(5, 7 * 24 * 60) : null;
    final due = date(json['dueDate']);
    final title = (json['title'] as String?)?.trim() ?? '';
    return PlannerTask(
      id: id,
      title: title,
      minutes: minutes(json['planMinutes']),
      priority:
          PlanPriority.values.asNameMap()[json['priority']] ?? PlanPriority.medium,
      due: due,
      dueHasTime: due != null &&
          !(due.hour == 0 && due.minute == 0) &&
          !(due.hour == 23 && due.minute == 59),
      notBefore: date(json['startDate']),
      minChunk: minutes(json['planMinChunk']),
      maxChunk: minutes(json['planMaxChunk']),
      auto: json['planAuto'] is bool ? json['planAuto'] as bool : null,
      hoursId: json['planHours'] == personalHoursId ? personalHoursId : workHoursId,
      completed: json['isCompleted'] == true,
      repeats: json['recurrence'] != null,
      dueRaw: json['dueDate'] is String ? json['dueDate'] as String : null,
      createdAt: json['createdAt'] is String ? json['createdAt'] as String : '',
    );
  }

  /// [json] (a stored task) with the Planner's fields changed and every
  /// other field as stored. A null value in [changes] removes the field.
  static Map<String, Object?> withPlanFields(
    Map<String, Object?> json,
    Map<String, Object?> changes,
    DateTime now,
  ) {
    const allowed = {'planMinutes', 'planMinChunk', 'planMaxChunk', 'planAuto', 'planHours'};
    final out = {...json};
    for (final e in changes.entries) {
      if (!allowed.contains(e.key)) {
        throw ArgumentError('Calendar only writes plan fields, not ${e.key}');
      }
      if (e.value == null) {
        out.remove(e.key);
      } else {
        out[e.key] = e.value;
      }
    }
    out['updatedAt'] = now.toIso8601String();
    return out;
  }

  /// [json] (a stored task) due on the day of [day], at the time of day it
  /// was due before (midnight, ZT Tasks' "no time", when it had none), with
  /// every other field as stored.
  static Map<String, Object?> withDueDay(
    Map<String, Object?> json,
    DateTime day,
    DateTime now,
  ) {
    final old = json['dueDate'] is String
        ? DateTime.tryParse(json['dueDate'] as String)?.toLocal()
        : null;
    final due = DateTime(
      day.year,
      day.month,
      day.day,
      old?.hour ?? 0,
      old?.minute ?? 0,
    );
    return {
      ...json,
      'dueDate': due.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
  }
}
