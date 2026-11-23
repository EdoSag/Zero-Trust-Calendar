import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../booking/booking_crypto.dart';
import '../model/calendar_event.dart';
import 'poll_crypto.dart';

/// Meeting polls (K-5): propose a few times, share a link, guests vote on
/// zerotrust.bz/poll/, then pick the winner and it becomes an event.
///
/// The poll lives twice: as an encrypted item in this account's vault (with
/// its key and the private key guests' emails are sealed to), and as
/// ciphertext on the server for guests to read. See poll_crypto.dart.

/// How long a poll stays on the server after its last proposed time.
const pollKeepAfter = Duration(days: 30);

/// At most this many proposed times.
const pollMaxTimes = 8;

@immutable
class MeetingPoll {
  const MeetingPoll({
    required this.id,
    required this.key,
    required this.privateKey,
    required this.title,
    required this.durationMin,
    required this.times,
    this.hostName = '',
    this.description = '',
    this.location = '',
    this.calendarId = CalendarEvent.defaultCalendarId,
    this.chosen,
    this.eventId,
    this.createdAt,
  });

  final String id;

  /// The link key (base64url, 32 bytes).
  final String key;

  /// P-256 private key guests' emails are sealed to (32 bytes).
  final Uint8List privateKey;
  final String title;
  final String hostName;
  final String description;
  final String location;
  final int durationMin;

  /// The proposed starts, soonest first.
  final List<DateTime> times;

  /// Where the event goes once a time is picked.
  final String calendarId;

  /// The time picked, once there is one.
  final DateTime? chosen;
  final String? eventId;
  final DateTime? createdAt;

  String get link => pollLink(id, key);
  String get publicKey => BookingKeyPair.publicKeyOf(privateKey);
  Duration get duration => Duration(minutes: durationMin);

  /// The server forgets the poll this long after its last time.
  DateTime get expiresAt => times.reduce((a, b) => a.isAfter(b) ? a : b).add(pollKeepAfter);

  static String itemIdFor(String pollId) => 'poll/$pollId';

  MeetingPoll copyWith({
    String? title,
    String? hostName,
    String? description,
    String? location,
    int? durationMin,
    List<DateTime>? times,
    String? calendarId,
    DateTime? chosen,
    String? eventId,
  }) => MeetingPoll(
    id: id,
    key: key,
    privateKey: privateKey,
    title: title ?? this.title,
    hostName: hostName ?? this.hostName,
    description: description ?? this.description,
    location: location ?? this.location,
    durationMin: durationMin ?? this.durationMin,
    times: times ?? this.times,
    calendarId: calendarId ?? this.calendarId,
    chosen: chosen ?? this.chosen,
    eventId: eventId ?? this.eventId,
    createdAt: createdAt,
  );

  /// What guests see (sealed with the link key).
  Map<String, Object?> publicJson() => {
    'title': title,
    'host': hostName,
    'description': description,
    'location': location,
    'durationMin': durationMin,
    'times': [for (final t in times) t.toUtc().millisecondsSinceEpoch],
    'chosen': chosen?.toUtc().millisecondsSinceEpoch,
    'publicKey': publicKey,
  };

  String sealed() => sealForPoll(key: key, pollId: id, part: 'poll', data: publicJson());

