import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/ics/ics.dart';
import 'package:zerotrust_calendar/ics/import_service.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

/// Shaped like Google Calendar's export (Takeout / "Export" in settings).
const googleIcs = '''BEGIN:VCALENDAR\r
PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
VERSION:2.0\r
CALSCALE:GREGORIAN\r
X-WR-CALNAME:Work\r
X-WR-TIMEZONE:Europe/Berlin\r
BEGIN:VEVENT\r
DTSTART;TZID=Europe/Berlin:20261102T090000\r
DTEND;TZID=Europe/Berlin:20261102T093000\r
RRULE:FREQ=WEEKLY;BYDAY=MO\r
EXDATE;TZID=Europe/Berlin:20261109T090000\r
DTSTAMP:20261101T000000Z\r
UID:standup@google.com\r
SUMMARY:Stand-up\\, team\r
LOCATION:Room 4\r
DESCRIPTION:Line one\\nLine two that is quite long so the exporter folded i\r
 t onto the next line\r
BEGIN:VALARM\r
ACTION:DISPLAY\r
TRIGGER:-P0DT0H10M0S\r
END:VALARM\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=Europe/Berlin:20261116T100000\r
DTEND;TZID=Europe/Berlin:20261116T103000\r
RECURRENCE-ID;TZID=Europe/Berlin:20261116T090000\r
UID:standup@google.com\r
SUMMARY:Stand-up (moved)\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261224\r
DTEND;VALUE=DATE:20261227\r
UID:holiday@google.com\r
SUMMARY:Holidays\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:20261201T120000Z\r
DTEND:20261201T130000Z\r
UID:cancelled@google.com\r
STATUS:CANCELLED\r
SUMMARY:Cancelled\r
END:VEVENT\r
END:VCALENDAR\r
''';

void main() {
  test('reads a Google Calendar export', () {
    final cal = Ics.parse(googleIcs);
    expect(cal.name, 'Work');
    expect(cal.events.length, 3); // Cancelled one dropped.
    final standup = cal.events.firstWhere((e) => e.title == 'Stand-up, team');
    expect(standup.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(standup.location, 'Room 4');
    expect(standup.description, contains('folded it onto'));
    expect(standup.description, startsWith('Line one\nLine two'));
    expect(standup.reminders, [10]);
    // 09:00 Berlin (CET, UTC+1) is 08:00 UTC.
    expect(standup.start.toUtc(), DateTime.utc(2026, 11, 2, 8));
    expect(standup.exceptions.map((e) => e.toUtc()), contains(DateTime.utc(2026, 11, 9, 8)));
    expect(standup.exceptions.map((e) => e.toUtc()), contains(DateTime.utc(2026, 11, 16, 8)));
    final moved = cal.events.firstWhere((e) => e.title == 'Stand-up (moved)');
    expect(moved.seriesId, standup.id);
    expect(moved.originalStart!.toUtc(), DateTime.utc(2026, 11, 16, 8));
    final holiday = cal.events.firstWhere((e) => e.title == 'Holidays');
    expect(holiday.allDay, isTrue);
    expect(holiday.start, DateTime(2026, 12, 24));
    expect(holiday.end, DateTime(2026, 12, 27));
  });

  test('writes .ics that reads back the same', () {
    final events = Ics.parse(googleIcs).events;
    final text = Ics.write(events, now: DateTime.utc(2026));
    expect(text.split('\r\n').every((l) => utf8.encode(l).length <= 75), isTrue);
    final again = Ics.parse(text).events;
    expect(again.length, events.length);
    for (final e in events) {
      final match = again.firstWhere((x) => x.title == e.title);
      expect(match.start, e.start);
      expect(match.end, e.end);
      expect(match.rrule, e.rrule);
      expect(match.reminders, e.reminders);
      expect(match.description, e.description);
    }
  });

  test('imports a Takeout zip once, mapping calendars by name', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Takeout/Calendar/Work.ics', utf8.encode(googleIcs)))
      ..addFile(
        ArchiveFile.bytes(
          'Takeout/Calendar/me@example.com.ics',
          utf8.encode('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261110\r\n'
              'UID:x1\r\nSUMMARY:Dentist\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'),
        ),
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final plan = IcsImportPlan.build(
      files: [('takeout.zip', zip)],
      existing: const [],
      calendars: const [ZtCalendarInfo.personal],
    );
    expect(plan.newCalendars.map((c) => c.name), ['Work', 'me@example.com']);
    expect(plan.events.length, 4);

    final again = IcsImportPlan.build(
      files: [('takeout.zip', zip)],
      existing: plan.events,
      calendars: [ZtCalendarInfo.personal, ...plan.newCalendars],
    );
    expect(again.newCalendars, isEmpty);
    expect(again.events, isEmpty);
    expect(again.skipped, 4);
  });
}
