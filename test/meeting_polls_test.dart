import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/polls/meeting_polls.dart';
import 'package:zerotrust_calendar/polls/poll_crypto.dart';
import 'package:zerotrust_calendar/ui/meeting_polls_page.dart';

import 'home_page_test.dart' show app, expectTappableOnScreen, usePhoneScreen;

/// Made by the website's code (poll.js's vote sealing and /book/seal.js for
/// the email), so the app and the page stay in step.
const _web = {
  'pollId': "pAAAAAAAAAAAAAAAAAAAAAA",
  'key': "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA",
  'privateKey': "yjyBBrXYH2H+FvXd8mO562qr2hEoebeDpOwf80HkXk8=",
  'publicKey': "BAQD0VGRc30MRQUjOFhEzG+Y4hBClX+6sKcThcrckqfycUfsJLOwdVeahZnqoh0ACQVkcEoohgC1Yq1o5xxMau0=",
  'vote': "{\"v\":1,\"iv\":\"n9d3LcE6tQvTSrQP\",\"ct\":\"E8bLsHa6pgcf6fQVxEyyz2kKlvDdx5FYWYuYvIeNqAj0WrgFyBj19vwdXpgPhnd4JXia9SMnJ36aEx+UL7ZRkzTU/6jkrCQyVq6ETnJg7xE4N9B7hJh+7G8WpJ8xaN/AiyLu3hAcTZELO/XZivJRq17yfrWLd/x15+XXKUY0N7QGjPKkDFdKsNGmZ2fmsDlQ3/KvMFRnlXe/kgTDYFwCwzA8oC/ROX1dBhP7lNcILXoqfm3PzYzR7WAUnyD7B9UwTRAtyBkECIdOQZQSB8UzDp+CdXAQ4k8b32TMY9+ZzkGBAXioKuFhQxrBdOxJdwpzhHyPrvT9+l0w4XfOsoN9bhWqs4qcXLONOyF2MjEhQzk521VFf41zjG/RdAr3/LQdw+brGfteWwqyGKPK\"}",
};

class _FakePolls implements PollBackend {
  final saved = <(String, bool)>[];
  List<SealedVote> rows = const [];

  @override
  Future<void> savePoll(MeetingPoll poll, {bool closed = false}) async => saved.add((poll.sealed(), closed));

  @override
  Future<void> deletePoll(String id) async {}

  Object? votesError;

  @override
  Future<List<SealedVote>> votes(String pollId) async {
    if (votesError case final e?) throw e;
    return rows;
  }
}

MeetingPoll _poll({String? id, String? key, String? privateKey, List<DateTime>? times}) => MeetingPoll(
  id: id ?? _web['pollId']!,
  key: key ?? _web['key']!,
  privateKey: base64.decode(privateKey ?? _web['privateKey']!),
  title: 'Team lunch',
  hostName: 'Edo',
  location: 'Cafe',
  durationMin: 60,
  times: times ??
      [
        DateTime.utc(2026, 12, 1, 8).toLocal(),
        DateTime.utc(2026, 12, 2, 8).toLocal(),
        DateTime.utc(2026, 12, 3, 8).toLocal(),
      ],
);

