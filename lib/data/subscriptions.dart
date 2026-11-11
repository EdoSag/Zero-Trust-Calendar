import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../ics/ics.dart';
import '../model/calendar_event.dart';
import 'calendar_store.dart';
import 'shared_calendars.dart';

/// The last copy of a subscribed calendar (public holidays, a school or
/// team .ics link): its events as fetched, kept as one encrypted item so
/// every device shows them offline. Fetched without the account: the
/// calendar's server sees a plain download, nothing else.
@immutable
class CalendarFeed {
  const CalendarFeed({
    required this.calendarId,
    required this.fetchedAt,
    required this.events,
    this.error,
  });

  final String calendarId;
  final DateTime fetchedAt;
  final List<CalendarEvent> events;

  /// Why the last refresh failed, or null.
  final String? error;

  /// The item id for [calendarId]'s feed (a fixed UUID, so every device
  /// writes the same item).
  static String itemIdFor(String calendarId) =>
      const Uuid().v5(Namespace.url.value, 'zt-calendar-feed:$calendarId');

  Map<String, Object?> toJson() => {
    'calendarId': calendarId,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'events': [for (final e in events) e.toJson()],
    'error': error,
  };

  static CalendarFeed fromJson(Map<String, Object?> json) {
    final calendarId = (json['calendarId'] as String?) ?? '';
    var i = 0;
    return CalendarFeed(
      calendarId: calendarId,
      fetchedAt:
          DateTime.tryParse((json['fetchedAt'] as String?) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      error: json['error'] as String?,
      events: [
        if (json['events'] case final List list)
          for (final e in list)
            if (e is Map)
              if (CalendarEvent.fromJson(
                    'feed:$calendarId:${i++}',
                    Map<String, Object?>.from(e),
                    null,
                  )
                  case final CalendarEvent event)
                event.copyWith(calendarId: calendarId, readOnly: true),
      ],
    );
  }
}

final feedsCollection = ZtCollection<CalendarFeed>(
  kind: 'feed',
  version: 1,
  fromJson: (_, json, _) => CalendarFeed.fromJson(json),
  toJson: (f) => f.toJson(),
  idOf: (f) => CalendarFeed.itemIdFor(f.calendarId),
);

/// Every subscribed calendar's last copy.
final feedsProvider = StreamProvider<List<CalendarFeed>>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  if (store is ZtLocalStore) {
    yield* feedsCollection.watch(store);
  } else {
    yield await feedsCollection.list(store);
  }
});

/// Events of subscribed calendars, read-only. Series exceptions inside a
/// feed point at their series by the feed-local id.
final feedEventsProvider = Provider<List<CalendarEvent>>((ref) {
  final calendars = ref.watch(calendarsProvider).value ?? const [];
  final subscribed = {for (final c in calendars) if (c.isSubscription) c.id};
  return [
    for (final f in ref.watch(feedsProvider).value ?? const <CalendarFeed>[])
      if (subscribed.contains(f.calendarId)) ...f.events,
  ];
});

/// Your events plus shared and subscribed calendars' events.
final allEventsProvider = Provider<AsyncValue<List<CalendarEvent>>>((ref) {
  final own = ref.watch(eventsProvider);
  final feeds = ref.watch(feedEventsProvider);
  final shared = ref.watch(sharedEventsProvider);
  return own.whenData((list) => [...list, ...shared, ...feeds]);
});

/// A public holiday calendar to subscribe to. These are the public Google
/// Calendar holiday feeds: downloaded like any web file, no Google account
/// involved.
@immutable
class HolidayCalendar {
  const HolidayCalendar(this.name, this.feedId);
  final String name;
  final String feedId;

  String get url =>
      'https://calendar.google.com/calendar/ical/'
      '${Uri.encodeComponent('$feedId#holiday@group.v.calendar.google.com')}'
      '/public/basic.ics';
}

const holidayCalendars = [
  HolidayCalendar('Israel (Jewish holidays)', 'en.jewish'),
  HolidayCalendar('Israel (Jewish holidays, Hebrew)', 'iw.jewish'),
  HolidayCalendar('United States', 'en.usa'),
  HolidayCalendar('United Kingdom', 'en.uk'),
  HolidayCalendar('Canada', 'en.canadian'),
  HolidayCalendar('Australia', 'en.australian'),
  HolidayCalendar('Ireland', 'en.irish'),
  HolidayCalendar('Germany', 'en.german'),
  HolidayCalendar('France', 'en.french'),
  HolidayCalendar('Italy', 'en.italian'),
  HolidayCalendar('Spain', 'en.spain'),
  HolidayCalendar('Netherlands', 'en.dutch'),
  HolidayCalendar('Portugal', 'en.portuguese'),
  HolidayCalendar('Poland', 'en.polish'),
  HolidayCalendar('Sweden', 'en.swedish'),
  HolidayCalendar('Russia', 'en.russian'),
  HolidayCalendar('India', 'en.indian'),
  HolidayCalendar('Japan', 'en.japanese'),
  HolidayCalendar('China', 'en.china'),
  HolidayCalendar('Brazil', 'en.brazilian'),
  HolidayCalendar('Mexico', 'en.mexican'),
  HolidayCalendar('South Africa', 'en.sa'),
  HolidayCalendar('Christian holidays', 'en.christian'),
  HolidayCalendar('Islamic holidays', 'en.islamic'),
];

