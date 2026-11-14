import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/find_a_time.dart';
import '../model/calendar_event.dart';

/// Booking pages (K15): "Book 30 min with Edo" links anyone can open at
/// zerotrust.bz/book/ to pick a free time, which lands in this calendar.
///
/// Edo chose instant bookings: the phone uploads when the account is busy
/// (start and end only, no titles, the next 60 days) and the server offers
/// the free slots and holds a booking at once. Who booked and why stays
/// sealed to the page's key (see booking_crypto.dart); the private key is an
/// encrypted item in the vault, so only the owner's phones read it.

/// Where visitors open a page.
const bookingSiteBase = 'https://zerotrust.bz/book/';

/// One booking page, as the server keeps it (visitors see all of this).
@immutable
class BookingPage {
  const BookingPage({
    required this.id,
    required this.title,
    required this.durationMin,
    required this.timeZone,
    required this.hours,
    required this.publicKey,
    this.hostName = '',
    this.description = '',
    this.stepMin = 30,
    this.bufferMin = 0,
    this.noticeMin = 240,
    this.horizonDays = 30,
    this.active = true,
  });

  final String id;
  final String title;
  final String hostName;
  final String description;
  final int durationMin;

  /// Slots start every [stepMin] minutes inside the working hours.
  final int stepMin;

  /// Free time kept before and after other events.
  final int bufferMin;

  /// How soon a visitor can book, in minutes from now.
  final int noticeMin;

  /// How far ahead visitors can book.
  final int horizonDays;

  /// IANA zone the [hours] are in.
  final String timeZone;

  /// ISO weekday (1 = Monday) to minute ranges in [timeZone].
  final Map<int, List<(int, int)>> hours;

  final String publicKey;
  final bool active;

  String get link => '$bookingSiteBase#$id';

  /// A fresh page id: 22 random URL-safe characters after "b".
  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return 'b${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  /// 09:00 to 17:00 on the working days ([sundayFirst]: Sunday to Thursday,
  /// as in Israel; otherwise Monday to Friday).
  static Map<int, List<(int, int)>> defaultHours({
    bool sundayFirst = false,
  }) => {
    for (final d in sundayFirst ? const [7, 1, 2, 3, 4] : const [1, 2, 3, 4, 5])
      d: const [(540, 1020)],
  };

  BookingPage copyWith({
    String? title,
    String? hostName,
    String? description,
    int? durationMin,
    int? stepMin,
    int? bufferMin,
    int? noticeMin,
    int? horizonDays,
    String? timeZone,
    Map<int, List<(int, int)>>? hours,
    bool? active,
  }) => BookingPage(
    id: id,
    publicKey: publicKey,
    title: title ?? this.title,
    hostName: hostName ?? this.hostName,
    description: description ?? this.description,
    durationMin: durationMin ?? this.durationMin,
    stepMin: stepMin ?? this.stepMin,
    bufferMin: bufferMin ?? this.bufferMin,
    noticeMin: noticeMin ?? this.noticeMin,
    horizonDays: horizonDays ?? this.horizonDays,
    timeZone: timeZone ?? this.timeZone,
    hours: hours ?? this.hours,
    active: active ?? this.active,
  );

  Map<String, Object?> toRow(String owner) => {
    'id': id,
    'owner': owner,
    'title': title,
    'host_name': hostName,
    'description': description,
    'duration_min': durationMin,
    'step_min': stepMin,
    'buffer_min': bufferMin,
    'notice_min': noticeMin,
    'horizon_days': horizonDays,
    'time_zone': timeZone,
    'hours': {
      for (final MapEntry(:key, :value) in hours.entries)
        if (value.isNotEmpty)
          '$key': [
            for (final (s, e) in value) [s, e],
          ],
    },
    'public_key': publicKey,
    'active': active,
  };

