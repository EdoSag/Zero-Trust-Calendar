import 'package:flutter/foundation.dart';

import '../util/time_zones.dart';
import 'recurrence.dart';

/// One event, or one repeating series of events.
///
/// Stored as one encrypted item in the account's Calendar store. Times of
/// timed events are kept as UTC instants; all-day events keep plain dates
/// (`2026-11-10`), so they stay on the same day in every time zone. In
/// memory, [start] and [end] are local times; for an all-day event they are
/// local midnights and [end] is exclusive (the day after the last day).
///
/// A change to one occurrence of a series is its own event, with [seriesId]
/// and [originalStart] pointing back at the occurrence it replaces; the
/// series lists that start in [exceptions] so it isn't shown twice.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.calendarId = defaultCalendarId,
    this.description = '',
    this.location = '',
    this.color,
    this.rrule,
    this.exceptions = const {},
    this.seriesId,
    this.originalStart,
    this.reminders = const [],
    this.noteIds = const [],
    this.contactIds = const [],
    this.taskIds = const [],
    this.icalUid,
    this.timeZone,
    this.createdAt,
    this.updatedAt,
    this.extra = const {},
  });

  static const defaultCalendarId = 'default';

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendarId;
  final String description;
  final String location;

  /// ARGB colour overriding the calendar's, or null.
  final int? color;

  /// RFC 5545 RRULE text without the `RRULE:` prefix, or null.
  final String? rrule;

  /// Starts of occurrences removed from (or moved out of) the series.
  final Set<DateTime> exceptions;

  /// For a changed occurrence: the series it belongs to.
  final String? seriesId;

  /// For a changed occurrence: the start it had in the series.
  final DateTime? originalStart;

  /// Minutes before the start. For all-day events, before 9:00 that day.
  final List<int> reminders;

  /// Linked ZT Notes notes, ZT Contacts contacts (guests) and ZT Tasks tasks.
  final List<String> noteIds;
  final List<String> contactIds;
  final List<String> taskIds;

  /// UID from an imported .ics file, so importing again doesn't duplicate.
  final String? icalUid;

  /// IANA zone a repeating event was created in ("Europe/Berlin", from an
  /// imported .ics). Its occurrences keep that zone's wall-clock time, so a
  /// 9:00 Berlin meeting stays at 9:00 Berlin across daylight-saving changes
  /// even on a phone in another zone. Null: the phone's own zone.
  final String? timeZone;
  final DateTime? createdAt;

  /// Last edit time from sync (not stored in the JSON).
  final DateTime? updatedAt;

  /// Keys a newer app version wrote; written back unchanged.
  final Map<String, Object?> extra;

  Duration get duration => end.difference(start);
  bool get repeats => recurrence != null;
  RecurrenceRule? get recurrence => RecurrenceRule.tryParse(rrule);
  bool get isException => seriesId != null;

  /// The occurrences of this event that overlap `[from, to)`, as
  /// (start, end) pairs in local time.
  List<(DateTime, DateTime)> occurrencesBetween(DateTime from, DateTime to) {
    final d = duration;
    final rule = recurrence;
    if (rule == null) {
      return start.isBefore(to) && end.isAfter(from) ? [(start, end)] : [];
    }
    return [
      for (final s in occurrenceStarts(from.subtract(d), to))
        if (_endFor(s, d).isAfter(from) || s == from) (s, _endFor(s, d)),
    ];
  }

  /// Starts of the series' occurrences in `[from, to)`, without
  /// [exceptions], expanded in [timeZone] when it has one.
  List<DateTime> occurrenceStarts(DateTime from, DateTime to) {
    final rule = recurrence;
    if (rule == null) {
      return !start.isBefore(from) && start.isBefore(to) ? [start] : [];
    }
    final zone = allDay ? null : zoneFor(timeZone);
    if (zone == null) return rule.between(start, from, to, exclude: exceptions);
    // Expand on the zone's wall clock, then turn each back into an instant.
    const slack = Duration(days: 2);
    return [
      for (final w in rule.between(
        wallClockIn(zone, start),
        wallClockIn(zone, from).subtract(slack),
        wallClockIn(zone, to).add(slack),
      ))
        if (instantFromWall(zone, w) case final t
            when !t.isBefore(from) && t.isBefore(to) && !exceptions.contains(t))
          t,
    ];
  }

  /// All-day occurrences keep their length in days, not hours (a DST change
  /// inside a two-day event mustn't shift its end off midnight).
  DateTime _endFor(DateTime s, Duration d) {
    if (!allDay) return s.add(d);
    final days = (d.inHours / 24).round();
    return DateTime(s.year, s.month, s.day + days);
  }

  /// The next start at or after [after], or null.
  DateTime? nextStart(DateTime after) {
    if (recurrence == null) return start.isBefore(after) ? null : start;
    return occurrenceStarts(after, after.add(const Duration(days: 3660))).firstOrNull;
  }

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    return DateTime.tryParse(v)?.toLocal();
  }

  String _timeKey(DateTime t) =>
      allDay ? dateKey(t) : t.toUtc().toIso8601String();

  static const _knownKeys = {
    'title',
    'start',
    'end',
    'allDay',
    'calendarId',
    'description',
    'location',
    'color',
    'rrule',
    'exdates',
    'seriesId',
    'originalStart',
    'reminders',
    'noteIds',
    'contactIds',
    'taskIds',
    'icalUid',
    'tz',
    'createdAt',
    'kind',
    '_v',
  };

  Map<String, Object?> toJson() => {
    ...extra,
    'title': title,
    'start': _timeKey(start),
    'end': _timeKey(end),
    'allDay': allDay,
    'calendarId': calendarId,
    'description': description,
    'location': location,
    'color': color,
    'rrule': rrule,
    'exdates': ([for (final e in exceptions) _timeKey(e)]..sort()),
    'seriesId': seriesId,
    'originalStart': originalStart == null ? null : _timeKey(originalStart!),
    'reminders': reminders,
    'noteIds': noteIds,
    'contactIds': contactIds,
    'taskIds': taskIds,
    'icalUid': icalUid,
    'tz': timeZone,
    'createdAt': createdAt?.toUtc().toIso8601String(),
  };

  static CalendarEvent? fromJson(
    String id,
    Map<String, Object?> json,
    DateTime? updatedAt,
  ) {
    final start = _parseDate(json['start']);
    var end = _parseDate(json['end']);
    if (start == null) return null;
    final allDay = json['allDay'] == true;
    if (end == null || end.isBefore(start)) {
      end = allDay
          ? DateTime(start.year, start.month, start.day + 1)
          : start.add(const Duration(hours: 1));
    }
    List<String> strings(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is String) e,
    ];
    return CalendarEvent(
      id: id,
      title: (json['title'] as String?) ?? '',
      start: start,
      end: end,
      allDay: allDay,
      calendarId: (json['calendarId'] as String?) ?? defaultCalendarId,
      description: (json['description'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      color: (json['color'] as num?)?.toInt(),
      rrule: json['rrule'] as String?,
      exceptions: {
        for (final s in strings(json['exdates']))
          if (_parseDate(s) case final DateTime d) d,
      },
      seriesId: json['seriesId'] as String?,
      originalStart: _parseDate(json['originalStart']),
      reminders: [
        if (json['reminders'] case final List list)
          for (final r in list)
            if (r is num) r.toInt(),
      ],
      noteIds: strings(json['noteIds']),
      contactIds: strings(json['contactIds']),
      taskIds: strings(json['taskIds']),
      icalUid: json['icalUid'] as String?,
      timeZone: json['tz'] as String?,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: updatedAt,
      extra: {
        for (final e in json.entries)
          if (!_knownKeys.contains(e.key)) e.key: e.value,
      },
    );
  }

  static const _unset = Object();

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? calendarId,
    String? description,
    String? location,
    Object? color = _unset,
    Object? rrule = _unset,
    Set<DateTime>? exceptions,
    Object? seriesId = _unset,
    Object? originalStart = _unset,
    List<int>? reminders,
    List<String>? noteIds,
    List<String>? contactIds,
    List<String>? taskIds,
    Object? icalUid = _unset,
    Object? timeZone = _unset,
    DateTime? createdAt,
  }) => CalendarEvent(
    id: id ?? this.id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    calendarId: calendarId ?? this.calendarId,
    description: description ?? this.description,
    location: location ?? this.location,
    color: identical(color, _unset) ? this.color : color as int?,
    rrule: identical(rrule, _unset) ? this.rrule : rrule as String?,
    exceptions: exceptions ?? this.exceptions,
    seriesId: identical(seriesId, _unset) ? this.seriesId : seriesId as String?,
    originalStart: identical(originalStart, _unset)
        ? this.originalStart
        : originalStart as DateTime?,
    reminders: reminders ?? this.reminders,
    noteIds: noteIds ?? this.noteIds,
    contactIds: contactIds ?? this.contactIds,
    taskIds: taskIds ?? this.taskIds,
    icalUid: identical(icalUid, _unset) ? this.icalUid : icalUid as String?,
    timeZone: identical(timeZone, _unset) ? this.timeZone : timeZone as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt,
    extra: extra,
  );
}

