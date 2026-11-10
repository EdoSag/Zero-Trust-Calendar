import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../model/calendar_event.dart';
import '../model/recurrence.dart';
import '../util/time_zones.dart';

/// One calendar read from an .ics file (Google Calendar's export, Apple,
/// Outlook, Proton): its name and events. Changed occurrences of a series
/// (`RECURRENCE-ID`) come back as exception events with [seriesId] set to
/// their series' id.
class IcsCalendar {
  IcsCalendar({required this.name, required this.events, this.method});
  final String? name;
  final List<CalendarEvent> events;

  /// `REQUEST` for an invitation, `CANCEL` for a cancellation, `PUBLISH`
  /// or null for a plain calendar file.
  final String? method;
}

/// The first video-call link in [text] (Google Meet, Zoom, Teams, Jitsi,
/// Webex, Whereby), or null.
String? findMeetingLink(String text) {
  final m = RegExp(
    r'https://(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com|meet\.jit\.si|[\w.-]*webex\.com|whereby\.com)/[^\s<>"]*',
    caseSensitive: false,
  ).firstMatch(text);
  return m?.group(0);
}

String? _mailto(String v) {
  final t = v.trim();
  final lower = t.toLowerCase();
  if (!lower.startsWith('mailto:')) return null;
  return t.substring(7).trim();
}

/// A content line: `NAME;PARAM=VALUE:value`.
class _Line {
  _Line(this.name, this.params, this.value);
  final String name;
  final Map<String, String> params;
  final String value;
}

