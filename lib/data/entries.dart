import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/calendar_settings.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import 'calendar_store.dart';
import 'linked_apps.dart';
import 'subscriptions.dart';

enum EntryKind { event, task, birthday }

/// One thing on the calendar: an event occurrence, a ZT Tasks task due that
/// day, or a ZT Contacts birthday.
@immutable
class CalendarEntry {
  const CalendarEntry({
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.color,
    this.event,
    this.task,
    this.contact,
  });

  final EntryKind kind;
  final String title;
  final DateTime start;

  /// Exclusive. For all-day entries, the midnight after the last day.
  final DateTime end;
  final bool allDay;
  final int color;

  /// The event (or series) this is an occurrence of.
  final CalendarEvent? event;
  final LinkedTask? task;
  final LinkedContact? contact;

  bool get isOccurrenceOfSeries => event?.repeats ?? false;

  /// Whether this entry shows on [day] (local midnight).
  bool coversDay(DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    if (start == end) return !start.isBefore(day) && start.isBefore(next);
    return start.isBefore(next) && end.isAfter(day);
  }

  /// Longer than one day, or all-day: drawn in the all-day strip.
  bool get spansDays =>
      allDay ||
      DateTime(start.year, start.month, start.day + 1).isBefore(end);

  static int compare(CalendarEntry a, CalendarEntry b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final s = a.start.compareTo(b.start);
    if (s != 0) return s;
    final e = b.end.compareTo(a.end); // Longer first.
    if (e != 0) return e;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}

/// A local-time range `[from, to)`.
@immutable
class DateRange {
  const DateRange(this.from, this.to);
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

const taskColor = 0xFF06B6D4; // ZT Tasks cyan
const birthdayColor = 0xFFEC4899; // ZT Contacts pink

/// Builds the entries in [range] from events, calendars, tasks and contacts.
/// Pure, so it is tested without the app.
List<CalendarEntry> buildEntries({
  required DateRange range,
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  List<LinkedTask> tasks = const [],
  List<LinkedContact> contacts = const [],
}) {
  final byId = {for (final c in calendars) c.id: c};
  final out = <CalendarEntry>[];
  for (final e in events) {
    final cal = byId[e.calendarId] ?? ZtCalendarInfo.personal;
    if (cal.hidden) continue;
    for (final (s, end) in e.occurrencesBetween(range.from, range.to)) {
      out.add(
        CalendarEntry(
          kind: EntryKind.event,
          title: e.title.trim().isEmpty ? '(No title)' : e.title.trim(),
          start: s,
          end: end,
          allDay: e.allDay,
          color: e.color ?? cal.color,
          event: e,
        ),
      );
    }
  }
  for (final t in tasks) {
    final day = DateTime(t.due.year, t.due.month, t.due.day);
    final start = t.hasTime ? t.due : day;
    final end = t.hasTime
        ? t.due.add(const Duration(minutes: 30))
        : DateTime(day.year, day.month, day.day + 1);
    if (start.isBefore(range.to) && end.isAfter(range.from)) {
      out.add(
        CalendarEntry(
          kind: EntryKind.task,
          title: t.title,
          start: start,
          end: end,
          allDay: !t.hasTime,
          color: taskColor,
          task: t,
        ),
      );
    }
  }
  for (final c in contacts) {
    for (final (month, day, _) in c.birthdays) {
      for (var y = range.from.year; y <= range.to.year; y++) {
        final d = DateTime(y, month, day);
        if (d.month != month) continue; // Feb 29 in other years.
        final next = DateTime(y, month, day + 1);
        if (d.isBefore(range.to) && next.isAfter(range.from)) {
          out.add(
            CalendarEntry(
              kind: EntryKind.birthday,
              title: "${c.name}'s birthday",
              start: d,
              end: next,
              allDay: true,
              color: birthdayColor,
              contact: c,
            ),
          );
        }
      }
    }
  }
  out.sort(CalendarEntry.compare);
  return out;
}

/// The entries in a range, kept up to date.
final entriesProvider = Provider.family<AsyncValue<List<CalendarEntry>>, DateRange>((
  ref,
  range,
) {
  final events = ref.watch(allEventsProvider);
  final calendars = ref.watch(calendarsProvider);
  final settings = ref.watch(calendarSettingsProvider);
  final tasks = settings.showTasks
      ? ref.watch(linkedTasksProvider).value ?? const <LinkedTask>[]
      : const <LinkedTask>[];
  final contacts = settings.showBirthdays
      ? ref.watch(linkedContactsProvider).value ?? const <LinkedContact>[]
      : const <LinkedContact>[];
  if (events.hasError) return AsyncError(events.error!, events.stackTrace!);
  final list = events.value;
  if (list == null) return const AsyncLoading();
  return AsyncData(
    buildEntries(
      range: range,
      events: list,
      calendars: calendars.value ?? const [ZtCalendarInfo.personal],
      tasks: settings.showCompletedTasks
          ? tasks
          : tasks.where((t) => !t.completed).toList(),
      contacts: contacts,
    ),
  );
});
