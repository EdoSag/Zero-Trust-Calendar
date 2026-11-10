import '../model/calendar_event.dart';

/// What "Show on this phone" copies into Android's calendar: for each
/// calendar turned on, its occurrences from a month ago to a year ahead,
/// with title, times and location only (no description, guests or notes).
/// All-day events are UTC midnights, as Android stores them. Pure, so it is
/// tested without a phone.
List<Map<String, Object?>> phoneCalendarPayload({
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required Set<String> enabledIds,
  required DateTime now,
  int maxPerCalendar = 3000,
}) {
  final from = DateTime(now.year, now.month - 1, now.day);
  final to = DateTime(now.year + 1, now.month, now.day);
  int utcMidnight(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  return [
    for (final c in calendars)
      if (enabledIds.contains(c.id))
        {
          'id': c.id,
          'name': c.name,
          'color': c.color,
          'events': () {
            final out = <Map<String, Object?>>[];
            for (final e in events) {
              if (e.calendarId != c.id) continue;
              for (final (s, end) in e.occurrencesBetween(from, to)) {
                out.add({
                  'title': e.title.trim().isEmpty ? '(No title)' : e.title.trim(),
                  'location': e.location,
                  'allDay': e.allDay,
                  'start': e.allDay ? utcMidnight(s) : s.millisecondsSinceEpoch,
                  'end': e.allDay ? utcMidnight(end) : end.millisecondsSinceEpoch,
                });
              }
            }
            out.sort((a, b) => (a['start']! as int).compareTo(b['start']! as int));
            return out.length > maxPerCalendar ? out.sublist(0, maxPerCalendar) : out;
          }(),
        },
  ];
}
