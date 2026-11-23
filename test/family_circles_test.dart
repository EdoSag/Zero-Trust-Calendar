import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/data/family_circles.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';

Uint8List _dek(int seed) => Uint8List.fromList(List<int>.generate(32, (i) => (seed * 7 + i) & 0xff));

/// A phone with the family circles as every app sees them since S-10.
class _Phone {
  _Phone(this.server, this.userId, this.seed);
  final InMemorySpaceServer server;
  final String userId;
  final int seed;
  final Map<String, InMemoryItemStore> stores = {};
  late final SharedSpaces circles;

  Future<_Phone> start() async {
    circles = SharedSpaces(
      app: ZtFamilySpace.app,
      myUserId: userId,
      identity: await ZtIdentity.fromDek(_dek(seed)),
      backend: server.backendFor(userId),
      privateStore: InMemorySpacePrivateStore(),
      openStore: (id) async => stores.putIfAbsent(id, InMemoryItemStore.new),
      deleteStore: (id) async => stores.remove(id),
      deviceId: 'phone-$userId',
      policy: ZtFamilySpace.policy,
    );
    return this;
  }
}

void main() {
  final now = DateTime(2026, 11, 22, 12);
  final dinner = CalendarEvent(
    id: 'e1',
    title: 'Dinner at Grandma',
    start: DateTime(2026, 11, 24, 19),
    end: DateTime(2026, 11, 24, 21),
    location: 'Haifa',
    attachments: const [{'id': 'f', 'key': 'k'}],
  );

  test('calendar ids and circle item ids', () {
    expect(familyCalendarId('s1'), 'family:s1');
    expect(familySpaceIdOf('family:s1'), 's1');
    expect(familySpaceIdOf('shared:s1'), isNull);
    expect(familyEventItemId('e1'), 'calendar/event/e1');
    expect(ZtFamilySpace.belongsTo(familyEventItemId('e1'), 'calendar'), isTrue);
    expect(const ZtCalendarInfo(id: 'family:s1', name: 'F', color: 1).isFamilyCircle, isTrue);
  });

  test('an event in the circle carries the summary ZT Family\'s hub reads', () {
    final json = familyEventJson(dinner, now: now);
    expect(json['kind'], 'calendar.event');
    final summary = ZtFamilySummary.of(json)!;
    expect(summary.title, 'Dinner at Grandma');
    expect(summary.kind, 'calendar.event');
    expect(summary.at!.toLocal(), dinner.start);
    expect(summary.done, isNull);
  });

  test('a repeating event\'s summary shows its next time, and is refreshed', () {
    final swim = CalendarEvent(
      id: 's',
      title: 'Swimming',
      start: DateTime(2026, 11, 2, 17),
      end: DateTime(2026, 11, 2, 18),
      rrule: 'FREQ=WEEKLY',
    );
    expect(nextStart(swim, now), DateTime(2026, 11, 23, 17));
    final old = familyEventJson(swim, now: DateTime(2026, 11, 3));
    expect(ZtFamilySummary.of(old)!.at!.toLocal(), DateTime(2026, 11, 9, 17));
    final items = [
      LocalItem(itemId: familyEventItemId('s'), updatedAt: now, json: old),
      LocalItem(itemId: familyEventItemId('e1'), updatedAt: now, json: familyEventJson(dinner, now: now)),
      LocalItem(
        itemId: familyEventItemId('fresh'),
        updatedAt: now,
        json: familyEventJson(
          CalendarEvent(id: 'fresh', title: 'Fresh', start: swim.start, end: swim.end, rrule: 'FREQ=WEEKLY'),
          now: now,
        ),
      ),
    ];
    expect([for (final e in staleFamilySummaries(items, now)) e.id], ['s']);
  });

  test('Calendar saves into the circle, ZT Family\'s hub sees it, '
      'other apps\' items stay out of the calendar', () async {
    final server = InMemorySpaceServer();
    final a = await _Phone(server, alice, 1).start(); // ZT Family
    final b = await _Phone(server, bob, 2).start(); // ZT Calendar

    final circle = await a.circles.create(myName: 'Alice');
    await circle.save('family.circle', {'kind': 'family.circle', 'name': 'Sagron family'});
    await circle.save(
      ZtFamilySpace.itemId('tasks', 'item', 't1'),
      const ZtFamilySummary(title: 'Milk', kind: 'tasks.item').addTo({'kind': 'tasks.item'}),
    );
    await a.circles.sync(circle);
    final link = await a.circles.invite(circle.id);
    await b.circles.answer(SpaceInviteLink.parse(link.toString()), myName: 'Bob');
    await a.circles.confirm((await a.circles.pendingJoins(circle.id)).single);

    // Bob (a member, not an owner) adds dinner from ZT Calendar.
    final bs = await b.circles.open(circle.id);
    await b.circles.sync(bs);
    await bs.save(familyEventItemId('e1'), familyEventJson(dinner, now: now));
    await b.circles.sync(bs);

    // Alice's ZT Family reads only the summary.
    final as = await a.circles.open(circle.id);
    await a.circles.sync(as);
    final there = await as.store.get('calendar/event/e1');
    expect(ZtFamilySummary.of(there!.json)!.title, 'Dinner at Grandma');

    // And Calendar shows the circle as a calendar with its name.
    final read = readFamilyCircle(circle.id, await as.store.all());
    expect(read.name, 'Sagron family');
    expect(read.events, hasLength(1));
    final e = read.events.single;
    expect(e.id, 'e1');
    expect(e.calendarId, familyCalendarId(circle.id));
    expect(e.location, 'Haifa');
    expect(e.start, dinner.start);
    expect(e.attachments, isEmpty);
    expect(e.extra.containsKey('zt'), isFalse);
    // One item alone reads the same (how the repository finds one event).
    expect(readFamilyCircle(circle.id, [there]).events.single.title, 'Dinner at Grandma');
  });

  test('family circles become calendars, with the member\'s own colour and hidden choice', () {
    const circles = [
      FamilyCircleCalendar(spaceId: 's1', name: 'Sagron family', events: []),
      FamilyCircleCalendar(spaceId: 's2', name: '', events: []),
    ];
    final infos = familyCalendarInfos(
      circles,
      const [ZtCalendarInfo(id: 'family:s2', name: 'x', color: 7, hidden: true)],
      unnamed: 'Family',
    );
    expect(infos[0].name, 'Sagron family');
    expect(infos[0].color, familyCalendarColor);
    expect(infos[1].name, 'Family');
    expect(infos[1].color, 7);
    expect(infos[1].hidden, isTrue);
  });
}