  Map<String, Object?> toJson() => {
    'pollId': id,
    'key': key,
    'privateKey': base64.encode(privateKey),
    'title': title,
    'host': hostName,
    'description': description,
    'location': location,
    'durationMin': durationMin,
    'times': [for (final t in times) t.toUtc().toIso8601String()],
    'calendarId': calendarId,
    'chosen': chosen?.toUtc().toIso8601String(),
    'eventId': eventId,
    'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  static MeetingPoll? fromJson(Map<String, Object?> json) {
    final id = json['pollId'];
    final key = json['key'];
    final pk = json['privateKey'];
    final times = [
      for (final t in json['times'] as List? ?? const [])
        if (t is String)
          if (DateTime.tryParse(t) case final d?) d.toLocal(),
    ]..sort();
    if (id is! String || key is! String || pk is! String || times.isEmpty) return null;
    return MeetingPoll(
      id: id,
      key: key,
      privateKey: base64.decode(pk),
      title: json['title'] as String? ?? '',
      hostName: json['host'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      durationMin: (json['durationMin'] as num?)?.toInt() ?? 30,
      times: times,
      calendarId: json['calendarId'] as String? ?? CalendarEvent.defaultCalendarId,
      chosen: DateTime.tryParse(json['chosen'] as String? ?? '')?.toLocal(),
      eventId: json['eventId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal(),
    );
  }
}

final meetingPollsCollection = ZtCollection<MeetingPoll>(
  kind: 'meetingPoll',
  version: 1,
  fromJson: (id, json, _) =>
      MeetingPoll.fromJson(json) ??
      // Unreadable: kept as a poll with no times, so it can be deleted.
      MeetingPoll(
        id: id.replaceFirst('poll/', ''),
        key: '',
        privateKey: Uint8List(32),
        title: (json['title'] as String?) ?? '',
        durationMin: 30,
        times: [DateTime.fromMillisecondsSinceEpoch(0)],
      ),
  toJson: (p) => p.toJson(),
  idOf: (p) => MeetingPoll.itemIdFor(p.id),
);

/// One guest's vote, opened.
@immutable
class PollVote {
  const PollVote({
    required this.id,
    required this.name,
    required this.yes,
    required this.maybe,
    this.email,
    this.updatedAt,
  });

  final String id;
  final String name;
  final Set<DateTime> yes;
  final Set<DateTime> maybe;

  /// Only the poll's owner can read it (sealed to the poll's key pair).
  final String? email;
  final DateTime? updatedAt;
}

/// A vote as the server keeps it.
typedef SealedVote = ({String id, String sealed, DateTime? updatedAt});

/// Opens [rows] with [poll]'s keys. Votes that don't open (changed, or for
/// another poll) are left out.
List<PollVote> openVotes(MeetingPoll poll, Iterable<SealedVote> rows) {
  Set<DateTime> times(Object? list) => {
    for (final t in list is List ? list : const [])
      if (t is int) DateTime.fromMillisecondsSinceEpoch(t),
  };
  final out = <PollVote>[];
  for (final r in rows) {
    try {
      final v = openForPoll(key: poll.key, pollId: poll.id, part: 'vote', sealed: r.sealed);
      final name = (v['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      String? email;
      if (v['contact'] case final String contact) {
        try {
          final c = openBooking(
            privateKey: poll.privateKey,
            sealed: contact,
            pageId: poll.id,
            start: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
          if (c['email'] case final String e when e.contains('@')) email = e.trim();
        } on Object {
          // A contact sealed to another key: the vote still counts.
        }
      }
      out.add(PollVote(
        id: r.id,
        name: name.length > 80 ? name.substring(0, 80) : name,
        yes: times(v['yes']),
        maybe: times(v['maybe']),
        email: email,
        updatedAt: r.updatedAt,
      ));
    } on Object {
      continue;
    }
  }
  return out;
}

/// How one proposed time is doing.
@immutable
class PollTally {
  const PollTally(this.time, this.yes, this.maybe);
  final DateTime time;
  final List<String> yes;
  final List<String> maybe;

  /// Yes counts 2, maybe 1: the best time has the highest score.
  int get score => yes.length * 2 + maybe.length;
}

List<PollTally> tallyPoll(MeetingPoll poll, List<PollVote> votes) => [
  for (final t in poll.times)
    PollTally(
      t,
      [for (final v in votes) if (v.yes.any((y) => y.isAtSameMomentAs(t))) v.name],
      [
        for (final v in votes)
          if (!v.yes.any((y) => y.isAtSameMomentAs(t)) && v.maybe.any((m) => m.isAtSameMomentAs(t)))
            v.name,
      ],
    ),
];

/// The times with the best score (none when nobody voted).
Set<DateTime> bestTimes(List<PollTally> tallies) {
  final top = tallies.fold<int>(0, (m, t) => t.score > m ? t.score : m);
  if (top == 0) return const {};
  return {for (final t in tallies) if (t.score == top) t.time};
}

/// The event for [poll] at [time]: guests who left an email and said yes or
/// maybe to that time are invited.
/// The id of the calendar event a poll's picked time becomes: the same for
/// every try, so picking again after a failure (or twice at once) saves one
/// event, not two.
String pollEventId(MeetingPoll poll) => const Uuid().v5(Namespace.url.value, 'zt-meeting-poll:${poll.id}');

CalendarEvent pollEvent(MeetingPoll poll, DateTime time, List<PollVote> votes, {required String id}) {
  final emails = <String>{
    for (final v in votes)
      if (v.email != null &&
          (v.yes.any((y) => y.isAtSameMomentAs(time)) ||
              v.maybe.any((m) => m.isAtSameMomentAs(time))))
        v.email!,
  };
  return CalendarEvent(
    id: id,
    title: poll.title,
    start: time,
    end: time.add(poll.duration),
    calendarId: poll.calendarId,
    description: poll.description,
    location: poll.location,
    guestEmails: emails.toList()..sort(),
  );
}

/// The server side of polls. [SupabasePollBackend] in the app; a fake in
/// tests.
abstract interface class PollBackend {
  Future<void> savePoll(MeetingPoll poll, {bool closed = false});

  /// Puts [poll] on the server only if it isn't there yet, in one step on
  /// the server. A poll already there (maybe with a time picked on another
  /// device) is left exactly as it is.
  Future<void> publishPoll(MeetingPoll poll);
  Future<void> deletePoll(String id);
  Future<List<SealedVote>> votes(String pollId);
}

class SupabasePollBackend implements PollBackend {
  SupabasePollBackend(this._client);
  final SupabaseClient _client;

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  @override
  Future<void> savePoll(MeetingPoll poll, {bool closed = false}) =>
      _client.from('zt_polls').upsert({
        'id': poll.id,
        'owner': _me,
        'sealed': poll.sealed(),
        'closed': closed,
        'expires_at': poll.expiresAt.toUtc().toIso8601String(),
      });

  @override
  Future<void> publishPoll(MeetingPoll poll) => _client.from('zt_polls').upsert(
    {
      'id': poll.id,
      'owner': _me,
      'sealed': poll.sealed(),
      'closed': false,
      'expires_at': poll.expiresAt.toUtc().toIso8601String(),
    },
    onConflict: 'id',
    ignoreDuplicates: true,
  );

  @override
  Future<void> deletePoll(String id) => _client.from('zt_polls').delete().eq('id', id);

  @override
  Future<List<SealedVote>> votes(String pollId) async => [
    for (final row in await _client
        .from('zt_poll_votes')
        .select('id, sealed, updated_at')
        .eq('poll_id', pollId)
        .order('created_at'))
      (
        id: row['id'] as String,
        sealed: row['sealed'] as String,
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '')?.toLocal(),
      ),
  ];
}

final pollBackendProvider = Provider<PollBackend>(
  (ref) => SupabasePollBackend(Supabase.instance.client),
);

/// This account's polls, newest first.
final meetingPollsProvider = StreamProvider<List<MeetingPoll>>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  List<MeetingPoll> sorted(List<MeetingPoll> list) => [...list]
    ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  if (store is ZtLocalStore) {
    yield* meetingPollsCollection.watch(store).map(sorted);
  } else {
    yield sorted(await meetingPollsCollection.list(store));
  }
});

/// The votes on one poll, opened (refresh with `ref.invalidate`).
final pollVotesProvider = FutureProvider.family<List<PollVote>, String>((ref, pollId) async {
  final polls = await ref.watch(meetingPollsProvider.future);
  final poll = polls.where((p) => p.id == pollId).firstOrNull;
  if (poll == null) return const [];
  return openVotes(poll, await ref.read(pollBackendProvider).votes(pollId));
});
