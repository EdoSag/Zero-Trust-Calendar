import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/data/find_a_time.dart';
import 'package:zerotrust_calendar/data/shared_calendars.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

void main() {
  // Monday 16 November 2026.
  final monday = DateTime(2026, 11, 16);
  DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

  test('blocks merge when they overlap or touch', () {
    expect(
      mergeBlocks([
        (at(16, 10), at(16, 11)),
        (at(16, 9), at(16, 10)),
        (at(16, 10, 30), at(16, 12)),
        (at(16, 14), at(16, 15)),
        (at(16, 16), at(16, 16)), // empty: dropped
      ]),
      [(at(16, 9), at(16, 12)), (at(16, 14), at(16, 15))],
    );
  });

  test('busy times: timed events of visible calendars, not all-day, '
      'not the shared calendar itself', () {
    const calendars = [
      ZtCalendarInfo.personal,
      ZtCalendarInfo(id: 'hidden', name: 'H', color: 1, hidden: true),
      ZtCalendarInfo(id: 'shared:s', name: 'Family', color: 2),
    ];
    final blocks = busyBlocks(
      events: [
        CalendarEvent(
          id: 'a',
          title: 'Dentist',
          start: at(16, 9),
          end: at(16, 10),
        ),
        CalendarEvent(
          id: 'b',
          title: 'Secret',
          start: at(16, 11),
          end: at(16, 12),
          calendarId: 'hidden',
        ),
        CalendarEvent(
          id: 'c',
          title: 'Holiday',
          start: monday,
          end: DateTime(2026, 11, 17),
          allDay: true,
        ),
        CalendarEvent(
          id: 'd',
          title: 'Family dinner',
          start: at(16, 19),
          end: at(16, 21),
          calendarId: 'shared:s',
        ),
        CalendarEvent(
          id: 'e',
          title: 'Gym',
          start: at(16, 7),
          end: at(16, 8),
          rrule: 'FREQ=DAILY;COUNT=3',
        ),
      ],
      calendars: calendars,
      from: monday,
      exceptCalendarId: 'shared:s',
    );
    expect(blocks, [
      (at(16, 7), at(16, 8)),
      (at(16, 9), at(16, 10)),
      (at(17, 7), at(17, 8)),
      (at(18, 7), at(18, 8)),
    ]);
  });

  test('free slots skip busy times, the past and weekends', () {
    final slots = freeSlots(
      busy: [(at(16, 9), at(16, 17)), (at(17, 8), at(17, 18))],
      from: DateTime(2026, 11, 14), // Saturday
      now: at(14, 12),
      length: const Duration(hours: 1),
      days: 4,
      dayStartHour: 8,
      dayEndHour: 18,
    );
    // Sat and Sun skipped; Monday 8:00 and 17:00 only; Tuesday all busy.
    expect(slots, [at(16, 8), at(16, 17)]);
    final now = freeSlots(
      busy: const [],
      from: monday,
      now: at(16, 16, 10),
      length: const Duration(minutes: 30),
      days: 1,
      dayEndHour: 17,
    );
    expect(now, [at(16, 16, 30)]);
  });

  test('busy items round-trip; a member can only speak for themselves', () {
    final busy = MemberBusy(
      userId: 'u1',
      blocks: [(at(16, 9), at(16, 10))],
      updated: DateTime.utc(2026, 11, 11),
    );
    final back = MemberBusy.fromJson(busy.toJson())!;
    expect(back.userId, 'u1');
    expect(back.sameBlocks(busy), isTrue);
    expect(MemberBusy.fromJson({'kind': 'event'}), isNull);

    final entry = SpaceEntry(
      info: const SpaceInfo(
        id: 's',
        app: 'calendar',
        keyEpoch: 1,
        myRole: SpaceRole.member,
      ),
    );
    final cal = readSharedCalendar(entry, [
      LocalItem(
        itemId: busyItemId('u1'),
        updatedAt: DateTime(2026),
        json: busy.toJson(),
      ),
      // Written under someone else's id: ignored.
      LocalItem(
        itemId: busyItemId('u2'),
        updatedAt: DateTime(2026),
        json: busy.toJson(),
      ),
    ]);
    expect(cal.busy.map((b) => b.userId), ['u1']);
    expect(cal.events, isEmpty);
  });
}
