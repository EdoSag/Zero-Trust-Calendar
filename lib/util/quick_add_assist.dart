import 'package:zt_assist/zt_assist.dart';

import 'quick_add.dart';

/// Puts ZT Assist's reading of a typed event together with the app's own.
///
/// The app's own reading ([own], from [parseQuickAdd]) counts days exactly
/// but only knows the phrases it was taught. ZT Assist ([read]) understands
/// free wording ("half past four in the afternoon", "remind me an hour
/// before") but is a small model that can slip. So:
///  * the day is the app's own where the text named one, else ZT Assist's;
///  * the title, the time, the length and the place are ZT Assist's where
///    it has one, else the app's own;
///  * the reminder comes from ZT Assist only;
///  * a repeat stays the app's own.
///
/// The result is shown in the sheet before the event is added.
QuickAdd mergeAssistReading(
  QuickAdd own,
  ZtAssistQuickAdd read, {
  required DateTime now,
  int defaultMinutes = 60,
}) {
  final title = read.title ?? own.title;
  final location = read.place ?? own.location;
  final ownDay = DateTime(own.start.year, own.start.month, own.start.day);
  final hour = read.hour ?? (own.hasTime ? own.start.hour : null);
  final minute = read.minute ?? (own.hasTime ? own.start.minute : null);
  final day = own.hasDate ? ownDay : read.day;

  if (hour == null || minute == null) {
    // No time from either: an all-day event, on the day either one named.
    final on = day ?? ownDay;
    return QuickAdd(
      title: title,
      start: on,
      end: DateTime(on.year, on.month, on.day + 1),
      allDay: true,
      hasDate: day != null,
      hasTime: false,
      location: location,
      rule: own.rule,
    );
  }

  DateTime start;
  if (day != null) {
    start = DateTime(day.year, day.month, day.day, hour, minute);
  } else {
    // Only a time: today, or tomorrow once that time has passed. The same
    // rule as the app's own reading.
    start = DateTime(now.year, now.month, now.day, hour, minute);
    if (start.isBefore(now)) start = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  final ownLength = own.hasTime && own.hasLength ? own.end.difference(own.start).inMinutes : null;
  final length = read.lengthMinutes ?? ownLength;
  return QuickAdd(
    title: title,
    start: start,
    end: start.add(Duration(minutes: length ?? defaultMinutes)),
    allDay: false,
    hasDate: day != null,
    hasTime: true,
    hasLength: length != null,
    // Counted back from the start, so only with a time.
    remindMinutesBefore: read.remindMinutesBefore,
    location: location,
    rule: own.rule,
  );
}
