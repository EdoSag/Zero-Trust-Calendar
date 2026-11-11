import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../model/calendar_event.dart';
import 'event_actions.dart';
import 'shared_calendars.dart';
import 'subscriptions.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Events are items with `kind: event`, calendars `kind: calendar`.
final eventsCollection = ZtCollection<CalendarEvent>(
  kind: 'event',
  version: 1,
  fromJson: (id, json, updatedAt) =>
      CalendarEvent.fromJson(id, json, updatedAt) ??
      CalendarEvent(
        // Unreadable dates: keep it visible rather than drop it.
        id: id,
        title: (json['title'] as String?) ?? '',
        start: updatedAt.toLocal(),
        end: updatedAt.toLocal().add(const Duration(hours: 1)),
      ),
  toJson: (e) => e.toJson(),
  idOf: (e) => e.id,
);

final calendarsCollection = ZtCollection<ZtCalendarInfo>(
  kind: 'calendar',
  version: 1,
  fromJson: (id, json, _) => ZtCalendarInfo.fromJson(id, json),
  toJson: (c) => c.toJson(),
  idOf: (c) => c.id,
);

/// Every event and series in the account (including hidden calendars').
final eventsProvider = StreamProvider<List<CalendarEvent>>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  if (store is ZtLocalStore) {
    yield* eventsCollection.watch(store);
  } else {
    yield await eventsCollection.list(store);
  }
});

/// The account's calendars, "Personal" first, shared calendars included.
/// "Personal" always exists: it has a fixed id, so two devices creating it
/// don't make two.
final calendarsProvider = StreamProvider<List<ZtCalendarInfo>>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  final shared = ref.watch(sharedCalendarsProvider).value ?? const <SharedCalendar>[];
  final unnamed = appL10nFor(ref.watch(ztLanguageProvider)).sharedCalendarUnnamed;
  List<ZtCalendarInfo> withDefault(List<ZtCalendarInfo> list) {
    final out = mergeSharedCalendars(list, shared, unnamed: unnamed)
      ..sort((a, b) {
        if (a.id == CalendarEvent.defaultCalendarId) return -1;
        if (b.id == CalendarEvent.defaultCalendarId) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    if (!out.any((c) => c.id == CalendarEvent.defaultCalendarId)) {
      out.insert(0, ZtCalendarInfo.personal);
    }
    return out;
  }

  if (store is ZtLocalStore) {
    yield* calendarsCollection.watch(store).map(withDefault);
  } else {
    yield withDefault(await calendarsCollection.list(store));
  }
});

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepository(ref),
);

/// Saves and deletes through the shared sync controller, so every edit is
/// encrypted, stored locally and pushed to the account's other devices.
class CalendarRepository {
  CalendarRepository(this._ref);
  final Ref _ref;

  SyncController get _sync => _ref.read(ztSyncControllerProvider.notifier);
  Future<LocalItemStore> get _store => _ref.read(ztLocalStoreProvider.future);

  /// The open shared calendars' spaces, by space id.
  Map<String, SharedSpace> get _spaces => {
    for (final e in _ref.read(ztSpacesProvider).entries)
      if (e.space case final s?) e.info.id: s,
  };

  /// The space an event is stored in now, or null for the account's own
  /// store (or nowhere yet).
  Future<String?> _spaceHolding(String eventId) async {
    if (await (await _store).get(eventId) case final item? when !item.deleted) {
      return null;
    }
    for (final MapEntry(:key, :value) in _spaces.entries) {
      final item = await value.store.get(eventId);
      if (item != null && !item.deleted) return key;
    }
    return null;
  }

  Future<void> saveEvent(CalendarEvent event) async {
    if (event.readOnly) throw StateError('Subscribed events are read-only');
    var withCreated = event.createdAt == null
        ? event.copyWith(createdAt: DateTime.now())
        : event;
    final target = spaceIdOf(event.calendarId);
    final from = await _spaceHolding(event.id);
    if (target != null) {
      // Attachments are sealed with this account's own key, which the
      // other members don't have, so shared events don't carry them.
      withCreated = withCreated.copyWith(attachments: const []);
      final space = _spaces[target];
      if (space == null) throw StateError('Shared calendar not open');
      if (from == null && await (await _store).get(event.id) != null) {
        await deleteEvent(event.id); // Moved in from the account's own.
      }
      if (from != null && from != target) await _deleteShared(from, event.id);
      final previous = (await space.store.get(event.id))?.json;
      await _ref.read(ztSpacesProvider.notifier).save(
        target,
        event.id,
        eventsCollection.encode(
          withCreated,
          previous: eventsCollection.owns(previous) ? previous : null,
        ),
      );
      _ref.read(sharedRevisionProvider.notifier).bump();
      return;
    }
    if (from != null) await _deleteShared(from, event.id); // Moved out.
    final store = await _store;
    final before = await eventsCollection.get(store, event.id);
    await eventsCollection.save(_sync, store, withCreated);
    if (before != null) {
      final kept = {for (final a in event.attachments) a['id']};
      await _release([
        for (final a in before.attachments)
          if (!kept.contains(a['id'])) a,
      ]);
    }
  }

