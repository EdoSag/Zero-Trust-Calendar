import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/widget/month_agenda_widgets.dart';

void main() {
  final now = DateTime(2026, 11, 14, 9);
  final en = lookupAppL10n(const Locale('en'));
  final he = lookupAppL10n(const Locale('he'));
  String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  CalendarEvent event(String id, DateTime start, Duration length, {bool allDay = false, int color = 0xFF3B82F6}) =>
      CalendarEvent(id: 'id-${id.length}-${start.hour}', title: id, start: start, end: start.add(length), allDay: allDay, color: color);

  List<CalendarEntry> entries(List<CalendarEvent> events, DateRange range) =>
      buildEntries(range: range, events: events, calendars: const [ZtCalendarInfo.personal], l10n: en);

  group('month grid dots', () {
    test('covers last month to two months ahead', () {
      final range = monthWidgetRange(now);
      expect(range.from, DateTime(2026, 10, 1));
      expect(range.to, DateTime(2027, 2, 1));
    });

    test('a dot per day with events, one colour each, at most three', () {
      final range = monthWidgetRange(now);
      final dots = monthDots(
        entries([
          event('a', DateTime(2026, 11, 14, 10), const Duration(hours: 1), color: 0xFFF97316),
          event('b', DateTime(2026, 11, 14, 12), const Duration(hours: 1), color: 0xFFF97316),
          event('c', DateTime(2026, 11, 14, 13), const Duration(hours: 1), color: 0xFF10B981),
          event('d', DateTime(2026, 11, 14, 14), const Duration(hours: 1), color: 0xFF3B82F6),
          event('e', DateTime(2026, 11, 14, 15), const Duration(hours: 1), color: 0xFF000000),
          // Three days, all day: a dot on each.
          event('trip', DateTime(2026, 12, 24), const Duration(days: 3), allDay: true),
        ], range),
        range,
      );
      expect(dots['2026-11-14'], ['#F97316', '#10B981', '#3B82F6']);
      expect(dots.keys.where((k) => k.startsWith('2026-12')), ['2026-12-24', '2026-12-25', '2026-12-26']);
      // Only colours: nothing the month grid gets could name an event.
      expect(dots.toString(), isNot(contains('trip')));
    });
  });

  group('agenda', () {
    final range = DateRange(DateTime(2026, 11, 14), DateTime(2026, 11, 28));

    test('all-day first, then by time; repeating events carry their start', () {
      final weekly = CalendarEvent(
        id: 'gym',
        title: 'Gym',
        start: DateTime(2026, 11, 7, 18),
        end: DateTime(2026, 11, 7, 19),
        color: 0xFF10B981,
        rrule: 'FREQ=WEEKLY',
      );
      final rows = agendaRows(
        entries([
          event('Dentist', DateTime(2026, 11, 14, 11), const Duration(hours: 1)),
          event('Holiday', DateTime(2026, 11, 14), const Duration(days: 1), allDay: true),
          weekly,
          event('Tomorrow', DateTime(2026, 11, 15, 9), const Duration(hours: 1)),
        ], range),
        day: DateTime(2026, 11, 14),
        showTitles: true,
        formatTime: time,
        l10n: en,
      );
      expect(rows.map((r) => r.title), ['Holiday', 'Dentist', 'Gym']);
      expect(rows.map((r) => r.time), ['All day', '11:00', '18:00']);
      expect(rows[1].toJson()['id'], 'id-7-11');
      expect(rows[1].toJson().containsKey('s'), isFalse);
      expect(rows[2].toJson()['s'], DateTime(2026, 11, 14, 18).toIso8601String());
      expect(rows[0].toJson().containsKey('e'), isFalse, reason: 'all-day rows stay all day');
      expect(rows[1].toJson()['e'], DateTime(2026, 11, 14, 12).millisecondsSinceEpoch);
    });

    test('with details off every row says Event, in Hebrew too', () {
      final list = entries([event('Secret', DateTime(2026, 11, 14, 11), const Duration(hours: 1))], range);
      final off = agendaRows(list, day: DateTime(2026, 11, 14), showTitles: false, formatTime: time, l10n: en);
      expect(off.single.title, 'Event');
      expect(off.single.toJson().toString(), isNot(contains('Secret')));
      final offHe = agendaRows(list, day: DateTime(2026, 11, 14), showTitles: false, formatTime: time, l10n: he);
      expect(offHe.single.title, he.event);
    });

    test('a day key the widget can look up', () {
      expect(dayKey(DateTime(2026, 1, 5, 23)), '2026-01-05');
    });
  });
}