abstract final class Ics {
  /// Unfolds lines (RFC 5545 3.1) and splits name, parameters and value.
  static List<_Line> _lines(String text) {
    final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final unfolded = <String>[];
    for (final line in raw.split('\n')) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          unfolded.isNotEmpty) {
        unfolded[unfolded.length - 1] += line.substring(1);
      } else if (line.isNotEmpty) {
        unfolded.add(line);
      }
    }
    final out = <_Line>[];
    for (final line in unfolded) {
      // The value starts at the first ':' outside a quoted parameter.
      var inQuotes = false;
      var colon = -1;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') inQuotes = !inQuotes;
        if (c == ':' && !inQuotes) {
          colon = i;
          break;
        }
      }
      if (colon <= 0) continue;
      final head = line.substring(0, colon).split(';');
      final params = <String, String>{};
      for (final p in head.skip(1)) {
        final eq = p.indexOf('=');
        if (eq > 0) {
          params[p.substring(0, eq).toUpperCase()] = p
              .substring(eq + 1)
              .replaceAll('"', '');
        }
      }
      out.add(_Line(head.first.toUpperCase(), params, line.substring(colon + 1)));
    }
    return out;
  }

  static String _unescape(String v) => v
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');

  static String _escape(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  /// A DTSTART-like value as (local time, is a date).
  static (DateTime, bool)? _time(_Line line) {
    final v = line.value.trim();
    final dm = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
    if (dm != null || line.params['VALUE'] == 'DATE') {
      final m = dm ?? RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(v);
      if (m == null) return null;
      return (
        DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)),
        true,
      );
    }
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$',
    ).firstMatch(v);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i) ?? '0');
    if (m.group(7) != null) {
      return (DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).toLocal(), false);
    }
    final tzid = line.params['TZID'];
    if (tzid != null) {
      final tz.Location? loc = zoneFor(_ianaFor(tzid));
      if (loc != null) {
        final t = tz.TZDateTime(loc, g(1), g(2), g(3), g(4), g(5), g(6));
        return (DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch), false);
      }
    }
    // Floating time, or a zone we don't know: the phone's own time.
    return (DateTime(g(1), g(2), g(3), g(4), g(5), g(6)), false);
  }

  /// Some exporters (Outlook) write Windows zone names or a path prefix.
  static String _ianaFor(String tzid) {
    var id = tzid.trim();
    final slash = RegExp(r'^/[^/]+/[^/]+/').firstMatch(id);
    if (slash != null) id = id.substring(slash.end); // /mozilla.org/.../X
    return _windowsZones[id] ?? id;
  }

  static const _windowsZones = {
    'UTC': 'UTC',
    'GMT Standard Time': 'Europe/London',
    'W. Europe Standard Time': 'Europe/Berlin',
    'Central Europe Standard Time': 'Europe/Budapest',
    'Romance Standard Time': 'Europe/Paris',
    'Central European Standard Time': 'Europe/Warsaw',
    'E. Europe Standard Time': 'Europe/Chisinau',
    'FLE Standard Time': 'Europe/Kiev',
    'GTB Standard Time': 'Europe/Bucharest',
    'Israel Standard Time': 'Asia/Jerusalem',
    'Russian Standard Time': 'Europe/Moscow',
    'Eastern Standard Time': 'America/New_York',
    'Central Standard Time': 'America/Chicago',
    'Mountain Standard Time': 'America/Denver',
    'Pacific Standard Time': 'America/Los_Angeles',
    'India Standard Time': 'Asia/Kolkata',
    'China Standard Time': 'Asia/Shanghai',
    'Tokyo Standard Time': 'Asia/Tokyo',
    'AUS Eastern Standard Time': 'Australia/Sydney',
  };

  /// `-PT15M`, `-P1D`, `-PT1H30M`, `PT0S` as minutes before the start.
  static int? _triggerMinutes(String v) {
    final m = RegExp(
      r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(v.trim());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final minutes = g(2) * 7 * 24 * 60 + g(3) * 24 * 60 + g(4) * 60 + g(5);
    final before = m.group(1) == '-' || minutes == 0;
    return before ? minutes : null; // Reminders after the start: skipped.
  }

  /// An event `DURATION` (`PT1H`, `P2D`, `P1DT30M`) in minutes.
  static int? _durationMinutes(String v) {
    final m = RegExp(
      r'^\+?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(v.trim());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return g(1) * 7 * 24 * 60 + g(2) * 24 * 60 + g(3) * 60 + g(4);
  }

  /// Reads every VEVENT of [text]. Events without a start are skipped.
  static IcsCalendar parse(String text, {String calendarId = CalendarEvent.defaultCalendarId}) {
    final lines = _lines(text);
    String? name;
    final events = <CalendarEvent>[];
    // Series by UID, to attach RECURRENCE-ID exceptions afterwards.
    final seriesByUid = <String, int>{};
    final pendingExceptions = <(String, DateTime, CalendarEvent)>[];

    var depth = <String>[];
    Map<String, _Line> props = {};
    List<_Line> exdates = [];
    List<int> alarms = [];
    List<_Line> attendees = [];
    String? method;
    for (final line in lines) {
      if (line.name == 'BEGIN') {
        depth.add(line.value.toUpperCase());
        if (line.value.toUpperCase() == 'VEVENT') {
          props = {};
          exdates = [];
          alarms = [];
          attendees = [];
        }
        continue;
      }
      if (line.name == 'END') {
        final ended = depth.isEmpty ? '' : depth.removeLast();
        if (ended == 'VEVENT') {
          final event = _event(props, exdates, alarms, attendees, calendarId);
          if (event == null) continue;
          final recurrenceId = props['RECURRENCE-ID'];
          if (recurrenceId != null && event.icalUid != null) {
            final original = _time(recurrenceId)?.$1;
            if (original != null) {
              pendingExceptions.add((event.icalUid!, original, event));
              continue;
            }
          }
          if (event.icalUid != null && event.repeats) {
            seriesByUid[event.icalUid!] = events.length;
          }
          events.add(event);
        }
        continue;
      }
      final inEvent = depth.isNotEmpty && depth.last == 'VEVENT';
      final inAlarm = depth.isNotEmpty && depth.last == 'VALARM';
      if (depth.length == 1 && line.name == 'X-WR-CALNAME') {
        name = _unescape(line.value).trim();
      } else if (depth.length == 1 && line.name == 'METHOD') {
        method = line.value.trim().toUpperCase();
      } else if (inEvent) {
        if (line.name == 'EXDATE') {
          exdates.add(line);
        } else if (line.name == 'ATTENDEE') {
          attendees.add(line);
        } else {
          props[line.name] = line;
        }
      } else if (inAlarm && line.name == 'TRIGGER') {
        if (line.params['VALUE'] != 'DATE-TIME') {
          final minutes = _triggerMinutes(line.value);
          if (minutes != null) alarms.add(minutes);
        }
      }
    }

    for (final (uid, original, ex) in pendingExceptions) {
      final i = seriesByUid[uid];
      if (i == null) {
        events.add(ex); // A lone changed occurrence: keep it as an event.
        continue;
      }
      final series = events[i];
      events[i] = series.copyWith(exceptions: {...series.exceptions, original});
      final cancelled = ex.extra['_status'] == 'CANCELLED';
      if (!cancelled) {
        events.add(ex.copyWith(seriesId: series.id, originalStart: original));
      }
    }
    return IcsCalendar(
      name: name,
      method: method,
      events: [
        for (final e in events)
          if (e.extra['_status'] != 'CANCELLED') _withoutStatus(e),
      ],
    );
  }

  static CalendarEvent _withoutStatus(CalendarEvent e) {
    if (!e.extra.containsKey('_status')) return e;
    return CalendarEvent.fromJson(
      e.id,
      {...e.toJson()}..remove('_status'),
      e.updatedAt,
    )!;
  }

  static CalendarEvent? _event(
    Map<String, _Line> p,
    List<_Line> exdates,
    List<int> alarms,
    List<_Line> attendees,
    String calendarId,
  ) {
    final startLine = p['DTSTART'];
    if (startLine == null) return null;
    final st = _time(startLine);
    if (st == null) return null;
    final (start, allDay) = st;
    DateTime end;
    final endLine = p['DTEND'] ?? p['DUE'];
    final et = endLine == null ? null : _time(endLine);
    if (et != null && et.$1.isAfter(start)) {
      end = et.$1;
    } else if (p['DURATION'] case final _Line d) {
      final minutes = _durationMinutes(d.value) ?? 0;
      end = allDay
          ? DateTime(start.year, start.month, start.day + (minutes / (24 * 60)).ceil())
          : start.add(Duration(minutes: minutes));
    } else {
      end = allDay
          ? DateTime(start.year, start.month, start.day + 1)
          : start;
    }
    if (allDay && !end.isAfter(start)) {
      end = DateTime(start.year, start.month, start.day + 1);
    }
    final rrule = p['RRULE']?.value;
    final rule = RecurrenceRule.tryParse(rrule);
    final status = p['STATUS']?.value.toUpperCase();
    // The event keeps its zone: a repeating one stays on that zone's clock
    // across DST, and the details show its own time when travelling.
    final tzid = startLine.params['TZID'];
    final zone = !allDay && tzid != null && zoneFor(_ianaFor(tzid)) != null
        ? _ianaFor(tzid)
        : null;
    final description = _unescape(p['DESCRIPTION']?.value ?? '').trim();
    final location = _unescape(p['LOCATION']?.value ?? '').trim();
    final conference = p['X-GOOGLE-CONFERENCE']?.value.trim() ??
        p['CONFERENCE']?.value.trim() ??
        findMeetingLink(location) ??
        findMeetingLink(description);
    return CalendarEvent(
      id: const Uuid().v4(),
      title: _unescape(p['SUMMARY']?.value ?? '').trim(),
      start: start,
      end: end,
      allDay: allDay,
      calendarId: calendarId,
      description: description,
      location: location,
      conferenceUrl: conference,
      guestEmails: [
        for (final a in attendees)
          if (_mailto(a.value) case final email? when email.isNotEmpty) email,
      ],
      rrule: rule?.toString(),
      exceptions: {
        for (final line in exdates)
          for (final v in line.value.split(','))
            if (_time(_Line('EXDATE', line.params, v)) case (final t, _)) t,
      },
      reminders: alarms.toSet().toList()..sort(),
      icalUid: p['UID']?.value.trim(),
      timeZone: zone,
      createdAt: DateTime.now(),
      extra: status == 'CANCELLED' ? {'_status': 'CANCELLED'} : const {},
    );
  }

  /// Writes [events] as an .ics file other calendars can import.
  static String write(
    Iterable<CalendarEvent> events, {
    String name = 'ZT Calendar',
    DateTime? now,
    IcsInvite? invite,
  }) {
    final stamp = _utc(now ?? DateTime.now());
    final out = StringBuffer()
      ..write('BEGIN:VCALENDAR\r\n')
      ..write('VERSION:2.0\r\n')
      ..write('PRODID:-//Zero-Trust//ZT Calendar//EN\r\n')
      ..write('CALSCALE:GREGORIAN\r\n');
    if (invite != null) out.write('METHOD:REQUEST\r\n');
    _fold(out, 'X-WR-CALNAME:${_escape(name)}');
    final all = events.toList();
    final byId = {for (final e in all) e.id: e};
    for (final e in all) {
      final uid = e.icalUid ?? '${e.id}@zt-calendar';
      out.write('BEGIN:VEVENT\r\n');
      if (e.seriesId != null && byId[e.seriesId] != null) {
        final series = byId[e.seriesId]!;
        _fold(out, 'UID:${series.icalUid ?? '${series.id}@zt-calendar'}');
        final orig = e.originalStart!;
        _fold(
          out,
          series.allDay
              ? 'RECURRENCE-ID;VALUE=DATE:${_date(orig)}'
              : 'RECURRENCE-ID:${_utc(orig)}',
        );
      } else {
        _fold(out, 'UID:$uid');
      }
      out.write('DTSTAMP:$stamp\r\n');
      if (e.allDay) {
        out.write('DTSTART;VALUE=DATE:${_date(e.start)}\r\n');
        out.write('DTEND;VALUE=DATE:${_date(e.end)}\r\n');
      } else if (zoneFor(e.timeZone) case final zone?) {
        out.write('DTSTART;TZID=${e.timeZone}:${_wall(zone, e.start)}\r\n');
        out.write('DTEND;TZID=${e.timeZone}:${_wall(zone, e.end)}\r\n');
      } else {
        out.write('DTSTART:${_utc(e.start)}\r\n');
        out.write('DTEND:${_utc(e.end)}\r\n');
      }
      _fold(out, 'SUMMARY:${_escape(e.title)}');
      if (e.location.isNotEmpty) _fold(out, 'LOCATION:${_escape(e.location)}');
      final call = e.conferenceUrl;
      // Most calendars don't read CONFERENCE yet, so the link also goes in
      // the description.
      final description = call != null && !e.description.contains(call)
          ? [if (e.description.isNotEmpty) e.description, 'Join: $call'].join('\n\n')
          : e.description;
      if (description.isNotEmpty) {
        _fold(out, 'DESCRIPTION:${_escape(description)}');
      }
      if (call != null) {
        _fold(out, 'CONFERENCE;VALUE=URI;FEATURE=VIDEO:$call');
      }
      if (invite != null) {
        out.write('SEQUENCE:${e.inviteSequence}\r\n');
        out.write('STATUS:CONFIRMED\r\n');
        final org = invite.organizerEmail;
        if (org != null && org.isNotEmpty) {
          _fold(
            out,
            'ORGANIZER${invite.organizerName == null ? '' : ';CN=${_param(invite.organizerName!)}'}:mailto:$org',
          );
        }
        for (final (guestName, email) in invite.guests) {
          _fold(
            out,
            'ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE'
            '${guestName == null ? '' : ';CN=${_param(guestName)}'}:mailto:$email',
          );
        }
      }
      if (e.rrule != null) _fold(out, 'RRULE:${e.rrule}');
      for (final x in (e.exceptions.toList()..sort())) {
        final zone = zoneFor(e.timeZone);
        out.write(
          e.allDay
              ? 'EXDATE;VALUE=DATE:${_date(x)}\r\n'
              : zone != null
              ? 'EXDATE;TZID=${e.timeZone}:${_wall(zone, x)}\r\n'
              : 'EXDATE:${_utc(x)}\r\n',
        );
      }
      for (final m in e.reminders) {
        out
          ..write('BEGIN:VALARM\r\n')
          ..write('ACTION:DISPLAY\r\n')
          ..write('DESCRIPTION:Reminder\r\n')
          ..write('TRIGGER:-PT${m}M\r\n')
          ..write('END:VALARM\r\n');
      }
      out.write('END:VEVENT\r\n');
    }
    out.write('END:VCALENDAR\r\n');
    return out.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// A parameter value, quoted when it holds `:;,`.
  static String _param(String v) {
    final clean = v.replaceAll('"', "'");
    return RegExp('[:;,]').hasMatch(clean) ? '"$clean"' : clean;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _wall(tz.Location zone, DateTime t) {
    final w = wallClockIn(zone, t);
    return '${_date(w)}T${_two(w.hour)}${_two(w.minute)}${_two(w.second)}';
  }

  static String _utc(DateTime t) {
    final u = t.toUtc();
    return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  /// Folds a content line at 75 octets (RFC 5545 3.1), on character
  /// boundaries.
  static void _fold(StringBuffer out, String line) {
    var rest = line;
    var first = true;
    while (true) {
      final limit = first ? 75 : 74;
      if (_utf8Length(rest) <= limit) {
        out.write(first ? rest : ' $rest');
        out.write('\r\n');
        return;
      }
      var cut = 0;
      var bytes = 0;
      for (final rune in rest.runes) {
        final len = rune < 0x80 ? 1 : rune < 0x800 ? 2 : rune < 0x10000 ? 3 : 4;
        if (bytes + len > limit) break;
        bytes += len;
        cut += rune > 0xFFFF ? 2 : 1;
      }
      out.write(first ? rest.substring(0, cut) : ' ${rest.substring(0, cut)}');
      out.write('\r\n');
      rest = rest.substring(cut);
      first = false;
    }
  }

  static int _utf8Length(String s) {
    var n = 0;
    for (final rune in s.runes) {
      n += rune < 0x80 ? 1 : rune < 0x800 ? 2 : rune < 0x10000 ? 3 : 4;
    }
    return n;
  }
}

/// Who an emailed invitation is from and to (iCalendar METHOD:REQUEST).
class IcsInvite {
  const IcsInvite({
    required this.organizerEmail,
    this.organizerName,
    required this.guests,
  });

  final String? organizerEmail;
  final String? organizerName;

  /// (name or null, email).
  final List<(String?, String)> guests;
}
