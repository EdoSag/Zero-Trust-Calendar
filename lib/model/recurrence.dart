import 'package:flutter/foundation.dart';

/// How often a repeating event repeats (RFC 5545 `FREQ`).
enum Frequency { daily, weekly, monthly, yearly }

/// A weekday in a rule, optionally the nth one of the month or year
/// (`2TU` is the second Tuesday, `-1FR` the last Friday).
@immutable
class WeekdayNum {
  const WeekdayNum(this.weekday, [this.n]);

  /// [DateTime.monday] .. [DateTime.sunday].
  final int weekday;

  /// Null for every such weekday in the period.
  final int? n;

  static const _codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  static WeekdayNum? parse(String s) {
    final m = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(
      s.trim().toUpperCase(),
    );
    if (m == null) return null;
    final n = m.group(1) == null ? null : int.parse(m.group(1)!);
    return WeekdayNum(_codes.indexOf(m.group(2)!) + 1, n == 0 ? null : n);
  }

  @override
  String toString() => '${n ?? ''}${_codes[weekday - 1]}';

  @override
  bool operator ==(Object other) =>
      other is WeekdayNum && other.weekday == weekday && other.n == n;

  @override
  int get hashCode => Object.hash(weekday, n);
}

/// The part of RFC 5545 `RRULE` that calendars use in practice: FREQ,
/// INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY, BYMONTH and BYSETPOS.
///
/// Occurrences are worked out in local wall-clock time, so a 9:00 weekly
/// meeting stays at 9:00 across daylight-saving changes.
@immutable
class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.count,
    this.until,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.bySetPos = const [],
    this.weekStart = DateTime.monday,
  });

  final Frequency frequency;
  final int interval;

  /// Total occurrences, counting the first.
  final int? count;

  /// Last allowed start (inclusive), local time.
  final DateTime? until;
  final List<WeekdayNum> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final List<int> bySetPos;
  final int weekStart;

  static RecurrenceRule? tryParse(String? rule) {
    if (rule == null) return null;
    var text = rule.trim();
    if (text.toUpperCase().startsWith('RRULE:')) text = text.substring(6);
    if (text.isEmpty) return null;
    Frequency? freq;
    var interval = 1;
    int? count;
    DateTime? until;
    var byDay = <WeekdayNum>[];
    var byMonthDay = <int>[];
    var byMonth = <int>[];
    var bySetPos = <int>[];
    var wkst = DateTime.monday;
    List<int> ints(String v) => [
      for (final p in v.split(','))
        if (int.tryParse(p.trim()) case final int i) i,
    ];
    for (final part in text.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq).trim().toUpperCase();
      final value = part.substring(eq + 1).trim();
      switch (key) {
        case 'FREQ':
          freq = switch (value.toUpperCase()) {
            'DAILY' => Frequency.daily,
            'WEEKLY' => Frequency.weekly,
            'MONTHLY' => Frequency.monthly,
            'YEARLY' => Frequency.yearly,
            _ => null,
          };
          if (freq == null) return null; // HOURLY etc.: not supported.
        case 'INTERVAL':
          interval = (int.tryParse(value) ?? 1).clamp(1, 1000);
        case 'COUNT':
          count = int.tryParse(value);
        case 'UNTIL':
          until = parseUntil(value);
        case 'BYDAY':
          byDay = [
            for (final p in value.split(','))
              if (WeekdayNum.parse(p) case final WeekdayNum d) d,
          ];
        case 'BYMONTHDAY':
          byMonthDay = ints(value).where((d) => d != 0 && d.abs() <= 31).toList();
        case 'BYMONTH':
          byMonth = ints(value).where((m) => m >= 1 && m <= 12).toList();
        case 'BYSETPOS':
          bySetPos = ints(value).where((p) => p != 0).toList();
        case 'WKST':
          final d = WeekdayNum.parse(value);
          if (d != null) wkst = d.weekday;
      }
    }
    if (freq == null) return null;
    return RecurrenceRule(
      frequency: freq,
      interval: interval,
      count: count != null && count > 0 ? count : null,
      until: until,
      byDay: byDay,
      byMonthDay: byMonthDay,
      byMonth: byMonth,
      bySetPos: bySetPos,
      weekStart: wkst,
    );
  }

  /// `UNTIL` as a local time: `20261231T235959Z` (UTC), `20261231T235959`
  /// (floating) or `20261231` (a date, meaning the whole day).
  static DateTime? parseUntil(String v) {
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
    ).firstMatch(v.trim());
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    if (m.group(4) == null) {
      return DateTime(g(1), g(2), g(3), 23, 59, 59);
    }
    if (m.group(7) != null) {
      return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).toLocal();
    }
    return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
  }

  @override
  String toString() {
    final parts = <String>[
      'FREQ=${frequency.name.toUpperCase()}',
      if (interval != 1) 'INTERVAL=$interval',
      if (count != null) 'COUNT=$count',
      if (until != null) 'UNTIL=${_utcStamp(until!)}',
      if (byDay.isNotEmpty) 'BYDAY=${byDay.join(',')}',
      if (byMonthDay.isNotEmpty) 'BYMONTHDAY=${byMonthDay.join(',')}',
      if (byMonth.isNotEmpty) 'BYMONTH=${byMonth.join(',')}',
      if (bySetPos.isNotEmpty) 'BYSETPOS=${bySetPos.join(',')}',
      if (weekStart != DateTime.monday)
        'WKST=${WeekdayNum(weekStart).toString()}',
    ];
    return parts.join(';');
  }

  static String _utcStamp(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
        'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  RecurrenceRule copyWith({
    int? interval,
    int? count,
    DateTime? until,
    bool clearEnd = false,
    List<WeekdayNum>? byDay,
  }) => RecurrenceRule(
    frequency: frequency,
    interval: interval ?? this.interval,
    count: clearEnd ? null : (count ?? this.count),
    until: clearEnd ? null : (until ?? this.until),
    byDay: byDay ?? this.byDay,
    byMonthDay: byMonthDay,
    byMonth: byMonth,
    bySetPos: bySetPos,
    weekStart: weekStart,
  );

  /// Start times of the occurrences that begin in `[from, to)`, given the
  /// series' first start [dtStart] (local). [dtStart] itself is always the
  /// first occurrence, as in RFC 5545. [exclude] holds starts to skip
  /// (EXDATE); they still count towards [count].
  List<DateTime> between(
    DateTime dtStart,
    DateTime from,
    DateTime to, {
    Set<DateTime> exclude = const {},
    int limit = 2000,
  }) {
    final out = <DateTime>[];
    for (final t in _iterate(dtStart)) {
      if (!t.isBefore(to)) break;
      if (!t.isBefore(from) && !exclude.contains(t)) {
        out.add(t);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Every occurrence from [dtStart] on, in order, until COUNT or UNTIL.
  /// Infinite for a rule with neither: take what you need.
  Iterable<DateTime> occurrences(DateTime dtStart) => _iterate(dtStart);

  Iterable<DateTime> _iterate(DateTime dtStart) sync* {
    var produced = 0;
    yield dtStart;
    produced++;
    if (count != null && produced >= count!) return;
    var emptyPeriods = 0;
    for (var period = 0; period < 100000; period++) {
      final candidates = _candidates(dtStart, period);
      if (candidates.isEmpty) {
        // A rule that can never match (BYMONTHDAY=31 with BYMONTH=2).
        if (++emptyPeriods > 1000) return;
        continue;
      }
      emptyPeriods = 0;
      for (final t in candidates) {
        if (!t.isAfter(dtStart)) continue;
        if (until != null && t.isAfter(until!)) return;
        yield t;
        produced++;
        if (count != null && produced >= count!) return;
      }
    }
  }

  /// The occurrences in the [period]th period after the one holding
  /// [start], sorted, with [start]'s time of day.
  List<DateTime> _candidates(DateTime start, int period) {
    final step = period * interval;
    DateTime at(int y, int m, int d) =>
        DateTime(y, m, d, start.hour, start.minute, start.second);
    List<DateTime> days;
    switch (frequency) {
      case Frequency.daily:
        final d = DateTime(start.year, start.month, start.day + step);
        days = [d];
        if (byMonth.isNotEmpty && !byMonth.contains(d.month)) days = [];
        if (byMonthDay.isNotEmpty && !_matchesMonthDay(d)) days = [];
        if (byDay.isNotEmpty && !byDay.any((w) => w.weekday == d.weekday)) {
          days = [];
        }
      case Frequency.weekly:
        final offset = (start.weekday - weekStart + 7) % 7;
        final weekBegin = DateTime(
          start.year,
          start.month,
          start.day - offset + 7 * step,
        );
        final wanted = byDay.isEmpty
            ? {start.weekday}
            : {for (final w in byDay) w.weekday};
        days = [
          for (var i = 0; i < 7; i++)
            DateTime(weekBegin.year, weekBegin.month, weekBegin.day + i),
        ].where((d) => wanted.contains(d.weekday)).toList();
        if (byMonth.isNotEmpty) {
          days = days.where((d) => byMonth.contains(d.month)).toList();
        }
      case Frequency.monthly:
        final first = DateTime(start.year, start.month + step);
        days = byMonth.isNotEmpty && !byMonth.contains(first.month)
            ? []
            : _daysInMonth(first.year, first.month, start);
      case Frequency.yearly:
        final year = start.year + step;
        if (byMonth.isNotEmpty) {
          days = [
            for (final m in [...byMonth]..sort())
              ..._daysInMonth(year, m, start, yearly: true),
          ];
        } else if (byDay.any((w) => w.n != null) && byMonthDay.isEmpty) {
          // "20th Monday of the year": rare; nth weekday of the year.
          days = _nthWeekdaysOfYear(year);
        } else if (byMonthDay.isNotEmpty || byDay.isNotEmpty) {
          days = [
            for (var m = 1; m <= 12; m++)
              ..._daysInMonth(year, m, start, yearly: true),
          ];
        } else {
          final d = DateTime(year, start.month, start.day);
          days = d.month == start.month ? [d] : []; // Feb 29 skips years.
        }
    }
    days.sort();
    if (bySetPos.isNotEmpty && days.isNotEmpty) {
      final picked = <DateTime>{};
      for (final p in bySetPos) {
        final i = p > 0 ? p - 1 : days.length + p;
        if (i >= 0 && i < days.length) picked.add(days[i]);
      }
      days = picked.toList()..sort();
    }
    return [for (final d in days) at(d.year, d.month, d.day)];
  }

  bool _matchesMonthDay(DateTime d) {
    final last = DateTime(d.year, d.month + 1, 0).day;
    return byMonthDay.any((md) => md > 0 ? md == d.day : last + md + 1 == d.day);
  }

  /// Matching days of one month for MONTHLY (and YEARLY with BYMONTH).
  List<DateTime> _daysInMonth(
    int year,
    int month,
    DateTime start, {
    bool yearly = false,
  }) {
    final last = DateTime(year, month + 1, 0).day;
    if (byMonthDay.isEmpty && byDay.isEmpty) {
      // Same day of month as the start; months without it are skipped.
      return start.day <= last ? [DateTime(year, month, start.day)] : [];
    }
    Iterable<int> days = List.generate(last, (i) => i + 1);
    if (byMonthDay.isNotEmpty) {
      final wanted = {
        for (final md in byMonthDay) md > 0 ? md : last + md + 1,
      };
      days = days.where(wanted.contains);
    }
    if (byDay.isNotEmpty) {
      days = days.where((day) {
        final d = DateTime(year, month, day);
        return byDay.any((w) {
          if (w.weekday != d.weekday) return false;
          final n = w.n;
          if (n == null) return true;
          final nth = (day - 1) ~/ 7 + 1;
          final fromEnd = (last - day) ~/ 7 + 1;
          return n > 0 ? nth == n : fromEnd == -n;
        });
      });
    }
    return [for (final day in days) DateTime(year, month, day)];
  }

  List<DateTime> _nthWeekdaysOfYear(int year) {
    final out = <DateTime>[];
    final daysInYear = DateTime(year + 1).difference(DateTime(year)).inDays;
    for (final w in byDay) {
      final all = [
        for (var i = 0; i < daysInYear + 1; i++)
          if (DateTime(year, 1, 1 + i) case final d
              when d.year == year && d.weekday == w.weekday)
            d,
      ];
      final n = w.n;
      if (n == null) {
        out.addAll(all);
      } else {
        final i = n > 0 ? n - 1 : all.length + n;
        if (i >= 0 && i < all.length) out.add(all[i]);
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
