import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/calendar_store.dart';
import '../data/find_a_time.dart';
import '../model/calendar_event.dart';
import 'booking_crypto.dart';
import 'booking_pages.dart';

/// Text for the events bookings become (the app passes its own language).
typedef BookingEventText = ({
  String Function(String name, String page) title,
  String Function(String page) footer,
});

/// Keeps booking pages in step with the calendar while it's unlocked:
/// new bookings become events (with the visitor as guest), bookings the
/// visitor cancelled are removed, and the busy times visitors are offered
/// slots around are uploaded when they change.
class BookingSync {
  BookingSync(this._ref);
  final Ref _ref;

  /// What was last uploaded, and when: unchanged busy times are sent again
  /// only every 12 hours (the server offers slots up to 60 days after the
  /// last upload).
  String? _lastBusy;
  DateTime? _lastBusyAt;
  String? _lastOwner;
  Future<void>? _running;

  BookingBackend get _backend => _ref.read(bookingBackendProvider);

  /// Runs one pass (a pass already running is joined, then run again).
  Future<void> sync({
    required List<CalendarEvent> events,
    required List<ZtCalendarInfo> calendars,
    required BookingEventText text,
    DateTime? now,
  }) async {
    while (_running != null) {
      await _running;
    }
    final run = _sync(events, calendars, text, now ?? DateTime.now());
    _running = run;
    try {
      await run;
    } finally {
      if (identical(_running, run)) _running = null;
    }
  }

  Future<void> _sync(
    List<CalendarEvent> events,
    List<ZtCalendarInfo> calendars,
    BookingEventText text,
    DateTime now,
  ) async {
    if (_ref.read(vaultControllerProvider) is! VaultUnlocked) return;
    final pages = {for (final p in await _backend.pages()) p.id: p};
    if (pages.isEmpty) return;
    final (:added, :changed) = await _takeBookings(pages, calendars, text);
    final removed = {for (final id in changed) id};
    await _uploadBusy(
      [
        for (final e in events)
          if (!removed.contains(e.id)) e,
        for (final e in added)
          if (!events.any((x) => x.id == e.id)) e,
      ],
      calendars,
      now,
    );
    if (changed.isNotEmpty) _ref.read(bookingRevisionProvider.notifier).bump();
  }

  Future<({List<CalendarEvent> added, List<String> changed})> _takeBookings(
    Map<String, BookingPage> pages,
    List<ZtCalendarInfo> calendars,
    BookingEventText text,
  ) async {
    final repo = _ref.read(calendarRepositoryProvider);
    final store = await _ref.read(ztLocalStoreProvider.future);
    return takeBookings(
      backend: _backend,
      pages: pages,
      keys: await bookingKeysCollection.list(store),
      calendars: calendars,
      text: text,
      eventExists: (id) async => await repo.event(id) != null,
      saveEvent: repo.saveEvent,
      deleteEvent: repo.deleteEvent,
    );
  }

  Future<void> _uploadBusy(
    List<CalendarEvent> events,
    List<ZtCalendarInfo> calendars,
    DateTime now,
  ) async {
    final from = DateTime(now.year, now.month, now.day);
    final blocks = busyBlocks(events: events, calendars: calendars, from: from);
    final json = jsonEncode(busyJson(blocks));
    final owner = _ref.read(accountServiceProvider).currentUserId;
    if (owner != _lastOwner) reset();
    final fresh =
        _lastBusyAt != null &&
        now.difference(_lastBusyAt!) < const Duration(hours: 12);
    if (json == _lastBusy && fresh) return;
    await _backend.uploadBusy(blocks);
    _lastBusy = json;
    _lastBusyAt = now;
    _lastOwner = owner;
  }

  /// Forgets what was uploaded, so the next pass uploads again.
  void reset() {
    _lastBusy = null;
    _lastBusyAt = null;
    _lastOwner = null;
  }
}

final bookingSyncProvider = Provider<BookingSync>(BookingSync.new);

/// Adds new bookings to the calendar and removes the ones visitors
/// cancelled, marking each on the server. Returns the events it added and
/// the ids of every event it added or removed.
Future<({List<CalendarEvent> added, List<String> changed})> takeBookings({
  required BookingBackend backend,
  required Map<String, BookingPage> pages,
  required List<BookingPageKey> keys,
  required List<ZtCalendarInfo> calendars,
  required BookingEventText text,
  required Future<bool> Function(String id) eventExists,
  required Future<void> Function(CalendarEvent event) saveEvent,
  required Future<void> Function(String id) deleteEvent,
}) async {
  final keyOf = {for (final k in keys) k.pageId: k};
  final writable = {
    for (final c in calendars)
      if (c.url == null) c.id,
  };
  final added = <CalendarEvent>[];
  final changed = <String>[];
  for (final b in await backend.bookings(
    statuses: const {'new', 'cancel_requested', 'cancelled'},
  )) {
    final eventId = bookingEventId(b.id);
    if (b.status == 'cancelled') {
      // Another phone of this account took the cancel before this
      // booking's event had synced to it, so the event can still turn up
      // here later: remove it whenever it does.
      if (await eventExists(eventId)) {
        await deleteEvent(eventId);
        changed.add(eventId);
      }
      continue;
    }
    if (b.status == 'cancel_requested') {
      if (await eventExists(eventId)) await deleteEvent(eventId);
      await backend.setStatus(b.id, 'cancelled');
      changed.add(eventId);
      continue;
    }
    final key = keyOf[b.pageId];
    final page = pages[b.pageId];
    // Another phone of this account made the page and its key hasn't
    // synced here yet: that phone (or this one, later) takes it.
    if (key == null || page == null || b.sealed == null) continue;
    Map<String, Object?> who;
    try {
      who = openBooking(
        privateKey: key.privateKey,
        sealed: b.sealed!,
        pageId: b.pageId,
        start: b.start,
      );
    } on Object {
      // Not sealed to this page's key: it can't be shown, so it isn't
      // added. The slot stays held until it is cancelled on the server.
      continue;
    }
    final name = _cleanText(who['name'], 80);
    final email = _cleanText(who['email'], 254);
    final note = _cleanText(who['note'], 2000, lines: true);
    final event = CalendarEvent(
      id: eventId,
      title: text.title(name.isEmpty ? email : name, page.title),
      start: b.start,
      end: b.end,
      calendarId: writable.contains(key.calendarId)
          ? key.calendarId
          : CalendarEvent.defaultCalendarId,
      description: [
        if (note.isNotEmpty) note,
        text.footer(page.title),
      ].join('\n\n'),
      guestEmails: [if (_looksLikeEmail(email)) email],
    );
    if (!await eventExists(eventId)) await saveEvent(event);
    await backend.setStatus(b.id, 'added', clearSealed: true);
    added.add(event);
  }
  return (added: added, changed: [...changed, for (final e in added) e.id]);
}

String _cleanText(Object? v, int max, {bool lines = false}) {
  final s = (v is String ? v : '')
      .replaceAll(
        lines
            ? RegExp(r'[\u0000-\u0009\u000b-\u001f\u007f]')
            : RegExp(r'[\u0000-\u001f\u007f]'),
        ' ',
      )
      .trim();
  return s.length > max ? s.substring(0, max) : s;
}

bool _looksLikeEmail(String s) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
