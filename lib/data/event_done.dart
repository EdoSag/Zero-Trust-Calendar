import '../model/calendar_event.dart';

/// "Mark as done" on an ordinary event: a tick the user sets, shown crossed
/// out. It is only a mark. Nothing else reads it, and the Planner's blocks
/// have their own (`plan.done`).
///
/// A single event keeps `done: true`; a repeating one keeps the starts of
/// the occurrences that are done, so ticking this week's leaves next week's
/// alone.
const _doneKey = 'done';
const _doneOccurrencesKey = 'doneOccurrences';

String _occurrenceKey(DateTime start) => start.toUtc().toIso8601String();

/// Whether the occurrence of [event] that starts at [occurrenceStart] is
/// marked done.
bool eventDone(CalendarEvent event, DateTime occurrenceStart) {
  if (!event.repeats) return event.extra[_doneKey] == true;
  final list = event.extra[_doneOccurrencesKey];
  return list is List && list.contains(_occurrenceKey(occurrenceStart));
}

/// [event] with the occurrence at [occurrenceStart] marked done, or not.
CalendarEvent withEventDone(
  CalendarEvent event,
  DateTime occurrenceStart,
  bool done,
) {
  final extra = {...event.extra};
  if (!event.repeats) {
    if (done) {
      extra[_doneKey] = true;
    } else {
      extra.remove(_doneKey);
    }
    return event.copyWith(extra: extra);
  }
  final key = _occurrenceKey(occurrenceStart);
  final old = extra[_doneOccurrencesKey];
  final list = <String>{
    if (old is List)
      for (final o in old)
        if (o is String) o,
  };
  if (done) {
    list.add(key);
  } else {
    list.remove(key);
  }
  if (list.isEmpty) {
    extra.remove(_doneOccurrencesKey);
  } else {
    // The newest 200: a daily event ticked for years stays small.
    final sorted = list.toList()..sort();
    extra[_doneOccurrencesKey] =
        sorted.length > 200 ? sorted.sublist(sorted.length - 200) : sorted;
  }
  return event.copyWith(extra: extra);
}
