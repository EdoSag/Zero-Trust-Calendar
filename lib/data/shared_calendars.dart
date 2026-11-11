import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../model/calendar_event.dart';
import 'calendar_store.dart';
import 'find_a_time.dart';

/// Shared and family calendars (K14), built on the core's shared spaces
/// (Z24): each shared calendar is one space of the app `calendar`.
///
/// Inside the space, everything is end-to-end encrypted under the space key,
/// which only the members' phones hold:
/// - item `calendar` (kind `calendar`, admins only): name, colour and
///   whether it's a family calendar;
/// - one item per event (kind `event`), written by any member.
///
/// In the app a shared calendar's id is `shared:<spaceId>`. Each member can
/// pick their own colour and hide it: that choice is kept as a `calendar`
/// item with the same id in the member's own store, never in the space.
const sharedCalendarPrefix = 'shared:';

String sharedCalendarId(String spaceId) => '$sharedCalendarPrefix$spaceId';

/// The space behind a shared calendar's id, or null for any other calendar.
String? spaceIdOf(String calendarId) =>
    calendarId.startsWith(sharedCalendarPrefix)
    ? calendarId.substring(sharedCalendarPrefix.length)
    : null;

extension SharedCalendarInfo on ZtCalendarInfo {
  bool get isShared => id.startsWith(sharedCalendarPrefix);
}

/// Item id of the calendar's name and colour inside its space.
const sharedInfoItemId = 'calendar';

/// Only admins may rename or recolour the shared calendar for everyone.
const calendarSpacePolicy = SpacePolicy(adminOnlyKinds: {'calendar'});

/// Bumped after every local write to a shared calendar, so screens update
/// at once even offline (the sync status, which also refreshes them,
/// changes only on sync).
final sharedRevisionProvider = NotifierProvider<SharedRevision, int>(
  SharedRevision.new,
);

class SharedRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// One shared calendar as this account sees it.
@immutable
class SharedCalendar {
  const SharedCalendar({
    required this.entry,
    required this.info,
    required this.events,
    this.family = false,
    this.busy = const [],
  });

  final SpaceEntry entry;

  /// Name and colour as the admins set them (before this member's own
  /// colour and hidden choice).
  final ZtCalendarInfo info;
  final List<CalendarEvent> events;
  final bool family;

  /// Busy times of the members who share them (for "Find a time").
  final List<MemberBusy> busy;

  String get spaceId => entry.info.id;
  String get id => sharedCalendarId(spaceId);

  /// Joined, but an admin hasn't let this account in yet.
  bool get waiting => entry.space == null;
  bool get isAdmin => entry.info.myRole == SpaceRole.admin;
  List<SpaceMember> get members => entry.space?.members ?? const [];

  /// The code to compare with the admin while [waiting].
  String? get joinCode => entry.joinCode;
}

/// Decodes one space's items into a [SharedCalendar]. Pure, so it is tested
/// without a server.
SharedCalendar readSharedCalendar(SpaceEntry entry, List<LocalItem> items) {
  final id = sharedCalendarId(entry.info.id);
  var info = ZtCalendarInfo(
    id: id,
    name: '',
    color: ZtCalendarInfo.defaultColor,
  );
  var family = false;
  final events = <CalendarEvent>[];
  final busy = <MemberBusy>[];
  for (final item in items) {
    if (item.deleted || item.json == null) continue;
    if (item.itemId == sharedInfoItemId) {
      final c = calendarsCollection.decode(item);
      if (c != null) {
        info = ZtCalendarInfo(id: id, name: c.name, color: c.color);
        family = item.json!['family'] == true;
      }
      continue;
    }
    if (MemberBusy.fromJson(item.json) case final b?) {
      // Only a member's own busy item counts (its id names them).
      if (item.itemId == busyItemId(b.userId)) busy.add(b);
      continue;
    }
    final e = eventsCollection.decode(item);
    // The space decides the calendar, whatever an event says.
    if (e != null) events.add(e.copyWith(calendarId: id));
  }
  return SharedCalendar(
    entry: entry,
    info: info,
    events: events,
    family: family,
    busy: busy,
  );
}

/// Every shared calendar of the account, waiting ones included. Empty while
/// locked or when sharing isn't available.
final sharedCalendarsProvider = FutureProvider<List<SharedCalendar>>((
  ref,
) async {
  ref.watch(sharedRevisionProvider);
  final spaces = ref.watch(ztSpacesProvider);
  final out = <SharedCalendar>[];
  for (final e in spaces.entries) {
    final space = e.space;
    out.add(
      readSharedCalendar(e, space == null ? const [] : await space.store.all()),
    );
  }
  return out;
});

