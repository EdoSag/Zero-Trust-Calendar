import 'package:flutter/foundation.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'planner_model.dart';

/// A routine the Planner keeps time for, such as "Lunch, every day, 30 min,
/// around 12:30, between 11:30 and 14:00" or "Gym, Mon Wed Fri, 1 h,
/// evenings". Kept in the Planner's settings item, so every device plans it
/// the same way.
///
/// Each day the habit gets the free time nearest its ideal time; if there
/// is no room it is shortened (when allowed) or skipped that day. Habits
/// are placed before tasks.
@immutable
class PlannerHabit {
  const PlannerHabit({
    required this.id,
    required this.title,
    required this.minutes,
    required this.days,
    required this.ideal,
    required this.earliest,
    required this.latest,
    this.minMinutes,
    this.hoursId,
    this.paused = false,
    this.extra = const {},
  });

  /// Id of the habit the focus time goal makes ([focusHabitOf]).
  static const focusId = 'focus';

  final String id;
  final String title;
  final int minutes;

  /// Shortest it may be cut to when there isn't room; null skips the day.
  final int? minMinutes;

  /// Weekdays it happens on ([DateTime.monday] .. [DateTime.sunday]).
  final Set<int> days;

  /// Minutes of the day: when it would ideally start, and the window it
  /// has to fit in.
  final int ideal;
  final int earliest;
  final int latest;

  /// Only inside these hours (work or personal); null: any time in the
  /// window.
  final String? hoursId;

  /// Kept, but not planned for now.
  final bool paused;

  /// Keys a newer version wrote; written back unchanged.
  final Map<String, Object?> extra;

  bool get isFocus => id == focusId;

  static const _known = {
    'id', 'title', 'minutes', 'minMinutes', 'days', 'ideal', 'earliest', 'latest',
    'hours', 'paused',
  };

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'minutes': minutes,
    if (minMinutes != null) 'minMinutes': minMinutes,
    'days': days.toList()..sort(),
    'ideal': ideal,
    'earliest': earliest,
    'latest': latest,
    if (hoursId != null) 'hours': hoursId,
    if (paused) 'paused': true,
  };

  /// A habit from the settings, or null when it can't be planned as stored.
  static PlannerHabit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = {for (final e in raw.entries) '${e.key}': e.value as Object?};
    final id = json['id'];
    if (id is! String || id.isEmpty || id == focusId) return null;
    int? minute(String key) {
      final v = json[key];
      return v is num && v >= 0 && v <= 24 * 60 ? v.toInt() : null;
    }

    final minutes = json['minutes'];
    final earliest = minute('earliest') ?? 0;
    final latest = minute('latest') ?? 24 * 60;
    if (minutes is! num || minutes < 5 || latest <= earliest) return null;
    final length = minutes.toInt().clamp(5, latest - earliest);
    final min = json['minMinutes'];
    final days = {
      if (json['days'] case final List list)
        for (final d in list)
          if (d is int && d >= 1 && d <= 7) d,
    };
    final ideal = (minute('ideal') ?? earliest).clamp(earliest, latest - length);
    final hours = json['hours'];
    return PlannerHabit(
      id: id,
      title: (json['title'] as String?)?.trim() ?? '',
      minutes: length,
      minMinutes: min is num && min >= 5 && min < length ? min.toInt() : null,
      days: days,
      ideal: ideal,
      earliest: earliest,
      latest: latest,
      hoursId: hours == workHoursId || hours == personalHoursId ? hours as String : null,
      paused: json['paused'] == true,
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  PlannerHabit copyWith({
    String? title,
    int? minutes,
    Object? minMinutes = _unset,
    Set<int>? days,
    int? ideal,
    int? earliest,
    int? latest,
    Object? hoursId = _unset,
    bool? paused,
  }) => PlannerHabit(
    id: id,
    title: title ?? this.title,
    minutes: minutes ?? this.minutes,
    minMinutes: identical(minMinutes, _unset) ? this.minMinutes : minMinutes as int?,
    days: days ?? this.days,
    ideal: ideal ?? this.ideal,
    earliest: earliest ?? this.earliest,
    latest: latest ?? this.latest,
    hoursId: identical(hoursId, _unset) ? this.hoursId : hoursId as String?,
    paused: paused ?? this.paused,
    extra: extra,
  );

  static const _unset = Object();

  /// The engine's habit. [order]: habits earlier in the list choose their
  /// time first.
  PlanHabit toPlan({int order = 0}) => PlanHabit(
    id: id,
    minutes: minutes,
    minMinutes: minMinutes,
    days: days,
    ideal: ideal,
    earliest: earliest,
    latest: latest,
    hoursId: hoursId,
    order: order,
  );

  /// Ready-made habits to start from.
  static PlannerHabit lunch(String id, String title) => PlannerHabit(
    id: id,
    title: title,
    minutes: 30,
    minMinutes: 15,
    days: const {1, 2, 3, 4, 5, 6, 7},
    ideal: 12 * 60 + 30,
    earliest: 11 * 60 + 30,
    latest: 14 * 60,
  );

  static PlannerHabit exercise(String id, String title, Set<int> days) => PlannerHabit(
    id: id,
    title: title,
    minutes: 60,
    days: days,
    ideal: 18 * 60,
    earliest: 6 * 60,
    latest: 22 * 60,
    hoursId: personalHoursId,
  );
}

/// The habit a weekly focus time goal makes: the goal split evenly over the
/// days that have work hours, in work hours, as early in the day as there
/// is room, and shortened to half (at least 30 minutes) rather than
/// dropped. Null when there is no goal or no work hours.
PlannerHabit? focusHabitOf(PlannerSettings settings) {
  final goal = settings.focusMinutesPerWeek;
  final work = settings.hours[workHoursId] ?? const <int, List<MinuteRange>>{};
  final days = {
    for (final e in work.entries)
      if (e.value.isNotEmpty) e.key,
  };
  if (goal <= 0 || days.isEmpty) return null;
  // Per day, on the planner's 15-minute grid.
  final perDay = ((goal / days.length) / 15).ceil() * 15;
  final starts = [for (final d in days) work[d]!.first.$1]..sort();
  return PlannerHabit(
    id: PlannerHabit.focusId,
    title: settings.focusTitle,
    minutes: perDay,
    minMinutes: perDay <= 30 ? null : (perDay ~/ 2 < 30 ? 30 : perDay ~/ 2),
    days: days,
    ideal: starts.first,
    earliest: 0,
    latest: 24 * 60,
    hoursId: workHoursId,
  );
}

/// Every habit the Planner plans now: the user's (not paused), then focus
/// time.
List<PlannerHabit> plannedHabitsOf(PlannerSettings settings) => [
  for (final h in settings.habits)
    if (!h.paused && h.days.isNotEmpty) h,
  ?focusHabitOf(settings),
];
