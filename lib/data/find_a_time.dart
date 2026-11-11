import 'package:flutter/foundation.dart';

import '../model/calendar_event.dart';

/// "Find a time" (K15, first part): members of a shared calendar can let it
/// know when they are busy, and the app finds slots when everyone is free.
/// No server sees anything new: busy times are one encrypted item per
/// member inside the shared calendar's space, start and end only, never
/// titles.

/// Item id of a member's busy times inside a space.
String busyItemId(String userId) => 'busy/$userId';

const busyKind = 'busy';

/// How far ahead busy times are shared.
const busyHorizon = Duration(days: 60);

/// One member's busy times, as kept in the space.
@immutable
class MemberBusy {
  const MemberBusy({
    required this.userId,
    required this.blocks,
    required this.updated,
  });

  final String userId;

  /// Busy ranges `[start, end)`, sorted, not overlapping.
  final List<(DateTime, DateTime)> blocks;
  final DateTime updated;

  Map<String, Object?> toJson() => {
    'kind': busyKind,
    'userId': userId,
    'updated': updated.toUtc().toIso8601String(),
    'blocks': [
      for (final (s, e) in blocks)
        [s.toUtc().millisecondsSinceEpoch, e.toUtc().millisecondsSinceEpoch],
    ],
  };

  static MemberBusy? fromJson(Map<String, Object?>? json) {
    if (json == null || json['kind'] != busyKind) return null;
    final userId = json['userId'];
    final raw = json['blocks'];
    if (userId is! String || raw is! List) return null;
    final blocks = <(DateTime, DateTime)>[];
    for (final b in raw) {
      if (b is List && b.length == 2 && b[0] is int && b[1] is int) {
        blocks.add((
          DateTime.fromMillisecondsSinceEpoch(b[0] as int),
          DateTime.fromMillisecondsSinceEpoch(b[1] as int),
        ));
      }
    }
    return MemberBusy(
      userId: userId,
      blocks: mergeBlocks(blocks),
      updated:
          DateTime.tryParse(json['updated'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Same blocks (the time it was made doesn't count).
  bool sameBlocks(MemberBusy other) => listEquals(blocks, other.blocks);
}

/// Sorts [blocks] and joins the ones that overlap or touch.
List<(DateTime, DateTime)> mergeBlocks(Iterable<(DateTime, DateTime)> blocks) {
  final sorted = [
    for (final b in blocks)
      if (b.$2.isAfter(b.$1)) b,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(DateTime, DateTime)>[];
  for (final b in sorted) {
    if (out.isNotEmpty && !b.$1.isAfter(out.last.$2)) {
      final last = out.removeLast();
      out.add((last.$1, b.$2.isAfter(last.$2) ? b.$2 : last.$2));
    } else {
      out.add(b);
    }
  }
  return out;
}

/// When this account is busy from [from] for [busyHorizon]: timed events
/// of its visible calendars, except [exceptCalendarId] (that calendar's
/// events are already in the space for everyone). All-day events don't
/// count, as in Google Calendar (holidays, birthdays, reminders).
List<(DateTime, DateTime)> busyBlocks({
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required DateTime from,
  String? exceptCalendarId,
}) {
  final visible = {
    for (final c in calendars)
      if (!c.hidden && c.id != exceptCalendarId) c.id,
  };
  final to = from.add(busyHorizon);
  return mergeBlocks([
    for (final e in events)
      if (!e.allDay && visible.contains(e.calendarId))
        for (final o in e.occurrencesBetween(from, to)) o,
  ]);
}

/// Start times of free slots of [length], on a [step] grid, between
/// [dayStartHour] and [dayEndHour] on each of [days] days from [from]'s day,
/// later than [now], that overlap none of [busy].
List<DateTime> freeSlots({
  required List<(DateTime, DateTime)> busy,
  required DateTime from,
  required DateTime now,
  required Duration length,
  int days = 14,
  int dayStartHour = 8,
  int dayEndHour = 20,
  Duration step = const Duration(minutes: 30),
  bool weekends = false,
}) {
  final merged = mergeBlocks(busy);
  final out = <DateTime>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(from.year, from.month, from.day + d);
    if (!weekends &&
        (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday)) {
      continue;
    }
    final end = DateTime(day.year, day.month, day.day, dayEndHour);
    for (
      var s = DateTime(day.year, day.month, day.day, dayStartHour);
      !s.add(length).isAfter(end);
      s = s.add(step)
    ) {
      if (!s.isAfter(now)) continue;
      final e = s.add(length);
      final clash = merged.any((b) => b.$1.isBefore(e) && b.$2.isAfter(s));
      if (!clash) out.add(s);
    }
  }
  return out;
}
