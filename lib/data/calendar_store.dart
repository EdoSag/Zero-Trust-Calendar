import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../model/calendar_event.dart';
import 'event_actions.dart';
import 'subscriptions.dart';

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

/// The account's calendars, "Personal" first. "Personal" always exists:
/// it has a fixed id, so two devices creating it don't make two.
final calendarsProvider = StreamProvider<List<ZtCalendarInfo>>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  List<ZtCalendarInfo> withDefault(List<ZtCalendarInfo> list) {
    final out = [...list]
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

  Future<void> saveEvent(CalendarEvent event) async {
    if (event.readOnly) throw StateError('Subscribed events are read-only');
    final withCreated = event.createdAt == null
        ? event.copyWith(createdAt: DateTime.now())
        : event;
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

  Future<void> deleteEvent(String id) async {
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
    final store = await _store;
    for (final e in await eventsCollection.list(store)) {
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
    for (final e in await eventsCollection.list(await _store))
      if (e.seriesId == seriesId) e,
  ];

  Future<CalendarEvent?> event(String id) async =>
      eventsCollection.get(await _store, id);

  Future<List<CalendarEvent>> allEvents() async =>
      eventsCollection.list(await _store);
}
