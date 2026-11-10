import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/data/phone_calendar_sync.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/ics/ics.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';

void main() {
  group('event fields', () {
    test('video link, attachments, guests and replies survive JSON', () {
      final e = CalendarEvent(
        id: 'a',
        title: 'Planning',
        start: DateTime(2026, 11, 12, 10),
        end: DateTime(2026, 11, 12, 11),
        timeZone: 'Europe/London',
        conferenceUrl: 'https://meet.jit.si/zt-planning',
        attachments: const [
          {'id': 'x', 'key': 'k', 'size': 10, 'mime': 'text/plain', 'name': 'a.txt'},
        ],
        guestEmails: const ['dana@example.com'],
        guestStatus: const {'dana@example.com': 'accepted'},
        inviteSequence: 2,
      );
      final back = CalendarEvent.fromJson('a', jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>, null)!;
      expect(back.timeZone, 'Europe/London');
      expect(back.conferenceUrl, 'https://meet.jit.si/zt-planning');
      expect(back.attachments.single['name'], 'a.txt');
      expect(back.guestEmails, ['dana@example.com']);
      expect(back.guestStatus['dana@example.com'], 'accepted');
      expect(back.inviteSequence, 2);
      expect(back.readOnly, isFalse);
    });

    test('a subscribed calendar keeps its link through edits', () {
      const c = ZtCalendarInfo(id: 'c', name: 'Team', color: 1, url: 'https://x.test/a.ics');
      final edited = ZtCalendarInfo.fromJson('c', c.copyWith(name: 'Football').toJson());
      expect(edited.url, 'https://x.test/a.ics');
      expect(edited.isSubscription, isTrue);
      expect(ZtCalendarInfo.personal.isSubscription, isFalse);
    });
  });

  group('invitations', () {
    test('an emailed invitation round-trips guests, method and video link', () {
      final e = CalendarEvent(
        id: 'a',
        title: 'Planning',
        start: DateTime.utc(2026, 11, 12, 10),
        end: DateTime.utc(2026, 11, 12, 11),
        icalUid: 'uid-1@zt',
        conferenceUrl: 'https://meet.google.com/abc-defg-hij',
      );
      final text = Ics.write(
        [e],
        invite: const IcsInvite(
          organizerEmail: 'me@example.com',
          organizerName: 'Me',
          guests: [('Dana', 'dana@example.com'), (null, 'sam@example.com')],
        ),
      );
      final unfolded = text.replaceAll('\r\n ', '');
      expect(unfolded, contains('METHOD:REQUEST'));
      expect(unfolded, contains('ORGANIZER;CN=Me:mailto:me@example.com'));
      expect(unfolded, contains('CN=Dana:mailto:dana@example.com'));
      final parsed = Ics.parse(text);
      expect(parsed.method, 'REQUEST');
      final back = parsed.events.single;
      expect(back.icalUid, 'uid-1@zt');
      expect(back.conferenceUrl, 'https://meet.google.com/abc-defg-hij');
      expect(back.guestEmails, containsAll(['dana@example.com', 'sam@example.com']));
    });

    test('a cancellation keeps the cancelled UIDs', () {
      const text =
          'BEGIN:VCALENDAR\r\nMETHOD:CANCEL\r\n'
          'BEGIN:VEVENT\r\nUID:u1\r\nDTSTART:20261112T100000Z\r\nDTEND:20261112T110000Z\r\n'
          'STATUS:CANCELLED\r\nSUMMARY:Planning\r\nEND:VEVENT\r\n'
          'BEGIN:VEVENT\r\nUID:u2\r\nRECURRENCE-ID:20261119T100000Z\r\nDTSTART:20261119T100000Z\r\n'
          'DTEND:20261119T110000Z\r\nSTATUS:CANCELLED\r\nSUMMARY:Standup\r\nEND:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      final parsed = Ics.parse(text);
      expect(parsed.method, 'CANCEL');
      expect(parsed.events, isEmpty);
      expect(parsed.cancelled.map((c) => c.uid), ['u1', 'u2']);
      expect(parsed.cancelled.first.occurrence, isNull);
      expect(parsed.cancelled.last.occurrence!.isAtSameMomentAs(DateTime.utc(2026, 11, 19, 10)), isTrue);
    });

    test('an update to one occurrence says which one it replaces', () {
      const text =
          'BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\n'
          'BEGIN:VEVENT\r\nUID:series\r\nRECURRENCE-ID:20261119T100000Z\r\n'
          'DTSTART:20261119T140000Z\r\nDTEND:20261119T150000Z\r\nSUMMARY:Standup (moved)\r\nEND:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      final parsed = Ics.parse(text);
      final e = parsed.events.single;
      expect(e.rrule, isNull);
      final occ = parsed.changedOccurrences[e.id]!;
      expect(occ.uid, 'series');
      expect(occ.occurrence.isAtSameMomentAs(DateTime.utc(2026, 11, 19, 10)), isTrue);
    });

    test('meeting links are found in plain text', () {
      expect(
        findMeetingLink('Dial in: https://us02web.zoom.us/j/123?pwd=x thanks'),
        'https://us02web.zoom.us/j/123?pwd=x',
      );
      expect(findMeetingLink('see https://example.com/page'), isNull);
    });
  });

  group('subscriptions', () {
    test('webcal and bare links become https', () {
      expect(normalizeFeedUrl('webcal://x.test/a.ics'), 'https://x.test/a.ics');
      expect(normalizeFeedUrl('  x.test/a.ics '), 'https://x.test/a.ics');
      expect(normalizeFeedUrl('http://x.test/a.ics'), 'http://x.test/a.ics');
    });

    test('a feed keeps recent events, read-only, and round-trips', () {
      const ics =
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
          'BEGIN:VEVENT\r\nUID:old\r\nDTSTART;VALUE=DATE:20200101\r\nDTEND;VALUE=DATE:20200102\r\nSUMMARY:Old\r\nEND:VEVENT\r\n'
          'BEGIN:VEVENT\r\nUID:new\r\nDTSTART;VALUE=DATE:20261225\r\nDTEND;VALUE=DATE:20261226\r\nSUMMARY:Christmas\r\nEND:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      const cal = ZtCalendarInfo(id: 'hol', name: 'Holidays', color: 1, url: 'https://x.test/h.ics');
      final feed = feedFromIcs(cal, ics, now: DateTime(2026, 11, 10));
      expect(feed.events.map((e) => e.title), ['Christmas']);
      final back = CalendarFeed.fromJson(jsonDecode(jsonEncode(feed.toJson())) as Map<String, Object?>);
      expect(back.calendarId, 'hol');
      expect(back.events.single.title, 'Christmas');
      expect(back.events.single.calendarId, 'hol');
      expect(back.events.single.readOnly, isTrue);
      expect(CalendarFeed.itemIdFor('hol'), CalendarFeed.itemIdFor('hol'));
      expect(CalendarFeed.itemIdFor('hol'), isNot(CalendarFeed.itemIdFor('other')));
    });

    test('holiday feeds are https Google public calendars', () {
      for (final h in holidayCalendars) {
        expect(h.url, startsWith('https://calendar.google.com/calendar/ical/'));
        expect(h.url, endsWith('/public/basic.ics'));
      }
    });
  });

  group('show on this phone', () {
    test('another account on the same phone starts with nothing copied', () {
      const s = CalendarSettings(phoneCalendarIds: {'default'}, phoneCalendarOwner: 'user-a');
      expect(s.phoneCalendarIdsFor('user-a'), {'default'});
      expect(s.phoneCalendarIdsFor('user-b'), isEmpty);
      expect(s.phoneCalendarIdsFor(null), isEmpty);
      final back = CalendarSettings.fromPrefs(s.toPrefs());
      expect(back.phoneCalendarIdsFor('user-a'), {'default'});
      expect(const CalendarSettings().phoneCalendarIdsFor('user-a'), isEmpty);
    });

    test('only switched-on calendars are copied, within the window', () {
      final now = DateTime(2026, 11, 10);
      final payload = phoneCalendarPayload(
        events: [
          CalendarEvent(id: '1', title: 'Gym', start: DateTime(2026, 11, 11, 7), end: DateTime(2026, 11, 11, 8)),
          CalendarEvent(id: '2', title: 'Too late', start: DateTime(2028, 1, 1, 7), end: DateTime(2028, 1, 1, 8)),
          CalendarEvent(id: '3', title: 'Holiday', start: DateTime(2026, 12, 25), end: DateTime(2026, 12, 26), allDay: true),
          CalendarEvent(id: '4', title: 'Private', calendarId: 'work', start: DateTime(2026, 11, 11, 9), end: DateTime(2026, 11, 11, 10)),
        ],
        calendars: const [
          ZtCalendarInfo.personal,
          ZtCalendarInfo(id: 'work', name: 'Work', color: 2),
        ],
        enabledIds: {CalendarEvent.defaultCalendarId},
        now: now,
      );
      expect(payload, hasLength(1));
      final events = payload.single['events']! as List;
      expect(events.map((e) => (e as Map)['title']), ['Gym', 'Holiday']);
      final holiday = events.last as Map;
      expect(holiday['start'], DateTime.utc(2026, 12, 25).millisecondsSinceEpoch);
    });
  });

  group('tasks', () {
    test('new tasks look like ZT Tasks tasks', () {
      final now = DateTime(2026, 11, 10, 9);
      final json = LinkedTask.newTaskJson(title: 'Pay rent', due: DateTime(2026, 11, 13, 15), hasTime: false, now: now);
      expect(json['dueDate'], '2026-11-13T00:00:00.000');
      expect(json['isCompleted'], isFalse);
      expect(json.containsKey('kind'), isFalse);
      final task = LinkedTask.fromItem('t1', json)!;
      expect(task.title, 'Pay rent');
      final done = LinkedTask.completedJson(json, true, now);
      expect(done['isCompleted'], isTrue);
      expect(done['completedAt'], now.toIso8601String());
      expect(LinkedTask.completedJson(done, false, now)['completedAt'], isNull);
    });
  });

  group('reminder payloads', () {
    test('new payloads carry actions and survive a round trip', () {
      final p = ReminderPayload(
        eventId: 'e1',
        occurrence: DateTime(2026, 11, 12, 10),
        title: 'Planning',
        body: '10:00',
        actions: const [ReminderAction.snooze, ReminderAction.map],
      );
      final back = ReminderPayload.parse(p.encode())!;
      expect(back.eventId, 'e1');
      expect(back.occurrence, DateTime(2026, 11, 12, 10));
      expect(back.actions, [ReminderAction.snooze, ReminderAction.map]);
      expect(back.snoozed, isFalse);
    });

    test('old eventId|occurrence payloads still open the event', () {
      final back = ReminderPayload.parse('e1|2026-11-12T10:00:00.000Z')!;
      expect(back.eventId, 'e1');
      expect(back.occurrence, isNotNull);
      expect(back.actions, isEmpty);
    });
  });
}