  Future<void> _deleteShared(String spaceId, String id) async {
    await _ref.read(ztSpacesProvider.notifier).delete(spaceId, id);
    _ref.read(sharedRevisionProvider.notifier).bump();
  }

  Future<void> deleteEvent(String id) async {
    if (await _spaceHolding(id) case final spaceId?) {
      return _deleteShared(spaceId, id);
    }
    final before = await eventsCollection.get(await _store, id);
    await eventsCollection.delete(_sync, id);
    if (before != null) await _release(before.attachments);
  }

  /// Deletes the files of [attachments] that no other event still holds
  /// (a changed occurrence keeps its series' attachments).
  Future<void> _release(List<Map<String, Object?>> attachments) async {
    if (attachments.isEmpty) return;
    final inUse = {
      for (final e in await eventsCollection.list(await _store))
        for (final a in e.attachments) a['id'],
    };
    final refs = <ZtAttachmentRef>[
      for (final a in attachments)
        if (!inUse.contains(a['id']))
          if (_parseRef(a) case final r?) r,
    ];
    if (refs.isEmpty) return;
    try {
      final files = await _ref.read(ztAttachmentsProvider.future);
      await files.deleteAll(refs);
    } on Object {
      // Locked or offline: an orphan file costs storage, not privacy.
    }
  }

  static ZtAttachmentRef? _parseRef(Map<String, Object?> json) {
    try {
      return ZtAttachmentRef.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// Deletes a series and every changed occurrence of it.
  Future<void> deleteSeries(CalendarEvent series) async {
    for (final e in await allEvents()) {
      if (e.seriesId == series.id) await deleteEvent(e.id);
    }
    await deleteEvent(series.id);
  }

  Future<void> saveCalendar(ZtCalendarInfo calendar) async {
    await calendarsCollection.save(_sync, await _store, calendar);
  }

  /// Deletes a calendar and its events. "Personal" can't be deleted.
  Future<void> deleteCalendar(String id) async {
    if (id == CalendarEvent.defaultCalendarId) return;
    // Shared calendars are left or deleted through SharedCalendarActions.
    if (spaceIdOf(id) != null) return;
    final store = await _store;
    for (final e in await eventsCollection.list(store)) {
      if (e.calendarId == id) await deleteEvent(e.id);
    }
    await calendarsCollection.delete(_sync, id);
    await feedsCollection.delete(_sync, CalendarFeed.itemIdFor(id));
  }

  /// Applies a series edit or delete (see [SeriesEdits]).
  Future<void> apply(SeriesChange change) async {
    for (final e in change.save) {
      await saveEvent(e);
    }
    for (final id in change.delete) {
      await deleteEvent(id);
    }
  }

  /// Changed occurrences of the series [seriesId].
  Future<List<CalendarEvent>> exceptionsOf(String seriesId) async => [
    for (final e in await allEvents())
      if (e.seriesId == seriesId) e,
  ];

  Future<CalendarEvent?> event(String id) async {
    if (await eventsCollection.get(await _store, id) case final e?) return e;
    for (final MapEntry(:key, :value) in _spaces.entries) {
      if (await eventsCollection.get(value.store, id) case final e?) {
        return e.copyWith(calendarId: sharedCalendarId(key));
      }
    }
    return null;
  }

  /// The account's own events and its shared calendars' events.
  Future<List<CalendarEvent>> allEvents() async => [
    ...await eventsCollection.list(await _store),
    for (final MapEntry(:key, :value) in _spaces.entries)
      for (final e in await eventsCollection.list(value.store))
        e.copyWith(calendarId: sharedCalendarId(key)),
  ];
}
