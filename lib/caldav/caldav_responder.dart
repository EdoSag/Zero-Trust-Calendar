import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';

import '../ics/ics.dart';
import '../model/calendar_event.dart';

/// One calendar the bridge offers to desktop apps.
@immutable
class DavCalendar {
  const DavCalendar({required this.info, required this.events});
  final ZtCalendarInfo info;

  /// The calendar's events: series, single events and changed occurrences.
  final List<CalendarEvent> events;
}

/// A request as the bridge received it.
@immutable
class DavRequest {
  const DavRequest({
    required this.method,
    required this.path,
    this.depth,
    this.body = '',
  });
  final String method;
  final String path;

  /// The `Depth` header: '0', '1' or 'infinity'; null when absent.
  final String? depth;
  final String body;
}

@immutable
class DavResponse {
  const DavResponse(this.status, {this.headers = const {}, this.body = ''});
  final int status;
  final Map<String, String> headers;
  final String body;
}

/// A read-only CalDAV server's answers (K16), as pure functions of the
/// request and the calendars, so they are tested without a network.
///
/// Layout:
/// - `/` and `/.well-known/caldav` point at the principal;
/// - `/principal/` names the calendar home;
/// - `/calendars/` lists one collection per calendar;
/// - `/calendars/<id>/` holds one `.ics` resource per event or series
///   (with its changed occurrences);
/// - `GET /calendars/<id>/` returns the whole calendar as one .ics, for apps
///   that only subscribe to a link.
///
/// Writes (PUT, DELETE, MKCALENDAR, PROPPATCH…) are refused: desktop apps
/// read, the phone stays the only place events are changed.
class CalDavResponder {
  CalDavResponder(this.calendars, {DateTime? now})
    : _now = now ?? DateTime.now();

  final List<DavCalendar> calendars;
  final DateTime _now;

  static const _xml = 'application/xml; charset=utf-8';
  static const _dav = '1, 3, calendar-access';
  static const _allow = 'OPTIONS, GET, HEAD, PROPFIND, REPORT';

  /// A calendar's path segment: its id, made URL-safe.
  static String segment(String calendarId) =>
      Uri.encodeComponent(calendarId.replaceAll(':', '-'));

  DavCalendar? _calendar(String seg) {
    for (final c in calendars) {
      if (segment(c.info.id) == seg) return c;
    }
    return null;
  }

  DavResponse handle(DavRequest r) {
    final path = Uri.decodeFull(r.path.split('?').first);
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (r.method == 'OPTIONS') {
      return const DavResponse(200, headers: {'DAV': _dav, 'Allow': _allow});
    }
    if (!const {'GET', 'HEAD', 'PROPFIND', 'REPORT'}.contains(r.method)) {
      return const DavResponse(
        403,
        headers: {'Allow': _allow},
        body: 'ZT Calendar shares events read-only. Change them on the phone.',
      );
    }
    if (parts.length >= 2 &&
        parts[0] == '.well-known' &&
        parts[1] == 'caldav') {
      return const DavResponse(301, headers: {'Location': '/principal/'});
    }
    if (parts.isEmpty || parts[0] == 'principal') {
      if (r.method != 'PROPFIND') {
        return r.method == 'GET'
            ? const DavResponse(
                200,
                headers: {'Content-Type': 'text/plain; charset=utf-8'},
                body:
                    'ZT Calendar desktop bridge. Add this address as a '
                    'CalDAV account in your calendar app.',
              )
            : const DavResponse(405);
      }
      return _multistatus([_principal(parts.isEmpty ? '/' : '/principal/')]);
    }
    if (parts[0] != 'calendars') return const DavResponse(404);
    if (parts.length == 1) {
      if (r.method != 'PROPFIND') return const DavResponse(405);
      return _multistatus([
        _home(),
        if (r.depth != '0')
          for (final c in calendars) _collection(c),
      ]);
    }
    final cal = _calendar(parts[1]);
    if (cal == null) return const DavResponse(404);
    if (parts.length == 2) {
      switch (r.method) {
        case 'GET' || 'HEAD':
          return DavResponse(
            200,
            headers: {
              'Content-Type': 'text/calendar; charset=utf-8',
              'ETag': '"${_ctag(cal)}"',
            },
            body: r.method == 'HEAD'
                ? ''
                : Ics.write(cal.events, name: cal.info.name, now: _now),
          );
        case 'PROPFIND':
          return _multistatus([
            _collection(cal),
            if (r.depth != '0')
              for (final res in _resources(cal)) _resource(cal, res, false),
          ]);
        default: // REPORT
          return _report(cal, r.body);
      }
    }
    final name = parts[2];
    final res = _resources(cal).where((x) => x.name == name).firstOrNull;
    if (res == null) return const DavResponse(404);
    switch (r.method) {
      case 'GET' || 'HEAD':
        final ics = res.ics(cal, _now);
        return DavResponse(
          200,
          headers: {
            'Content-Type': 'text/calendar; charset=utf-8',
            'ETag': '"${res.etag(cal)}"',
          },
          body: r.method == 'HEAD' ? '' : ics,
        );
      case 'PROPFIND':
        return _multistatus([_resource(cal, res, false)]);
      default:
        return const DavResponse(405);
    }
  }

  // ---- resources --------------------------------------------------------

