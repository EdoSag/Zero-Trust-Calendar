import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/widget/my_day_widget.dart';

void main() {
  final now = DateTime(2026, 11, 11, 14, 30);
  String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  CalendarEvent event(
    String id,
    DateTime start,
    Duration length, {
    bool allDay = false,
  }) => CalendarEvent(
    id: id,
    title: id,
    start: start,
    end: start.add(length),
    allDay: allDay,
    color: 0xFF3B82F6,
  );

  List<CalendarEntry> entries(List<CalendarEvent> events) => buildEntries(
    range: DateRange(DateTime(2026, 11, 11), DateTime(2026, 11, 25)),
    events: events,
    calendars: const [ZtCalendarInfo.personal],
  );

  LinkedTask task(
    String title,
    DateTime due, {
    bool hasTime = false,
    bool done = false,
  }) => LinkedTask(
    id: title,
    title: title,
    due: due,
    completed: done,
    hasTime: hasTime,
  );

  MyDay build(
    List<CalendarEvent> events,
    List<LinkedTask> tasks, {
    bool titles = true,
  }) => myDay(
    entries: entries(events),
    tasks: tasks,
    now: now,
    showTitles: titles,
    formatTime: time,
    date: 'Wednesday, 11 November',
    l10n: lookupAppL10n(const Locale('en')),
  );

  test('the next timed event beats today\'s all-day one; past ones are '
      'skipped; tasks due today, timed first', () {
    final day = build(
      [
        event('Breakfast', DateTime(2026, 11, 11, 8), const Duration(hours: 1)),
        event(
          'Holiday',
          DateTime(2026, 11, 11),
          const Duration(days: 1),
          allDay: true,
        ),
        event('Dentist', DateTime(2026, 11, 11, 16), const Duration(hours: 1)),
      ],
      [
        task('Buy milk', DateTime(2026, 11, 11)),
        task('Send slides', DateTime(2026, 11, 11, 17), hasTime: true),
        task('Done already', DateTime(2026, 11, 11), done: true),
        task('Tomorrow', DateTime(2026, 11, 12)),
        task('Late 1', DateTime(2026, 11, 9)),
        task('Late 2', DateTime(2026, 11, 10, 9), hasTime: true),
      ],
    );
    expect(day.nextTitle, 'Dentist');
    expect(day.nextTime, '16:00');
    expect(day.nextColor, '#3B82F6');
    expect(day.tasks, [('17:00', 'Send slides'), ('', 'Buy milk')]);
    expect(day.overdue, 2);
    expect(day.date, 'Wednesday, 11 November');
  });

  test('an event going on now says Now; then all-day today, then tomorrow', () {
    expect(
      build([
        event('Call', DateTime(2026, 11, 11, 14), const Duration(hours: 1)),
      ], const []).nextTime,
      'Now',
    );
    final allDay = build([
      event(
        'Holiday',
        DateTime(2026, 11, 11),
        const Duration(days: 1),
        allDay: true,
      ),
      event('Gym', DateTime(2026, 11, 12, 7), const Duration(hours: 1)),
    ], const []);
    expect((allDay.nextTitle, allDay.nextTime), ('Holiday', 'all day'));
    final tomorrow = build([
      event('Gym', DateTime(2026, 11, 12, 7), const Duration(hours: 1)),
    ], const []);
    expect(tomorrow.nextTime, 'Tomorrow 7:00');
  });

  test('without "Show details" no title leaves the app', () {
    final day = build(
      [event('Dentist', DateTime(2026, 11, 11, 16), const Duration(hours: 1))],
      [task('Buy milk', DateTime(2026, 11, 11))],
      titles: false,
    );
    expect(day.nextTitle, 'Event');
    expect(day.tasks, [('', 'Task')]);
  });

  test('nothing coming up and nothing due', () {
    final day = build(const [], const []);
    expect(day.nextTitle, isNull);
    expect(day.nextTime, isNull);
    expect(day.tasks, isEmpty);
    expect(day.overdue, 0);
  });
}
