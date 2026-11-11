
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/booking/booking_crypto.dart';
import 'package:zerotrust_calendar/booking/booking_pages.dart';
import 'package:zerotrust_calendar/booking/booking_sync.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

class FakeBackend implements BookingBackend {
  final List<BookingPage> saved = [];
  final Map<String, Booking> rows = {};
  final Map<String, bool> cleared = {};
  List<(DateTime, DateTime)>? busy;

  @override
  Future<List<BookingPage>> pages() async => saved;
  @override
  Future<void> savePage(BookingPage page) async => saved
    ..removeWhere((p) => p.id == page.id)
    ..add(page);
  @override
  Future<void> deletePage(String id) async => saved.removeWhere((p) => p.id == id);
  @override
  Future<void> uploadBusy(List<(DateTime, DateTime)> blocks) async => busy = blocks;
  @override
  Future<List<Booking>> bookings({Set<String>? statuses}) async => [
    for (final b in rows.values)
      if (statuses == null || statuses.contains(b.status)) b,
  ];
  @override
  Future<void> setStatus(String id, String status, {bool clearSealed = false}) async {
    final b = rows[id]!;
    rows[id] = Booking(
      id: b.id,
      pageId: b.pageId,
      start: b.start,
      end: b.end,
      status: status,
      sealed: clearSealed ? null : b.sealed,
    );
    cleared[id] = clearSealed;
  }

  @override
  Stream<void> changes() => const Stream.empty();
}

void main() {
  final keys = BookingKeyPair.generate();
  final page = BookingPage(
    id: 'bAAAAAAAAAAAAAAAAAAAAAA',
    title: 'Intro call',
    durationMin: 30,
    timeZone: 'Asia/Jerusalem',
    hours: BookingPage.defaultHours(sundayFirst: true),
    publicKey: keys.publicKey,
  );
  final text = (
    title: (String name, String page) => '$name ($page)',
    footer: (String page) => 'Booked on “$page”.',
  );
  const calendars = [
    ZtCalendarInfo.personal,
    ZtCalendarInfo(id: 'work', name: 'Work', color: 1),
  ];

  test('page rows round trip, as the server stores them', () {
    final row = page.copyWith(hostName: 'Edo', bufferMin: 10).toRow('owner-1');
    expect(row['owner'], 'owner-1');
    expect(row['hours'], {
      '7': [[540, 1020]],
      '1': [[540, 1020]],
      '2': [[540, 1020]],
      '3': [[540, 1020]],
      '4': [[540, 1020]],
    });
    expect(BookingPage.fromRow(row), page.copyWith(hostName: 'Edo', bufferMin: 10));
    expect(page.link, 'https://zerotrust.bz/book/#bAAAAAAAAAAAAAAAAAAAAAA');
    expect(RegExp(r'^[A-Za-z0-9_-]{16,32}$').hasMatch(BookingPage.newId()), isTrue);
  });

  test('busy times go up as merged millisecond pairs', () {
    final a = DateTime.utc(2026, 11, 16, 9);
    expect(
      busyJson([
        (a, a.add(const Duration(hours: 1))),
        (a.add(const Duration(minutes: 30)), a.add(const Duration(hours: 2))),
      ]),
      [
        [a.millisecondsSinceEpoch, a.add(const Duration(hours: 2)).millisecondsSinceEpoch],
      ],
    );
  });

  group('takeBookings', () {
    late FakeBackend backend;
    late Map<String, CalendarEvent> events;
    final start = DateTime.utc(2026, 11, 16, 7).toLocal();

    Booking booking(String id, String status, {String? sealed}) => Booking(
      id: id,
      pageId: page.id,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      status: status,
      sealed: sealed,
    );

    Future<({List<CalendarEvent> added, List<String> changed})> run({
      List<BookingPageKey>? withKeys,
    }) => takeBookings(
      backend: backend,
      pages: {page.id: page},
      keys:
          withKeys ??
          [BookingPageKey(pageId: page.id, privateKey: keys.privateKey, calendarId: 'work')],
      calendars: calendars,
      text: text,
      eventExists: (id) async => events.containsKey(id),
      saveEvent: (e) async => events[e.id] = e,
      deleteEvent: (id) async => events.remove(id),
    );

    setUp(() {
      backend = FakeBackend();
      events = {};
    });

    test('a new booking becomes an event with the visitor as guest', () async {
      backend.rows['b1'] = booking(
        'b1',
        'new',
        sealed: sealBooking(
          publicKey: keys.publicKey,
          data: {'name': 'Dana\u0007 Levi', 'email': 'dana@example.com', 'note': 'About the\nproject'},
          pageId: page.id,
          start: start,
        ),
      );
      final r = await run();
      final e = events[bookingEventId('b1')]!;
      expect(e.title, 'Dana  Levi (Intro call)');
      expect(e.calendarId, 'work');
      expect(e.start, start);
      expect(e.end, start.add(const Duration(minutes: 30)));
      expect(e.guestEmails, ['dana@example.com']);
      expect(e.description, 'About the\nproject\n\nBooked on “Intro call”.');
      expect(backend.rows['b1']!.status, 'added');
      expect(backend.rows['b1']!.sealed, isNull);
      expect(r.added.single.id, e.id);
      // Running again changes nothing.
      expect((await run()).changed, isEmpty);
    });

    test('without the page key here, the booking waits', () async {
      backend.rows['b2'] = booking(
        'b2',
        'new',
        sealed: sealBooking(
          publicKey: keys.publicKey,
          data: {'name': 'Avi', 'email': 'avi@example.com'},
          pageId: page.id,
          start: start,
        ),
      );
      await run(withKeys: const []);
      expect(events, isEmpty);
      expect(backend.rows['b2']!.status, 'new');
    });

    test('a booking sealed to another key or time is not added', () async {
      backend.rows['b3'] = booking(
        'b3',
        'new',
        sealed: sealBooking(
          publicKey: keys.publicKey,
          data: {'name': 'Mallory'},
          pageId: page.id,
          start: start.add(const Duration(hours: 1)),
        ),
      );
      await run();
      expect(events, isEmpty);
      expect(backend.rows['b3']!.status, 'new');
    });

    test('a visitor\'s cancel removes the event', () async {
      final id = bookingEventId('b4');
      events[id] = CalendarEvent(id: id, title: 'x', start: start, end: start);
      backend.rows['b4'] = booking('b4', 'cancel_requested');
      final r = await run();
      expect(events, isEmpty);
      expect(backend.rows['b4']!.status, 'cancelled');
      expect(r.changed, [id]);
    });

    test('a calendar that is gone falls back to the default one', () async {
      backend.rows['b5'] = booking(
        'b5',
        'new',
        sealed: sealBooking(
          publicKey: keys.publicKey,
          data: {'name': '', 'email': 'not an email'},
          pageId: page.id,
          start: start,
        ),
      );
      await run(withKeys: [
        BookingPageKey(pageId: page.id, privateKey: keys.privateKey, calendarId: 'gone'),
      ]);
      final e = events[bookingEventId('b5')]!;
      expect(e.calendarId, CalendarEvent.defaultCalendarId);
      expect(e.guestEmails, isEmpty);
      expect(e.title, 'not an email (Intro call)');
    });
  });

}
