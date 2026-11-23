import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zerotrust_calendar/app/app_gate.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  final now = DateTime(2026, 11, 22, 8);
  String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  CalendarEvent booking(String id, int day, int hour) => CalendarEvent(
    id: id,
    title: 'Dana (Intro call)',
    start: DateTime(2026, 11, day, hour),
    end: DateTime(2026, 11, day, hour, 30),
  );

  test('a new booking says who and when', () {
    final notices = bookingNotices(
      [booking('b1', 23, 10)],
      showTitles: true,
      now: now,
      formatTime: hhmm,
    );
    expect(notices, hasLength(1));
    expect(notices.single.title, 'New booking');
    expect(notices.single.body, 'Dana (Intro call)\nTomorrow, 10:00 to 10:30');
    expect(notices.single.eventId, 'b1');
    // A tap opens the event on its day.
    final payload = ReminderPayload.parse(notices.single.payload)!;
    expect(payload.eventId, 'b1');
    expect(payload.occurrence, DateTime(2026, 11, 23, 10));
  });

  test('with titles kept out of notifications, only when', () {
    final notices = bookingNotices(
      [booking('b1', 22, 15)],
      showTitles: false,
      now: now,
      formatTime: hhmm,
    );
    expect(notices.single.body, 'Today, 15:00 to 15:30');
    expect(notices.single.body, isNot(contains('Dana')));
  });

  test('many at once become one notification about the first', () {
    final notices = bookingNotices(
      [booking('b3', 25, 9), booking('b1', 23, 9), booking('b4', 26, 9), booking('b2', 24, 9)],
      showTitles: true,
      now: now,
      formatTime: hhmm,
    );
    expect(notices, hasLength(1));
    expect(notices.single.title, '4 new bookings');
    expect(notices.single.body, 'First: Tomorrow, 09:00 to 09:30');
    expect(notices.single.eventId, 'b1');
  });

  test('the same booking keeps the same notification id', () {
    const a = Notice(eventId: 'x', title: 't', body: 'b');
    const b = Notice(eventId: 'x', title: 'other', body: 'other');
    expect(a.notificationId, b.notificationId);
  });

  test('the test scheduler records notices', () async {
    final s = NoopReminderScheduler();
    await s.showNotice(const Notice(eventId: 'x', title: 't', body: 'b'));
    expect(s.notices.single.eventId, 'x');
  });
}