/// The shared calendars' events, ready to merge with the account's own.
final sharedEventsProvider = Provider<List<CalendarEvent>>(
  (ref) => [
    for (final c
        in ref.watch(sharedCalendarsProvider).value ?? const <SharedCalendar>[])
      ...c.events,
  ],
);

/// Merges the account's own calendars with its shared ones: name from the
/// space, colour and hidden from the member's own choice when set. Own
/// choices for calendars this account has left are dropped. Pure.
List<ZtCalendarInfo> mergeSharedCalendars(
  List<ZtCalendarInfo> own,
  List<SharedCalendar> shared, {
  required String unnamed,
}) {
  final choices = {
    for (final c in own)
      if (c.isShared) c.id: c,
  };
  return [
    for (final c in own)
      if (!c.isShared) c,
    for (final s in shared)
      if (!s.waiting)
        ZtCalendarInfo(
          id: s.id,
          name: s.info.name.trim().isEmpty ? unnamed : s.info.name,
          color: choices[s.id]?.color ?? s.info.color,
          hidden: choices[s.id]?.hidden ?? false,
        ),
  ];
}

/// Creating, joining and managing shared calendars.
final sharedCalendarActionsProvider = Provider<SharedCalendarActions>(
  (ref) => SharedCalendarActions(ref),
);

class SharedCalendarActions {
  SharedCalendarActions(this._ref);
  final Ref _ref;

  SpacesController get _spaces => _ref.read(ztSpacesProvider.notifier);
  void _changed() => _ref.read(sharedRevisionProvider.notifier).bump();

  /// A new shared calendar with this account as its admin. Returns its id.
  Future<String> create({
    required String name,
    required int color,
    required String myName,
    bool family = false,
  }) async {
    final space = await _spaces.create(myName: myName);
    await saveInfo(space.id, name: name, color: color, family: family);
    return sharedCalendarId(space.id);
  }

  /// Renames or recolours the calendar for every member (admins only).
  Future<void> saveInfo(
    String spaceId, {
    required String name,
    required int color,
    bool family = false,
  }) async {
    final json = calendarsCollection.encode(
      ZtCalendarInfo(id: sharedInfoItemId, name: name, color: color),
    )..['family'] = family;
    json.remove('url');
    json.remove('hidden');
    await _spaces.save(spaceId, sharedInfoItemId, json);
    _changed();
  }

  /// This member's own colour and hidden choice (kept in their own store).
  Future<void> saveMyChoice(ZtCalendarInfo calendar) =>
      _ref.read(calendarRepositoryProvider).saveCalendar(calendar);

  /// Puts this account's busy times into [spaceId] for "Find a time", only
  /// when they changed (so an unchanged calendar doesn't sync every
  /// minute).
  Future<void> publishBusy(
    String spaceId,
    List<(DateTime, DateTime)> blocks,
  ) async {
    final me = _ref.read(accountServiceProvider).currentUserId;
    final space = _ref.read(ztSpacesProvider)[spaceId]?.space;
    if (me == null || space == null) return;
    final next = MemberBusy(
      userId: me,
      blocks: mergeBlocks(blocks),
      updated: DateTime.now(),
    );
    final item = await space.store.get(busyItemId(me));
    final before = item == null || item.deleted
        ? null
        : MemberBusy.fromJson(item.json);
    if (before != null && before.sameBlocks(next)) return;
    await _spaces.save(spaceId, busyItemId(me), next.toJson());
    _changed();
  }

  /// Takes this account's busy times out of [spaceId].
  Future<void> withdrawBusy(String spaceId) async {
    final me = _ref.read(accountServiceProvider).currentUserId;
    final space = _ref.read(ztSpacesProvider)[spaceId]?.space;
    if (me == null || space == null) return;
    final item = await space.store.get(busyItemId(me));
    if (item == null || item.deleted) return;
    await _spaces.delete(spaceId, busyItemId(me));
    _changed();
  }

  Future<void> leave(String spaceId) async {
    await _spaces.leave(spaceId);
    await _forgetChoice(spaceId);
    _changed();
  }

  /// Deletes the calendar and its events for everyone (admins only).
  Future<void> delete(String spaceId) async {
    await _spaces.deleteSpace(spaceId);
    await _forgetChoice(spaceId);
    _changed();
  }

  Future<void> _forgetChoice(String spaceId) async {
    final id = sharedCalendarId(spaceId);
    final store = await _ref.read(ztLocalStoreProvider.future);
    if (await calendarsCollection.get(store, id) == null) return;
    await calendarsCollection.delete(
      _ref.read(ztSyncControllerProvider.notifier),
      id,
    );
  }
}
