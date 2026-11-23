import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../model/calendar_event.dart';

/// The ZT Family circle as a calendar (S-10, for ZT Family's hub, L-2).
///
/// Since S-10 the family circle ZT Family manages is every app's family
/// space. Calendar shows each circle as a calendar, `family:<spaceId>`;
/// events saved in it live in the circle as items
/// `calendar/event/<event id>` with kind `calendar.event` and the common
/// summary under `zt` ([ZtFamilySummary]), which ZT Family's hub lists
/// under "Coming up". Members and invites stay in ZT Family.
const familyCalendarPrefix = 'family:';

String familyCalendarId(String spaceId) => '$familyCalendarPrefix$spaceId';

/// The circle behind a family calendar's id, or null for any other calendar.
String? familySpaceIdOf(String calendarId) =>
    calendarId.startsWith(familyCalendarPrefix)
    ? calendarId.substring(familyCalendarPrefix.length)
    : null;

extension FamilyCircleCalendarInfo on ZtCalendarInfo {
  bool get isFamilyCircle => id.startsWith(familyCalendarPrefix);
}

/// The kind of Calendar's events in the circle.
const familyEventKind = 'calendar.event';

/// The circle item of the event [eventId].
String familyEventItemId(String eventId) =>
    ZtFamilySpace.itemId('calendar', 'event', eventId);

const _eventItemPrefix = 'calendar/event/';

/// A family calendar's colour until the member picks their own.
const familyCalendarColor = 0xFF2E7D32;

/// When [event] next happens from [now] (its start when it repeats no
/// more, or never did): what the hub sorts by.
DateTime nextStart(CalendarEvent event, DateTime now) {
  if (!event.repeats) return event.start;
  final from = now.subtract(event.duration);
  return event.occurrencesBetween(from, from.add(const Duration(days: 400))).firstOrNull?.$1 ??
      event.start;
}

/// [event] as an item of the circle, with the summary ZT Family's hub reads.
Map<String, Object?> familyEventJson(CalendarEvent event, {required DateTime now}) =>
    ZtFamilySummary(
      title: event.title,
      kind: familyEventKind,
      at: nextStart(event, now),
    ).addTo({
      ...event.copyWith(calendarId: CalendarEvent.defaultCalendarId, extra: {
        for (final MapEntry(:key, :value) in event.extra.entries)
          if (key != ZtFamilySpace.summaryKey) key: value,
      }).toJson(),
      'kind': familyEventKind,
    });

/// One family circle as a calendar.
@immutable
class FamilyCircleCalendar {
  const FamilyCircleCalendar({required this.spaceId, required this.name, required this.events});

  final String spaceId;

  /// The circle's name as ZT Family keeps it ('' until it has synced).
  final String name;
  final List<CalendarEvent> events;

  String get id => familyCalendarId(spaceId);
}

/// Reads Calendar's events and the circle's name from a circle's items.
/// Other apps' items and ZT Family's own are left alone. Pure.
FamilyCircleCalendar readFamilyCircle(String spaceId, Iterable<LocalItem> items) {
  var name = '';
  final events = <CalendarEvent>[];
  final id = familyCalendarId(spaceId);
  for (final item in items) {
    final json = item.json;
    if (item.deleted || json == null) continue;
    if (item.itemId == 'family.circle' && json['kind'] == 'family.circle') {
      name = (json['name'] as String? ?? '').trim();
      continue;
    }
    if (!ZtFamilySpace.belongsTo(item.itemId, 'calendar') ||
        !item.itemId.startsWith(_eventItemPrefix) ||
        json['kind'] != familyEventKind) {
      continue;
    }
    final eventId = item.itemId.substring(_eventItemPrefix.length);
    final e = CalendarEvent.fromJson(eventId, json, item.updatedAt);
    if (e == null) continue;
    // The circle decides the calendar; the hub's summary isn't the event's.
    events.add(e.copyWith(
      calendarId: id,
      attachments: const [],
      extra: {
        for (final MapEntry(:key, :value) in e.extra.entries)
          if (key != ZtFamilySpace.summaryKey) key: value,
      },
    ));
  }
  return FamilyCircleCalendar(spaceId: spaceId, name: name, events: events);
}

/// Bumped after every local write to a family circle, so screens update at
/// once even offline.
final familyRevisionProvider = NotifierProvider<FamilyRevision, int>(FamilyRevision.new);

class FamilyRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// The account's family circles this phone can open, as calendars. Empty
/// while locked, or with no circle (or no ZT Family) on the account.
final familyCirclesProvider = FutureProvider<List<FamilyCircleCalendar>>((ref) async {
  ref.watch(familyRevisionProvider);
  // Locked: nothing to open (and no family spaces to start watching).
  if (ref.watch(vaultControllerProvider) is! VaultUnlocked) return const [];
  final circles = ref.watch(ztFamilySpacesProvider);
  return [
    for (final e in circles.entries)
      if (e.space case final space?) readFamilyCircle(e.info.id, await space.store.all()),
  ];
});

/// The circles' events, ready to merge with the account's own.
final familyEventsProvider = Provider<List<CalendarEvent>>(
  (ref) => [
    for (final c in ref.watch(familyCirclesProvider).value ?? const <FamilyCircleCalendar>[])
      ...c.events,
  ],
);

/// The circles as calendars: the circle's name, colour and hidden from this
/// member's own choice when set ([own], kept in their own store). Pure.
List<ZtCalendarInfo> familyCalendarInfos(
  List<FamilyCircleCalendar> circles,
  List<ZtCalendarInfo> own, {
  required String unnamed,
}) {
  final choices = {for (final c in own) if (c.isFamilyCircle) c.id: c};
  return [
    for (final c in circles)
      ZtCalendarInfo(
        id: c.id,
        name: c.name.isEmpty ? unnamed : c.name,
        color: choices[c.id]?.color ?? familyCalendarColor,
        hidden: choices[c.id]?.hidden ?? false,
      ),
  ];
}

/// Repeating events in a circle whose hub summary has fallen behind: the
/// time it shows is over though the series goes on. Saved again with the
/// next time, so the hub's "Coming up" keeps them. Pure.
List<CalendarEvent> staleFamilySummaries(Iterable<LocalItem> items, DateTime now) {
  final out = <CalendarEvent>[];
  for (final item in items) {
    final json = item.json;
    if (item.deleted || json == null || !item.itemId.startsWith(_eventItemPrefix)) continue;
    if (json['kind'] != familyEventKind) continue;
    final at = ZtFamilySummary.of(json)?.at;
    final e = CalendarEvent.fromJson(item.itemId.substring(_eventItemPrefix.length), json, item.updatedAt);
    if (e == null || !e.repeats) continue;
    final next = nextStart(e, now);
    if (at == null || (at.isBefore(now.subtract(e.duration)) && next.isAfter(at))) out.add(e);
  }
  return out;
}
