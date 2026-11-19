import '../model/calendar_event.dart';
import 'planner_model.dart';

/// Hours searched when "Any time" is picked: 8:00 to 22:00.
const anyTimeRange = (8 * 60, 22 * 60);

/// Free times for one task ("Find a time", free plan): the earliest time
/// that fits on each day, soonest first, at most [count].
///
/// Busy: timed events of every calendar that counts (as the Planner sees
/// them, with the break after meetings), all-day ones when the settings
/// say so, and the Planner's own blocks that aren't done. Times are on the
/// Planner's 15-minute grid and start at least 30 minutes from [now].
///
/// [hoursId] picks work or personal hours from [settings]; null searches
/// [anyTimeRange] every day.
List<(DateTime, DateTime)> findTaskTimes({
  required DateTime now,
  required int minutes,
  required PlannerSettings settings,
  required String? hoursId,
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  int days = 14,
  int count = 6,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final until = DateTime(today.year, today.month, today.day + days + 1);
  final skip = {
    ...settings.freeCalendarIds,
    for (final c in calendars)
      if (c.hidden) c.id,
  };
  final busy = <(DateTime, DateTime)>[];
  for (final e in events) {
    final mark = PlanMark.of(e);
    if (mark != null) {
      if (!mark.done && !e.allDay && e.end.isAfter(e.start)) busy.add((e.start, e.end));
      continue;
    }
    if (skip.contains(e.calendarId) || (e.allDay && !settings.allDayBusy)) continue;
    final gap = e.allDay ? Duration.zero : Duration(minutes: settings.breakAfterMeetings);
    for (final (s, end) in e.occurrencesBetween(today, until)) {
      if (end.isAfter(s)) busy.add((s, end.add(gap)));
    }
  }

  bool free(DateTime s, DateTime e) =>
      !busy.any((b) => s.isBefore(b.$2) && b.$1.isBefore(e));

  // At least 30 minutes from now, on the 15-minute grid.
  final soon = now.add(const Duration(minutes: 30));
  final found = <(DateTime, DateTime)>[];
  for (var i = 0; i <= days && found.length < count; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final ranges = hoursId == null
        ? const [anyTimeRange]
        : settings.rangesOn(hoursId, day.weekday);
    search:
    for (final (from, to) in ranges) {
      for (var m = (from + 14) ~/ 15 * 15; m + minutes <= to; m += 15) {
        final s = DateTime(day.year, day.month, day.day, 0, m);
        if (s.isBefore(soon)) continue;
        final e = s.add(Duration(minutes: minutes));
        if (free(s, e)) {
          found.add((s, e));
          break search;
        }
      }
    }
  }
  return found;
}