/// `webcal://x` and plain `x.com/cal.ics` become https:// addresses.
String normalizeFeedUrl(String raw) {
  var v = raw.trim();
  final lower = v.toLowerCase();
  if (lower.startsWith('webcal://')) v = 'https://${v.substring(9)}';
  if (lower.startsWith('webcals://')) v = 'https://${v.substring(10)}';
  if (!v.contains('://')) v = 'https://$v';
  return v;
}

/// Downloads an .ics file. Throws on a network error, a non-200 answer or
/// a file over 8 MB.
typedef FeedFetcher = Future<String> Function(Uri url);

Future<String> fetchFeed(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'ZT Calendar';
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw HttpException('The server answered ${response.statusCode}', uri: url);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > 8 * 1000 * 1000) {
        throw const HttpException('The calendar file is too big');
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}

/// The feed for [calendar] from the text of its .ics file: events from a
/// year ago on, at most [max].
CalendarFeed feedFromIcs(
  ZtCalendarInfo calendar,
  String text, {
  required DateTime now,
  int max = 3000,
}) {
  final parsed = Ics.parse(text, calendarId: calendar.id).events;
  final cutoff = DateTime(now.year - 1, now.month, now.day);
  final kept = [
    for (final e in parsed)
      if (e.repeats || e.end.isAfter(cutoff)) e,
  ];
  kept.sort((a, b) => a.start.compareTo(b.start));
  return CalendarFeed(
    calendarId: calendar.id,
    fetchedAt: now,
    events: kept.length > max ? kept.sublist(kept.length - max) : kept,
  );
}

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService(ref),
);

/// Adds subscribed calendars and keeps their copies fresh.
class SubscriptionService {
  SubscriptionService(this._ref, {this.fetch = fetchFeed});
  final Ref _ref;
  final FeedFetcher fetch;

  /// How often a subscribed calendar is downloaded again.
  static const refreshEvery = Duration(hours: 12);

  SyncController get _sync => _ref.read(ztSyncControllerProvider.notifier);

  /// Creates the calendar and downloads it once. Throws (and adds
  /// nothing) when the first download fails.
  Future<ZtCalendarInfo> subscribe({
    required String name,
    required String url,
    required int color,
  }) async {
    final calendar = ZtCalendarInfo(
      id: const Uuid().v4(),
      name: name,
      color: color,
      url: normalizeFeedUrl(url),
    );
    final text = await fetch(Uri.parse(calendar.url!));
    final feed = feedFromIcs(calendar, text, now: DateTime.now());
    await _ref.read(calendarRepositoryProvider).saveCalendar(calendar);
    await _save(feed);
    return calendar;
  }

  /// Downloads [calendar] again. A failure keeps the last copy and records
  /// the error.
  Future<void> refresh(ZtCalendarInfo calendar) async {
    final url = calendar.url;
    if (url == null) return;
    final now = DateTime.now();
    try {
      final text = await fetch(Uri.parse(url));
      await _save(feedFromIcs(calendar, text, now: now));
    } on Object catch (e) {
      final store = await _ref.read(ztLocalStoreProvider.future);
      final old = await feedsCollection.get(store, CalendarFeed.itemIdFor(calendar.id));
      await _save(
        CalendarFeed(
          calendarId: calendar.id,
          fetchedAt: now,
          events: old?.events ?? const [],
          error: '$e',
        ),
      );
    }
  }

  /// Refreshes every subscription last fetched more than [refreshEvery]
  /// ago (on any of the account's devices).
  Future<void> refreshStale() async {
    final calendars = await _ref.read(calendarsProvider.future);
    final store = await _ref.read(ztLocalStoreProvider.future);
    final now = DateTime.now();
    for (final c in calendars) {
      if (!c.isSubscription) continue;
      final feed = await feedsCollection.get(store, CalendarFeed.itemIdFor(c.id));
      if (feed == null || now.difference(feed.fetchedAt) > refreshEvery) {
        await refresh(c);
      }
    }
  }

  Future<void> _save(CalendarFeed feed) async {
    final store = await _ref.read(ztLocalStoreProvider.future);
    // Events are stored with their feed-local ids dropped; the copy is
    // rebuilt in full each time.
    await feedsCollection.save(_sync, store, feed);
  }

  Future<void> deleteFeed(String calendarId) =>
      feedsCollection.delete(_sync, CalendarFeed.itemIdFor(calendarId));
}