/// A calendar: a named, coloured group of events ("Personal", "Work").
@immutable
class ZtCalendarInfo {
  const ZtCalendarInfo({
    required this.id,
    required this.name,
    required this.color,
    this.hidden = false,
  });

  final String id;
  final String name;
  final int color;

  /// Hidden calendars' events aren't shown (this setting syncs).
  final bool hidden;

  static const defaultColor = 0xFFF97316;

  static const personal = ZtCalendarInfo(
    id: CalendarEvent.defaultCalendarId,
    name: 'Personal',
    color: defaultColor,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'color': color,
    'hidden': hidden,
  };

  static ZtCalendarInfo fromJson(String id, Map<String, Object?> json) =>
      ZtCalendarInfo(
        id: id,
        name: (json['name'] as String?) ?? 'Calendar',
        color: (json['color'] as num?)?.toInt() ?? defaultColor,
        hidden: json['hidden'] == true,
      );

  ZtCalendarInfo copyWith({String? name, int? color, bool? hidden}) =>
      ZtCalendarInfo(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        hidden: hidden ?? this.hidden,
      );
}

/// Colours offered for calendars and events.
const List<int> calendarPalette = [
  0xFFF97316, // orange (ZT Calendar)
  0xFFEF4444, // red
  0xFFEC4899, // pink
  0xFF8B5CF6, // violet
  0xFF6366F1, // indigo
  0xFF3B82F6, // blue
  0xFF06B6D4, // cyan
  0xFF10B981, // green
  0xFF84CC16, // lime
  0xFFEAB308, // yellow
  0xFF78716C, // stone
];
