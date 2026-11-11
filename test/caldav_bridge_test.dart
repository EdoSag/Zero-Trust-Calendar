import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/caldav/caldav_bridge.dart';
import 'package:zerotrust_calendar/caldav/caldav_responder.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';

void main() {
  final series = CalendarEvent(
    id: 'standup',
    title: 'Stand-up & coffee',
    start: DateTime.utc(2026, 11, 9, 9),
    end: DateTime.utc(2026, 11, 9, 9, 15),
    rrule: 'FREQ=WEEKLY;BYDAY=MO',
    exceptions: {DateTime.utc(2026, 11, 16, 9)},
  );
  final moved = CalendarEvent(
    id: 'standup-moved',
    title: 'Stand-up (late)',
    start: DateTime.utc(2026, 11, 16, 10),
    end: DateTime.utc(2026, 11, 16, 10, 15),
    seriesId: 'standup',
    originalStart: DateTime.utc(2026, 11, 16, 9),
  );
  final dentist = CalendarEvent(
    id: 'dentist',
    title: 'Dentist',
    start: DateTime.utc(2026, 11, 12, 15),
    end: DateTime.utc(2026, 11, 12, 16),
  );
  final responder = CalDavResponder([
    DavCalendar(
      info: const ZtCalendarInfo(
        id: 'default',
        name: 'Personal',
        color: 0xFFF97316,
      ),
      events: [series, moved, dentist],
    ),
    const DavCalendar(
      info: ZtCalendarInfo(
        id: 'shared:abc',
        name: 'Family <3',
        color: 0xFF10B981,
      ),
      events: [],
    ),
  ], now: DateTime.utc(2026, 11, 11));

  DavResponse ask(
    String method,
    String path, {
    String? depth,
    String body = '',
  }) => responder.handle(
    DavRequest(method: method, path: path, depth: depth, body: body),
  );

  test('discovery: well-known, principal, home, collections', () {
    expect(
      ask('GET', '/.well-known/caldav').headers['Location'],
      '/principal/',
    );
    expect(ask('OPTIONS', '/').headers['DAV'], contains('calendar-access'));
    final root = ask('PROPFIND', '/', depth: '0');
    expect(root.status, 207);
    expect(
      root.body,
      contains('<c:calendar-home-set><d:href>/calendars/</d:href>'),
    );
    final home = ask('PROPFIND', '/calendars/', depth: '1');
    expect(home.body, contains('<d:href>/calendars/default/</d:href>'));
    expect(home.body, contains('<d:href>/calendars/shared-abc/</d:href>'));
    expect(home.body, contains('<d:displayname>Family &lt;3</d:displayname>'));
    expect(
      home.body,
      contains('<ic:calendar-color>#10B981FF</ic:calendar-color>'),
    );
    expect(
      ask('PROPFIND', '/calendars/', depth: '0').body,
      isNot(contains('/calendars/default/')),
    );
  });

  test('a series and its moved occurrence are one resource', () {
    final list = ask('PROPFIND', '/calendars/default/', depth: '1');
    expect(list.body, contains('/calendars/default/standup.ics'));
    expect(list.body, contains('/calendars/default/dentist.ics'));
    expect(list.body, isNot(contains('standup-moved.ics')));
    final ics = ask('GET', '/calendars/default/standup.ics').body;
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    expect(ics, contains('RECURRENCE-ID:20261116T090000Z'));
    // The override replaces the occurrence; it isn't also excluded.
    expect(ics, isNot(contains('EXDATE')));
  });

  test('sync-collection: full list, then nothing, old tokens refused', () {
    String sync(String token) =>
        '<d:sync-collection xmlns:d="DAV:">'
        '<d:sync-token>$token</d:sync-token><d:sync-level>1</d:sync-level>'
        '<d:prop><d:getetag/></d:prop></d:sync-collection>';
    final first = ask('REPORT', '/calendars/default/', body: sync(''));
    expect(first.status, 207);
    expect(first.body, contains('dentist.ics'));
    final token = RegExp(
      r'<d:sync-token>([^<]+)</',
    ).firstMatch(first.body)!.group(1)!;
    expect(token, startsWith('urn:'));
    final same = ask('REPORT', '/calendars/default/', body: sync(token));
    expect(same.status, 207);
    expect(same.body, isNot(contains('dentist.ics')));
    expect(same.body, contains(token));
    // A token from before a change (e.g. an event deleted on the phone)
    // makes the app start over, so it drops what is gone.
    final stale = ask(
      'REPORT',
      '/calendars/default/',
      body: sync('urn:zt-calendar:sync:old'),
    );
    expect(stale.status, 403);
    expect(stale.body, contains('valid-sync-token'));
  });

  test('multiget returns the asked events with data; etags are stable', () {
    final r = ask(
      'REPORT',
      '/calendars/default/',
      body: '''
<c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <d:href>/calendars/default/dentist.ics</d:href>
  <d:href>/calendars/default/missing.ics</d:href>
</c:calendar-multiget>''',
    );
    expect(r.status, 207);
    expect(r.body, contains('SUMMARY:Dentist'));
    expect(r.body, isNot(contains('Stand-up')));
    expect(r.body, contains('404 Not Found'));
    final again = CalDavResponder(responder.calendars, now: DateTime.utc(2030))
        .handle(
          const DavRequest(
            method: 'PROPFIND',
            path: '/calendars/default/',
            depth: '1',
          ),
        );
    expect(again.body, ask('PROPFIND', '/calendars/default/', depth: '1').body);
  });

  test('read-only: writes are refused, unknown paths 404', () {
    for (final m in ['PUT', 'DELETE', 'MKCALENDAR', 'PROPPATCH', 'MOVE']) {
      expect(ask(m, '/calendars/default/dentist.ics').status, 403);
    }
    expect(ask('GET', '/calendars/nope/').status, 404);
    expect(ask('GET', '/calendars/default/nope.ics').status, 404);
    expect(ask('GET', '/etc/passwd').status, 404);
    final whole = ask('GET', '/calendars/default/');
    expect(whole.headers['Content-Type'], startsWith('text/calendar'));
    expect(whole.body, contains('X-WR-CALNAME:Personal'));
  });

  test('basic auth is exact; throttle locks out after five failures', () {
    String header(String u, String p) =>
        'Basic ${base64.encode(utf8.encode('$u:$p'))}';
    expect(
      checkBasicAuth(header('zt', 'abcd-efgh'), 'zt', 'abcd-efgh'),
      isTrue,
    );
    expect(
      checkBasicAuth(header('zt', 'abcd-efg'), 'zt', 'abcd-efgh'),
      isFalse,
    );
    expect(
      checkBasicAuth(header('zt', 'abcd-efghi'), 'zt', 'abcd-efgh'),
      isFalse,
    );
    expect(checkBasicAuth('Bearer x', 'zt', 'p'), isFalse);
    expect(checkBasicAuth('Basic !!!', 'zt', 'p'), isFalse);
    expect(checkBasicAuth(null, 'zt', 'p'), isFalse);

    var now = DateTime(2026);
    final t = LoginThrottle(clock: () => now);
    for (var i = 0; i < 5; i++) {
      expect(t.blocked('10.0.0.2'), isFalse);
      t.failed('10.0.0.2');
    }
    expect(t.blocked('10.0.0.2'), isTrue);
    expect(t.blocked('10.0.0.3'), isFalse);
    now = now.add(const Duration(minutes: 6));
    expect(t.blocked('10.0.0.2'), isFalse);
  });

  test('only local network addresses are answered', () {
    for (final a in [
      '192.168.1.5',
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.1',
      '127.0.0.1',
      'fe80::1',
      'fd12::1',
    ]) {
      expect(isLocalAddress(InternetAddress(a)), isTrue, reason: a);
    }
    for (final a in ['8.8.8.8', '172.32.0.1', '100.64.0.1', '2a00:1450::1']) {
      expect(isLocalAddress(InternetAddress(a)), isFalse, reason: a);
    }
  });

  test('passwords are long, grouped and without look-alikes', () {
    final p = BridgeCredentials.newPassword();
    expect(p, matches(RegExp(r'^[a-z2-9]{4}(-[a-z2-9]{4}){4}$')));
    expect(p, isNot(contains(RegExp('[01ilo]'))));
  });

  test('the server answers over TLS only with the password', () async {
    final creds = BridgeCredentials.create();
    expect(
      creds.fingerprint,
      matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
    );
    final server = CalDavServer(
      credentials: creds,
      snapshot: () => responder.calendars,
      port: 0,
    );
    await server.start();
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    Future<(int, String)> get(String? auth) async {
      final req = await client.openUrl(
        'PROPFIND',
        Uri.parse('https://127.0.0.1:${server.boundPort}/calendars/'),
      );
      req.headers.set('Depth', '1');
      if (auth != null) req.headers.set('Authorization', auth);
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    expect((await get(null)).$1, 401);
    final ok = await get(
      'Basic ${base64.encode(utf8.encode('zt:${creds.password}'))}',
    );
    expect(ok.$1, 207);
    expect(ok.$2, contains('Family &lt;3'));
    client.close(force: true);
    await server.stop();
  });
}
