import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/shared_calendars.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';
const mallory = '00000000-0000-4000-8000-0000000000ff';

Uint8List dek(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 7 + i) & 0xff));

class Phone {
  Phone(this.server, this.userId, this.seed);
  final InMemorySpaceServer server;
  final String userId;
  final int seed;
  final Map<String, InMemoryItemStore> stores = {};
  late final SharedSpaces spaces;

  Future<Phone> start() async {
    spaces = SharedSpaces(
      app: 'calendar',
      myUserId: userId,
      identity: await ZtIdentity.fromDek(dek(seed)),
      backend: server.backendFor(userId),
      privateStore: InMemorySpacePrivateStore(),
      openStore: (id) async => stores.putIfAbsent(id, InMemoryItemStore.new),
      deleteStore: (id) async => stores.remove(id),
      deviceId: 'phone-$userId',
      policy: calendarSpacePolicy,
    );
    return this;
  }

  /// What the app shows for the space, as [readSharedCalendar] builds it.
  Future<SharedCalendar> calendar(String spaceId) async {
    final space = await spaces.open(spaceId);
    await spaces.sync(space);
    final info = (await spaces.list()).firstWhere((i) => i.id == spaceId);
    return readSharedCalendar(
      SpaceEntry(info: info, space: space),
      await space.store.all(),
    );
  }
}

Map<String, Object?> calendarJson(String name, int color) =>
    calendarsCollection.encode(
      ZtCalendarInfo(id: sharedInfoItemId, name: name, color: color),
    )..['family'] = true;

void main() {
  test('shared calendar ids map to and from their space', () {
    const space = '11111111-2222-4333-8444-555555555555';
    expect(sharedCalendarId(space), 'shared:$space');
    expect(spaceIdOf(sharedCalendarId(space)), space);
    expect(spaceIdOf(CalendarEvent.defaultCalendarId), isNull);
    expect(spaceIdOf('3b1f2a9e-0000-4000-8000-000000000000'), isNull);
    expect(
      const ZtCalendarInfo(id: 'shared:x', name: 'A', color: 1).isShared,
      isTrue,
    );
    expect(ZtCalendarInfo.personal.isShared, isFalse);
  });

  test('a member sees the family calendar and edits its events; '
      'only admins rename it; a removed member reads nothing new', () async {
    final server = InMemorySpaceServer();
    final a = await Phone(server, alice, 1).start();
    final b = await Phone(server, bob, 2).start();

    // Alice makes "Family" and adds dinner.
    final space = await a.spaces.create(myName: 'Alice');
    await space.save(sharedInfoItemId, calendarJson('Family', 0xFF10B981));
    final dinner = CalendarEvent(
      id: 'e1',
      title: 'Dinner at Grandma',
      start: DateTime(2026, 11, 13, 19),
      end: DateTime(2026, 11, 13, 21),
    );
    await space.save('e1', eventsCollection.encode(dinner));
    await a.spaces.sync(space);

    // Bob joins with a link and the matching code.
    final link = await a.spaces.invite(space.id);
    expect(
      link.toString(),
      startsWith('https://zerotrust.bz/join/calendar#zt1.calendar.'),
    );
    final started = await b.spaces.answer(
      SpaceInviteLink.parse(link.toString()),
      myName: 'Bob',
    );
    final pending = await a.spaces.pendingJoins(space.id);
    expect(pending.single.verificationCode, started.verificationCode);
    await a.spaces.confirm(pending.single);

    final seen = await b.calendar(space.id);
    expect(seen.info.name, 'Family');
    expect(seen.family, isTrue);
    expect(seen.isAdmin, isFalse);
    expect(seen.events.single.title, 'Dinner at Grandma');
    // The space decides the calendar, whatever the event JSON said.
    expect(seen.events.single.calendarId, sharedCalendarId(space.id));
    expect({for (final m in seen.members) m.name}, {'Alice', 'Bob'});

    // Bob moves dinner; Alice sees it.
    final bs = await b.spaces.open(space.id);
    await bs.save(
      'e1',
      eventsCollection.encode(
        dinner.copyWith(start: DateTime(2026, 11, 13, 20)),
        previous: (await bs.store.get('e1'))?.json,
      ),
    );
    await b.spaces.sync(bs);
    final mine = await a.calendar(space.id);
    expect(mine.events.single.start, DateTime(2026, 11, 13, 20));

    // Bob may not rename the calendar for everyone.
    await bs.save(sharedInfoItemId, calendarJson('Bob was here', 0xFFEF4444));
    await expectLater(b.spaces.sync(bs), throwsA(anything));

    // Alice removes Bob: what she adds next is sealed under a key he lacks.
    await a.spaces.remove(space.id, bob);
    final as = await a.spaces.open(space.id);
    await as.save(
      'e2',
      eventsCollection.encode(
        CalendarEvent(
          id: 'e2',
          title: 'Secret party',
          start: DateTime(2026, 11, 20, 19),
          end: DateTime(2026, 11, 20, 23),
        ),
      ),
    );
    await a.spaces.sync(as);
    try {
      await b.spaces.sync(bs);
    } on Object {
      // Removed: the sync may fail outright.
    }
    final leftWith = [
      for (final s in b.stores.values)
        for (final i in await s.all())
          if (i.json?['title'] == 'Secret party') i,
    ];
    expect(leftWith, isEmpty);
  });

  test(
    'my colour and hidden choice win over the space; '
    'choices for calendars I left are dropped; waiting ones are not listed',
    () async {
      final a = await Phone(InMemorySpaceServer(), alice, 1).start();
      final s1 = await a.spaces.create(myName: 'Alice');
      final s2 = await a.spaces.create(myName: 'Alice');
      final infos = {for (final i in await a.spaces.list()) i.id: i};
      SharedCalendar shared(SharedSpace? space, String id, String name) =>
          SharedCalendar(
            entry: SpaceEntry(
              info:
                  infos[id] ??
                  SpaceInfo(
                    id: id,
                    app: 'calendar',
                    keyEpoch: 1,
                    myRole: SpaceRole.member,
                  ),
              space: space,
            ),
            info: ZtCalendarInfo(
              id: sharedCalendarId(id),
              name: name,
              color: 0xFF10B981,
            ),
            events: const [],
          );
      final own = [
        ZtCalendarInfo.personal,
        const ZtCalendarInfo(id: 'work', name: 'Work', color: 1),
        ZtCalendarInfo(
          id: sharedCalendarId(s1.id),
          name: '',
          color: 0xFF000001,
          hidden: true,
        ),
        const ZtCalendarInfo(id: 'shared:gone', name: '', color: 2),
      ];
      final merged = mergeSharedCalendars(own, [
        shared(s1, s1.id, 'Family'),
        shared(s2, s2.id, ''),
        shared(null, 'waiting-space', 'Club'),
      ], unnamed: 'Shared calendar');
      expect(merged.map((c) => c.id), [
        'default',
        'work',
        sharedCalendarId(s1.id),
        sharedCalendarId(s2.id),
      ]);
      final family = merged[2];
      expect(family.name, 'Family');
      expect(family.color, 0xFF000001);
      expect(family.hidden, isTrue);
      expect(merged[3].name, 'Shared calendar');
      expect(merged[3].color, 0xFF10B981);
      expect(merged[3].hidden, isFalse);
    },
  );
}