  /// One .ics resource per series or single event; changed occurrences go
  /// with their series (CalDAV keeps a series and its overrides together).
  List<_Resource> _resources(DavCalendar cal) {
    final byId = {for (final e in cal.events) e.id: e};
    final groups = <String, List<CalendarEvent>>{};
    for (final e in cal.events) {
      final owner = e.seriesId != null && byId.containsKey(e.seriesId)
          ? e.seriesId!
          : e.id;
      (groups[owner] ??= []).add(e);
    }
    return [
      for (final MapEntry(:key, :value) in groups.entries)
        _Resource('${_safe(key)}.ics', _ordered(byId[key]!, value)),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The series first, without EXDATEs for occurrences that have an
  /// override in the same resource (RFC 5545: an override replaces it).
  static List<CalendarEvent> _ordered(
    CalendarEvent owner,
    List<CalendarEvent> group,
  ) {
    final overrides = {
      for (final e in group)
        if (e.id != owner.id && e.originalStart != null) e.originalStart!,
    };
    return [
      owner.copyWith(exceptions: owner.exceptions.difference(overrides)),
      for (final e in group)
        if (e.id != owner.id) e,
    ];
  }

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');

  static String _digest(String text) =>
      hash.sha256.convert(utf8.encode(text)).toString().substring(0, 24);

  String _ctag(DavCalendar cal) => _digest(
    '${cal.info.name}|${cal.info.color}|'
    '${[for (final r in _resources(cal)) r.etag(cal)].join(',')}',
  );

  // ---- XML --------------------------------------------------------------

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _color(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}FF';

  DavResponse _multistatus(List<String> responses) => DavResponse(
    207,
    headers: const {'Content-Type': _xml, 'DAV': _dav},
    body:
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
        'xmlns:cs="http://calendarserver.org/ns/" '
        'xmlns:ic="http://apple.com/ns/ical/">'
        '${responses.join()}</d:multistatus>',
  );

  static String _ok(String href, String props) =>
      '<d:response><d:href>${_esc(href)}</d:href><d:propstat><d:prop>'
      '$props</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';

  static const _principalProps =
      '<d:current-user-principal><d:href>/principal/</d:href>'
      '</d:current-user-principal>'
      '<d:principal-URL><d:href>/principal/</d:href></d:principal-URL>'
      '<c:calendar-home-set><d:href>/calendars/</d:href></c:calendar-home-set>'
      '<d:displayname>ZT Calendar</d:displayname>';

  String _principal(String href) => _ok(
    href,
    '<d:resourcetype><d:principal/></d:resourcetype>$_principalProps',
  );

  String _home() => _ok(
    '/calendars/',
    '<d:resourcetype><d:collection/></d:resourcetype>'
        '<d:displayname>ZT Calendar</d:displayname>$_principalProps',
  );

  String _collection(DavCalendar c) => _ok(
    '/calendars/${segment(c.info.id)}/',
    '<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>'
        '<d:displayname>${_esc(c.info.name)}</d:displayname>'
        '<ic:calendar-color>${_color(c.info.color)}</ic:calendar-color>'
        '<cs:getctag>${_ctag(c)}</cs:getctag>'
        '<d:sync-token>${_ctag(c)}</d:sync-token>'
        '<c:supported-calendar-component-set><c:comp name="VEVENT"/>'
        '</c:supported-calendar-component-set>'
        '<d:current-user-privilege-set><d:privilege><d:read/></d:privilege>'
        '</d:current-user-privilege-set>'
        '$_principalProps',
  );

  String _resource(DavCalendar cal, _Resource r, bool withData) => _ok(
    '/calendars/${segment(cal.info.id)}/${r.name}',
    '<d:resourcetype/>'
        '<d:getcontenttype>text/calendar; charset=utf-8; component=vevent'
        '</d:getcontenttype>'
        '<d:getetag>"${r.etag(cal)}"</d:getetag>'
        '${withData ? '<c:calendar-data>${_esc(r.ics(cal, _now))}</c:calendar-data>' : ''}',
  );

  /// calendar-multiget (the hrefs asked for) and calendar-query (every
  /// event; time-range filters are left to the app). Both return data.
  DavResponse _report(DavCalendar cal, String body) {
    final all = _resources(cal);
    if (body.contains('calendar-multiget')) {
      final hrefs = RegExp(r'<(?:[A-Za-z0-9_-]+:)?href>([^<]*)</')
          .allMatches(body)
          .map((m) => Uri.decodeFull(m.group(1)!.trim()).split('/').last)
          .toSet();
      return _multistatus([
        for (final r in all)
          if (hrefs.contains(r.name)) _resource(cal, r, true),
        for (final h in hrefs)
          if (!all.any((r) => r.name == h))
            '<d:response><d:href>${_esc('/calendars/${segment(cal.info.id)}/$h')}'
                '</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response>',
      ]);
    }
    if (body.contains('sync-collection')) {
      // No change history on the phone: answer with everything and the
      // current token, which every app accepts as a full resync.
      return DavResponse(
        207,
        headers: const {'Content-Type': _xml, 'DAV': _dav},
        body: _multistatus([for (final r in all) _resource(cal, r, false)]).body
            .replaceFirst(
              '</d:multistatus>',
              '<d:sync-token>${_ctag(cal)}</d:sync-token></d:multistatus>',
            ),
      );
    }
    final withData = body.contains('calendar-data');
    return _multistatus([for (final r in all) _resource(cal, r, withData)]);
  }
}

class _Resource {
  _Resource(this.name, this.events);
  final String name;
  final List<CalendarEvent> events;
  String? _ics;

  String ics(DavCalendar cal, DateTime now) =>
      _ics ??= Ics.write(events, name: cal.info.name, now: now);

  /// Changes whenever the events do (not on DTSTAMP).
  String etag(DavCalendar cal) => CalDavResponder._digest(
    Ics.write(events, name: '', now: DateTime.utc(2000)),
  );
}