  static BookingPage fromRow(Map<String, Object?> row) {
    final hours = <int, List<(int, int)>>{};
    if (row['hours'] case final Map raw) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final day = int.tryParse('$key');
        if (day == null || value is! List) continue;
        hours[day] = [
          for (final r in value)
            if (r is List && r.length == 2 && r[0] is num && r[1] is num)
              ((r[0] as num).toInt(), (r[1] as num).toInt()),
        ];
      }
    }
    return BookingPage(
      id: row['id']! as String,
      title: (row['title'] as String?) ?? '',
      hostName: (row['host_name'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      durationMin: (row['duration_min'] as num?)?.toInt() ?? 30,
      stepMin: (row['step_min'] as num?)?.toInt() ?? 30,
      bufferMin: (row['buffer_min'] as num?)?.toInt() ?? 0,
      noticeMin: (row['notice_min'] as num?)?.toInt() ?? 240,
      horizonDays: (row['horizon_days'] as num?)?.toInt() ?? 30,
      timeZone: (row['time_zone'] as String?) ?? 'UTC',
      hours: hours,
      publicKey: (row['public_key'] as String?) ?? '',
      active: row['active'] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingPage &&
      jsonEncode(other.toRow('')) == jsonEncode(toRow(''));

  @override
  int get hashCode => jsonEncode(toRow('')).hashCode;
}

/// A booking on one of this account's pages.
@immutable
class Booking {
  const Booking({
    required this.id,
    required this.pageId,
    required this.start,
    required this.end,
    required this.status,
    this.sealed,
  });

  final String id;
  final String pageId;
  final DateTime start;
  final DateTime end;

  /// new, added, cancel_requested or cancelled.
  final String status;
  final String? sealed;

  static Booking fromRow(Map<String, Object?> row) => Booking(
    id: row['id']! as String,
    pageId: row['page_id']! as String,
    start: DateTime.parse(row['starts_at']! as String).toLocal(),
    end: DateTime.parse(row['ends_at']! as String).toLocal(),
    status: row['status']! as String,
    sealed: row['sealed'] as String?,
  );
}

/// The event a booking becomes (one id on every phone).
String bookingEventId(String bookingId) =>
    const Uuid().v5(Namespace.url.value, 'zt-calendar-booking:$bookingId');

/// A page's private key and the calendar its bookings go into, kept as an
/// encrypted item so every phone of the account can open bookings.
@immutable
class BookingPageKey {
  const BookingPageKey({
    required this.pageId,
    required this.privateKey,
    this.calendarId = CalendarEvent.defaultCalendarId,
  });

  final String pageId;
  final Uint8List privateKey;
  final String calendarId;

  static String itemIdFor(String pageId) =>
      const Uuid().v5(Namespace.url.value, 'zt-calendar-booking-key:$pageId');

  BookingPageKey copyWith({String? calendarId}) => BookingPageKey(
    pageId: pageId,
    privateKey: privateKey,
    calendarId: calendarId ?? this.calendarId,
  );
}

final bookingKeysCollection = ZtCollection<BookingPageKey>(
  kind: 'bookingKey',
  version: 1,
  fromJson: (_, json, _) => BookingPageKey(
    pageId: (json['pageId'] as String?) ?? '',
    privateKey: base64.decode((json['privateKey'] as String?) ?? ''),
    calendarId:
        (json['calendarId'] as String?) ?? CalendarEvent.defaultCalendarId,
  ),
  toJson: (k) => {
    'pageId': k.pageId,
    'privateKey': base64.encode(k.privateKey),
    'calendarId': k.calendarId,
  },
  idOf: (k) => BookingPageKey.itemIdFor(k.pageId),
);

/// The server side of booking pages. [SupabaseBookingBackend] in the app; a
/// fake in tests.
abstract interface class BookingBackend {
  Future<List<BookingPage>> pages();
  Future<void> savePage(BookingPage page);
  Future<void> deletePage(String id);

  /// Replaces this account's busy times.
  Future<void> uploadBusy(List<(DateTime, DateTime)> blocks);

  /// This account's bookings with one of [statuses] (all when null),
  /// soonest first.
  Future<List<Booking>> bookings({Set<String>? statuses});

  /// Moves a booking along; [clearSealed] drops the visitor's sealed
  /// details from the server.
  Future<void> setStatus(String id, String status, {bool clearSealed = false});

  /// Fires when a booking arrives or changes.
  Stream<void> changes();
}

class SupabaseBookingBackend implements BookingBackend {
  SupabaseBookingBackend(this._client);
  final SupabaseClient _client;

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  @override
  Future<List<BookingPage>> pages() async => [
    for (final row
        in await _client
            .from('zt_booking_pages')
            .select()
            .eq('owner', _me)
            .order('created_at'))
      BookingPage.fromRow(row),
  ];

  @override
  Future<void> savePage(BookingPage page) =>
      _client.from('zt_booking_pages').upsert(page.toRow(_me));

  @override
  Future<void> deletePage(String id) =>
      _client.from('zt_booking_pages').delete().eq('id', id);

  @override
  Future<void> uploadBusy(List<(DateTime, DateTime)> blocks) => _client
      .from('zt_booking_busy')
      .upsert({'owner': _me, 'blocks': busyJson(blocks)});

  @override
  Future<List<Booking>> bookings({Set<String>? statuses}) async {
    var q = _client.from('zt_bookings').select().eq('owner', _me);
    if (statuses != null) q = q.inFilter('status', statuses.toList());
    return [for (final row in await q.order('starts_at')) Booking.fromRow(row)];
  }

  @override
  Future<void> setStatus(
    String id,
    String status, {
    bool clearSealed = false,
  }) => _client
      .from('zt_bookings')
      .update({'status': status, if (clearSealed) 'sealed': null})
      .eq('id', id);

  @override
  Stream<void> changes() {
    final out = StreamController<void>();
    RealtimeChannel? channel;
    out.onListen = () {
      channel = _client
          .channel('zt-bookings-${const Uuid().v4()}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'zt_bookings',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'owner',
              value: _me,
            ),
            callback: (_) => out.add(null),
          )
          .subscribe();
    };
    out.onCancel = () async {
      if (channel case final c?) await _client.removeChannel(c);
    };
    return out.stream;
  }
}

/// Busy times as the server keeps them: `[[start_ms, end_ms], ...]`.
List<List<int>> busyJson(List<(DateTime, DateTime)> blocks) => [
  for (final (s, e) in mergeBlocks(blocks))
    [s.toUtc().millisecondsSinceEpoch, e.toUtc().millisecondsSinceEpoch],
];

final bookingBackendProvider = Provider<BookingBackend>(
  (ref) => SupabaseBookingBackend(Supabase.instance.client),
);

/// This account's booking pages (refreshed by [bookingRevisionProvider]).
final bookingPagesProvider = FutureProvider<List<BookingPage>>((ref) async {
  ref.watch(bookingRevisionProvider);
  if (ref.watch(vaultControllerProvider) is! VaultUnlocked) return const [];
  return ref.read(bookingBackendProvider).pages();
});

/// Upcoming bookings on this account's pages, for the pages screen.
final upcomingBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  ref.watch(bookingRevisionProvider);
  if (ref.watch(vaultControllerProvider) is! VaultUnlocked) return const [];
  final now = DateTime.now();
  return [
    for (final b
        in await ref
            .read(bookingBackendProvider)
            .bookings(statuses: const {'new', 'added'}))
      if (b.end.isAfter(now)) b,
  ];
});

final bookingRevisionProvider = NotifierProvider<BookingRevision, int>(
  BookingRevision.new,
);

class BookingRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}
