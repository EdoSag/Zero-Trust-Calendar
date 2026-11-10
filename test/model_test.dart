import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/data/event_actions.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';
import 'package:zerotrust_calendar/util/day_layout.dart';
import 'package:zerotrust_calendar/widget/up_next_widget.dart';

CalendarEvent ev(
  String id,
  DateTime start,
  DateTime end, {
  String? rrule,
  bool allDay = false,
  List<int> reminders = const [],
}) => CalendarEvent(
  id: id,
  title: 'Event $id',
  start: start,
  end: end,
  rrule: rrule,
  allDay: allDay,
  reminders: reminders,
);

void main() {
  group('CalendarEvent JSON', () {
    test('timed events round-trip as UTC, keeping unknown keys', () {
      final e = ev(
        'a',
        DateTime(2026, 11, 10, 9, 30),
        DateTime(2026, 11, 10, 10, 30),
        rrule: 'FREQ=WEEKLY',
        reminders: [10],
      ).copyWith(exceptions: {DateTime(2026, 11, 17, 9, 30)}, noteIds: ['n1']);
      final json = e.toJson();
      expect(json['start'], endsWith('Z'));
      json['futureField'] = 42;
      final back = CalendarEvent.fromJson('a', json, null)!;
      expect(back.start, e.start);
      expect(back.end, e.end);
      expect(back.exceptions, e.exceptions);
      expect(back.noteIds, ['n1']);
      expect(back.reminders, [10]);
      expect(back.toJson()['futureField'], 42);
    });

    test('all-day events keep plain dates', () {
      final e = ev('b', DateTime(2026, 12, 24), DateTime(2026, 12, 26), allDay: true);
      final json = e.toJson();
      expect(json['start'], '2026-12-24');
      expect(json['end'], '2026-12-26');
      final back = CalendarEvent.fromJson('b', json, null)!;
      expect(back.start, DateTime(2026, 12, 24));
      expect(back.allDay, isTrue);
    });

    test('occurrences overlap the range', () {
      final e = ev('c', DateTime(2026, 11, 9, 23), DateTime(2026, 11, 10, 1), rrule: 'FREQ=DAILY');
      final occ = e.occurrencesBetween(DateTime(2026, 11, 10), DateTime(2026, 11, 11));
      expect(occ.map((o) => o.$1), [DateTime(2026, 11, 9, 23), DateTime(2026, 11, 10, 23)]);
    });
  });

  group('series edits', () {
    final series = ev('s', DateTime(2026, 11, 2, 9), DateTime(2026, 11, 2, 10), rrule: 'FREQ=WEEKLY');
    final occ = DateTime(2026, 11, 16, 9);

    test('this event makes an exception', () {
      final change = SeriesEdits.edit(
        series: series,
        occurrence: occ,
        edited: series.copyWith(title: 'Moved', start: DateTime(2026, 11, 16, 11), end: DateTime(2026, 11, 16, 12)),
        scope: SeriesScope.thisEvent,
      );
      expect(change.save.first.exceptions, {occ});
      final ex = change.save.last;
      expect(ex.seriesId, 's');
      expect(ex.originalStart, occ);
      expect(ex.rrule, isNull);
      expect(ex.start, DateTime(2026, 11, 16, 11));
    });

    test('this and following splits the series', () {
      final change = SeriesEdits.edit(
        series: series,
        occurrence: occ,
        edited: series.copyWith(title: 'New', start: occ, end: occ.add(const Duration(hours: 1))),
        scope: SeriesScope.thisAndFollowing,
      );
      final ended = change.save.first;
      expect(
        ended.recurrence!.occurrences(ended.start).toList(),
        [DateTime(2026, 11, 2, 9), DateTime(2026, 11, 9, 9)],
      );
      final next = change.save.last;
      expect(next.id, isNot('s'));
      expect(next.start, occ);
      expect(next.title, 'New');
    });

    test('this and following keeps later changed occurrences', () {
      final later = ev('x', DateTime(2026, 11, 23, 14), DateTime(2026, 11, 23, 15))
          .copyWith(seriesId: 's', originalStart: DateTime(2026, 11, 23, 9));
      final earlier = ev('y', DateTime(2026, 11, 9, 14), DateTime(2026, 11, 9, 15))
          .copyWith(seriesId: 's', originalStart: DateTime(2026, 11, 9, 9));
      final change = SeriesEdits.edit(
        series: series.copyWith(exceptions: {DateTime(2026, 11, 9, 9), DateTime(2026, 11, 23, 9)}),
        occurrence: occ,
        edited: series.copyWith(title: 'New', start: occ, end: occ.add(const Duration(hours: 1))),
        scope: SeriesScope.thisAndFollowing,
        exceptions: [earlier, later],
      );
      expect(change.delete, isEmpty);
      final next = change.save[1];
      final moved = change.save.singleWhere((e) => e.id == 'x');
      expect(moved.seriesId, next.id);
      expect(moved.start, DateTime(2026, 11, 23, 14));
      expect(next.exceptions, {DateTime(2026, 11, 23, 9)});
      expect(change.save.any((e) => e.id == 'y'), isFalse);
    });

    test('all events moves the series by the same amount', () {
      final change = SeriesEdits.edit(
        series: series,
        occurrence: occ,
        edited: series.copyWith(start: DateTime(2026, 11, 16, 10), end: DateTime(2026, 11, 16, 11)),
        scope: SeriesScope.allEvents,
      );
      expect(change.save.single.id, 's');
      expect(change.save.single.start, DateTime(2026, 11, 2, 10));
    });

    test('deleting one occurrence adds an exception', () {
      final change = SeriesEdits.delete(series: series, occurrence: occ, scope: SeriesScope.thisEvent);
      expect(change.save.single.exceptions, {occ});
      final all = SeriesEdits.delete(series: series, occurrence: occ, scope: SeriesScope.allEvents);
      expect(all.delete, ['s']);
    });
  });

  test('entries include tasks and birthdays, not hidden calendars', () {
    final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final entries = buildEntries(
      range: range,
      events: [
        ev('a', DateTime(2026, 11, 10, 9), DateTime(2026, 11, 10, 10)),
        ev('h', DateTime(2026, 11, 11, 9), DateTime(2026, 11, 11, 10)).copyWith(calendarId: 'work'),
      ],
      calendars: const [
        ZtCalendarInfo.personal,
        ZtCalendarInfo(id: 'work', name: 'Work', color: 1, hidden: true),
      ],
      tasks: [LinkedTask.fromItem('t', {'title': 'Pay rent', 'dueDate': '2026-11-15T00:00:00.000'})!],
      contacts: [
        LinkedContact.fromItem('c', {
          'kind': 'contact',
          'displayName': 'Ada',
          'birthdays': ['1990-11-20'],
        })!,
      ],
    );
    expect(entries.map((e) => e.title), ["Pay rent", "Ada's birthday", 'Event a']);
    expect(entries.first.allDay, isTrue);
  });

  test('linked notes skip notebooks and trash', () {
    final now = DateTime(2026);
    expect(LinkedNote.fromItem('1', {'title': 'Agenda', 'body': ''}, now)?.displayTitle, 'Agenda');
    expect(LinkedNote.fromItem('2', {'kind': 'notebook', 'name': 'x'}, now), isNull);
    expect(LinkedNote.fromItem('3', {'title': 'x', 'trashedAt': '2026-01-01'}, now), isNull);
    expect(LinkedContact.parseBirthday('--04-12'), (4, 12, null));
    expect(LinkedContact.parseBirthday('1604-04-12'), (4, 12, null));
  });

  test('reminders for repeating and all-day events', () {
    final now = DateTime(2026, 11, 10, 8);
    final reminders = remindersFor(
      [
        ev('w', DateTime(2026, 11, 3, 9), DateTime(2026, 11, 3, 10), rrule: 'FREQ=WEEKLY', reminders: [10]),
        ev('d', DateTime(2026, 11, 10), DateTime(2026, 11, 11), allDay: true, reminders: [0]),
      ],
      now: now,
      horizon: const Duration(days: 8),
      bodyFor: (_, _) => '',
    );
    expect(reminders.map((r) => (r.eventId, r.at)), [
      ('w', DateTime(2026, 11, 10, 8, 50)),
      ('d', DateTime(2026, 11, 10, 9)),
      ('w', DateTime(2026, 11, 17, 8, 50)),
    ]);
    final hidden = remindersFor(
      [ev('w', DateTime(2026, 11, 10, 9), DateTime(2026, 11, 10, 10), reminders: [10])],
      now: now,
      showTitles: false,
      bodyFor: (_, _) => '',
    );
    expect(hidden.single.title, 'Event');
    expect(hidden.single.notificationId, hidden.single.notificationId);
  });

  test('overlapping events share the width', () {
    DateTime t(int h, [int m = 0]) => DateTime(2026, 11, 10, h, m);
    final p = layoutDay([
      ('a', t(9), t(10)),
      ('b', t(9, 30), t(11)),
      ('c', t(10), t(10, 30)),
      ('d', t(12), t(13)),
    ]);
    final byItem = {for (final x in p) x.item: x};
    expect(byItem['a']!.columns, 2);
    expect(byItem['b']!.column, 1);
    expect(byItem['c']!.column, 0);
    expect(byItem['d']!.columns, 1);
  });

  test('widget rows hide titles unless allowed', () {
    final now = DateTime(2026, 11, 10, 12);
    final entries = buildEntries(
      range: DateRange(DateTime(2026, 11, 10), DateTime(2026, 11, 20)),
      events: [
        ev('past', DateTime(2026, 11, 10, 8), DateTime(2026, 11, 10, 9)),
        ev('next', DateTime(2026, 11, 10, 15), DateTime(2026, 11, 10, 16)),
        ev('tmrw', DateTime(2026, 11, 11, 9), DateTime(2026, 11, 11, 10)),
      ],
      calendars: const [ZtCalendarInfo.personal],
    );
    final rows = upNextRows(entries, now: now, showTitles: false, formatTime: (t) => '${t.hour}:00');
    expect(rows.map((r) => (r.time, r.title)), [('15:00', 'Event'), ('Tomorrow 9:00', 'Event')]);
    final titled = upNextRows(entries, now: now, showTitles: true, formatTime: (t) => '${t.hour}:00');
    expect(titled.first.title, 'Event next');
  });
}