void main() {
  test('poll texts open only with their key, poll and part', () {
    final key = newPollKey(Random(1));
    final id = newPollId(Random(2));
    expect(RegExp(r'^p[A-Za-z0-9_-]{16,31}$').hasMatch(id), isTrue);
    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(key), isTrue);
    final sealed = sealForPoll(key: key, pollId: id, part: 'poll', data: {'title': 'x'});
    expect(openForPoll(key: key, pollId: id, part: 'poll', sealed: sealed), {'title': 'x'});
    expect(() => openForPoll(key: key, pollId: id, part: 'vote', sealed: sealed), throwsA(anything));
    expect(() => openForPoll(key: key, pollId: newPollId(), part: 'poll', sealed: sealed), throwsA(anything));
    expect(() => openForPoll(key: newPollKey(), pollId: id, part: 'poll', sealed: sealed), throwsA(anything));
    expect(pollLink(id, key), 'https://zerotrust.bz/poll/#$id.$key');
  });

  test('a vote made by the website opens, email included', () {
    final poll = _poll();
    expect(poll.publicKey, _web['publicKey']);
    final votes = openVotes(poll, [
      (id: 'v1', sealed: _web['vote']!, updatedAt: null),
      (id: 'v2', sealed: 'not sealed', updatedAt: null),
    ]);
    expect(votes, hasLength(1));
    final v = votes.single;
    expect(v.name, 'Dana');
    expect(v.email, 'dana@example.com');
    expect([for (final t in v.yes) t.millisecondsSinceEpoch], [DateTime.utc(2026, 12, 1, 8).millisecondsSinceEpoch]);
    expect([for (final t in v.maybe) t.millisecondsSinceEpoch], [DateTime.utc(2026, 12, 2, 8).millisecondsSinceEpoch]);
  });

  test('tally, best time and the event with the guests who can come', () {
    final poll = _poll();
    final t = poll.times;
    final votes = [
      PollVote(id: '1', name: 'Dana', yes: {t[0]}, maybe: {t[1]}, email: 'dana@example.com'),
      PollVote(id: '2', name: 'Lior', yes: {t[1]}, maybe: const {}, email: 'lior@example.com'),
      PollVote(id: '3', name: 'Noa', yes: {t[0], t[1]}, maybe: const {}),
    ];
    final tallies = tallyPoll(poll, votes);
    expect(tallies[0].yes, ['Dana', 'Noa']);
    expect(tallies[1].yes, ['Lior', 'Noa']);
    expect(tallies[1].maybe, ['Dana']);
    expect(tallies[2].score, 0);
    expect(bestTimes(tallies), {t[1]});
    final e = pollEvent(poll, t[0], votes, id: 'e1');
    expect(e.title, 'Team lunch');
    expect(e.end.difference(e.start), const Duration(hours: 1));
    expect(e.location, 'Cafe');
    expect(e.guestEmails, ['dana@example.com']); // Lior can't make it.
  });

  test('the poll keeps everything in the vault and only ciphertext goes out', () {
    final poll = _poll().copyWith(chosen: DateTime.utc(2026, 12, 2, 8).toLocal(), eventId: 'e1');
    final back = MeetingPoll.fromJson(poll.toJson())!;
    expect(back.key, poll.key);
    expect(back.times, poll.times);
    expect(back.chosen, poll.chosen);
    expect(back.eventId, 'e1');
    expect(back.expiresAt, DateTime.utc(2026, 12, 3, 8).toLocal().add(pollKeepAfter));
    final sealed = poll.sealed();
    expect(sealed.contains('Team lunch'), isFalse);
    final open = openForPoll(key: poll.key, pollId: poll.id, part: 'poll', sealed: sealed);
    expect(open['title'], 'Team lunch');
    expect(open['chosen'], DateTime.utc(2026, 12, 2, 8).millisecondsSinceEpoch);
    expect(open['publicKey'], _web['publicKey']);
  });

  test('suggested times: one per day, free, inside working hours', () {
    // Monday 16 November 2026, 12:00.
    final now = DateTime(2026, 11, 16, 12);
    final times = suggestPollTimes(
      events: [
        CalendarEvent(
          id: 'a',
          title: 'Busy',
          start: DateTime(2026, 11, 17, 9),
          end: DateTime(2026, 11, 17, 12),
        ),
      ],
      calendars: const [ZtCalendarInfo.personal],
      hours: {for (var d = 1; d <= 5; d++) d: const [(9 * 60, 17 * 60)]},
      length: const Duration(hours: 1),
      now: now,
    );
    expect(times, [DateTime(2026, 11, 17, 12), DateTime(2026, 11, 18, 10), DateTime(2026, 11, 19, 10)]);
  });

  for (final locale in const [Locale('en'), Locale('he')]) {
    final he = locale.languageCode == 'he';
    testWidgets('a poll shows the answers per time and can pick one ($locale)', (tester) async {
      usePhoneScreen(tester);
      final fake = _FakePolls()..rows = [(id: 'v1', sealed: _web['vote']!, updatedAt: null)];
      final poll = _poll();
      await tester.pumpWidget(app(
        PollDetailsPage(pollId: poll.id),
        const [],
        locale: locale,
        overrides: [
          meetingPollsProvider.overrideWith((ref) => Stream.value([poll])),
          pollBackendProvider.overrideWithValue(fake),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectTappableOnScreen(tester, he ? 'שיתוף הקישור' : 'Share the link');
      // Yes on the first time, maybe on the second.
      expect(find.textContaining(he ? 'כן (1): Dana' : 'Yes (1): Dana'), findsOneWidget);
      expect(find.textContaining(he ? 'אולי (1): Dana' : 'Maybe (1): Dana'), findsOneWidget);
      expect(find.text(he ? 'המוביל כרגע' : 'Best so far'), findsOneWidget);
      final pick = find.text(he ? 'בחירת המועד' : 'Pick this time');
      expect(pick, findsNWidgets(3));
      // Each time's pick button sits below its own answers.
      final first = tester.getRect(find.textContaining('Dana').first);
      expect(tester.getRect(pick.first).top, greaterThan(first.bottom - 1));
    });

    testWidgets('a time can be picked only once the answers are in ($locale)', (tester) async {
      usePhoneScreen(tester);
      final fake = _FakePolls()..votesError = Exception('offline');
      final poll = _poll();
      await tester.pumpWidget(app(
        PollDetailsPage(pollId: poll.id),
        const [],
        locale: locale,
        overrides: [
          meetingPollsProvider.overrideWith((ref) => Stream.value([poll])),
          pollBackendProvider.overrideWithValue(fake),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text(he ? 'בחירת המועד' : 'Pick this time'), findsNothing);
    });

    testWidgets('a new poll suggests three times ($locale)', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(app(const PollEditorPage(), const [], locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.schedule), findsNWidgets(3));
      expectTappableOnScreen(tester, he ? 'יצירה' : 'Create');
      await tester.tap(find.text(he ? 'יצירה' : 'Create'));
      await tester.pump();
      expect(find.text(he ? 'נא לתת לסקר כותרת.' : 'Give the poll a title.'), findsOneWidget);
    });
  }
}
