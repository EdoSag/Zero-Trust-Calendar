import 'package:flutter/foundation.dart';

import '../model/recurrence.dart';

/// What "Lunch with Dana Fri 1pm" means: parsed on the phone, never sent
/// anywhere. English and Hebrew.
@immutable
class QuickAdd {
  const QuickAdd({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.hasDate,
    required this.hasTime,
    this.location,
    this.rule,
  });

  final String title;
  final DateTime start;

  /// Exclusive; the midnight after the last day for all-day events.
  final DateTime end;
  final bool allDay;

  /// Whether the text named a day / a time (else today / all day).
  final bool hasDate;
  final bool hasTime;
  final String? location;
  final RecurrenceRule? rule;
}

const _monthNames = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
  'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
  'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  'ינואר': 1, 'פברואר': 2, 'מרץ': 3, 'מרס': 3, 'אפריל': 4, 'מאי': 5,
  'יוני': 6, 'יולי': 7, 'אוגוסט': 8, 'ספטמבר': 9, 'אוקטובר': 10,
  'נובמבר': 11, 'דצמבר': 12,
};

const _weekdayNames = {
  'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2, 'wed': 3,
  'wednesday': 3, 'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4, 'fri': 5,
  'friday': 5, 'sat': 6, 'saturday': 6, 'sun': 7, 'sunday': 7,
  'ראשון': 7, 'שני': 1, 'שלישי': 2, 'רביעי': 3, 'חמישי': 4, 'שישי': 5,
  'שבת': 6,
};

final _weekdayPattern = _weekdayNames.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));
final _monthPattern = _monthNames.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));

// Word edges that also work for Hebrew (\b is ASCII-only in Dart).
const _l = r'(?<![\w֐-׿])';
const _r = r'(?![\w֐-׿])';

/// Parses [text] relative to [now]. [dayFirst] reads 3/12 as 3 December
/// (most of the world, Israel included); false reads it as March 12.
QuickAdd parseQuickAdd(
  String text, {
  required DateTime now,
  int defaultMinutes = 60,
  bool dayFirst = true,
}) {
  var rest = ' ${text.trim()} ';
  DateTime? date;
  int? startMin;
  int? endMin;
  int? durationMin;
  RecurrenceRule? rule;
  String? location;
  final today = DateTime(now.year, now.month, now.day);

  // Removes the first match of [pattern] and hands it to [onMatch].
  bool take(String pattern, void Function(RegExpMatch m) onMatch) {
    final m = RegExp(pattern, caseSensitive: false, unicode: true).firstMatch(rest);
    if (m == null) return false;
    onMatch(m);
    rest = '${rest.substring(0, m.start)} ${rest.substring(m.end)}';
    return true;
  }

  DateTime nextWeekday(int weekday, {bool next = false}) {
    var diff = (weekday - today.weekday) % 7;
    if (next && diff == 0) diff = 7;
    return today.add(Duration(days: diff));
  }

  // --- Repeats: "every Monday", "daily", "כל יום שני".
  final wd = _weekdayPattern.join('|');
  take('$_l(?:every|each|כל)\\s+(?:יום\\s+)?($wd)$_r', (m) {
    final day = _weekdayNames[m.group(1)!.toLowerCase()]!;
    rule = RecurrenceRule(frequency: Frequency.weekly, byDay: [WeekdayNum(day)]);
    date ??= nextWeekday(day);
  });
  if (rule == null) {
    take(
      '$_l(?:every\\s+(day|week|month|year)|(daily|weekly|monthly|yearly|annually)'
      '|כל\\s+(יום|שבוע|חודש|שנה))$_r',
      (m) {
        final w = (m.group(1) ?? m.group(2) ?? m.group(3))!.toLowerCase();
        final f = switch (w) {
          'day' || 'daily' || 'יום' => Frequency.daily,
          'week' || 'weekly' || 'שבוע' => Frequency.weekly,
          'month' || 'monthly' || 'חודש' => Frequency.monthly,
          _ => Frequency.yearly,
        };
        rule = RecurrenceRule(frequency: f);
      },
    );
  }

  // --- Times.
  int? minutesOf(String h, String? m, String? ampm, {int? pmHint}) {
    var hour = int.parse(h);
    final minute = m == null ? 0 : int.parse(m);
    if (minute > 59) return null;
    final ap = ampm?.toLowerCase().replaceAll('.', '');
    if (ap == 'am' || ap == 'pm') {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (ap == 'pm' ? 12 : 0);
    } else if (hour > 23) {
      return null;
    }
    return hour * 60 + minute;
  }

  // Bare "at 5" means 5pm; "at 9" means 9am (as people write them).
  int guessBare(int minutes) {
    final h = minutes ~/ 60;
    return h >= 1 && h <= 7 ? minutes + 12 * 60 : minutes;
  }

  const t = r'(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?';
  // A range: "1-2pm", "10am to 11:30", "13:00-14:00", "from 3 to 5pm".
  take(
    '$_l(?:from\\s+|מ-?|משעה\\s+)?$t\\s*(?:-|–|to|until|till|עד)\\s*$t$_r',
    (m) {
      final hasMarker = m.group(3) != null || m.group(6) != null ||
          m.group(2) != null || m.group(5) != null;
      if (!hasMarker) return;
      var end = minutesOf(m.group(4)!, m.group(5), m.group(6));
      var start = minutesOf(m.group(1)!, m.group(2), m.group(3));
      if (start == null || end == null) return;
      // "1-2pm": the start takes the end's am/pm.
      if (m.group(3) == null && m.group(6) != null) {
        final pmStart = start + 12 * 60;
        if (m.group(6)!.toLowerCase().startsWith('p') && pmStart < end) start = pmStart;
      }
      if (m.group(3) == null && m.group(6) == null && m.group(2) == null) {
        start = guessBare(start);
        if (end < start) end = guessBare(end);
      }
      startMin = start;
      endMin = end;
    },
  );
  if (startMin == null) {
    // "1pm", "13:30", "9.15am".
    take('$_l(?:at\\s+|@\\s*|בשעה\\s+|ב-?)?(\\d{1,2})(?:[:.](\\d{2})\\s*(am|pm|a\\.m\\.|p\\.m\\.)?|\\s*(am|pm|a\\.m\\.|p\\.m\\.))$_r', (m) {
      startMin = minutesOf(m.group(1)!, m.group(2), m.group(3) ?? m.group(4));
    });
  }
  if (startMin == null) {
    // "at 5", "בשעה 17": a bare hour needs the word before it.
    take('$_l(?:at|@|בשעה)\\s*(\\d{1,2})$_r', (m) {
      final v = minutesOf(m.group(1)!, null, null);
      if (v != null) startMin = m.group(0)!.contains('בשעה') ? v : guessBare(v);
    });
  }
  if (startMin == null) {
    take('$_l(?:at\\s+|@\\s*)?(noon|midnight|חצות)$_r', (m) {
      startMin = m.group(1)!.toLowerCase() == 'noon' ? 12 * 60 : 0;
    });
  }
  // "for 2 hours", "for 30 min", "for 1.5h", "למשך שעתיים".
  take(
    '$_l(?:for|למשך)\\s+(\\d+(?:[.,]\\d+)?)\\s*(h|hr|hrs|hour|hours|m|min|mins|minutes|שעות|שעה|דקות)$_r',
    (m) {
      final n = double.parse(m.group(1)!.replaceAll(',', '.'));
      final unit = m.group(2)!.toLowerCase();
      final hours = unit.startsWith('h') || unit.startsWith('ש');
      durationMin = (n * (hours ? 60 : 1)).round();
    },
  );
  take('$_l(?:for\\s+(an?\\s+hour|half\\s+an\\s+hour)|למשך\\s+(שעה|שעתיים|חצי\\s+שעה))$_r', (m) {
    final w = (m.group(1) ?? m.group(2))!.toLowerCase();
    durationMin = w.contains('half') || w.contains('חצי')
        ? 30
        : w.contains('שעתיים')
        ? 120
        : 60;
  });

  // --- Dates.
  take('$_l(day after tomorrow|מחרתיים)$_r', (_) => date = today.add(const Duration(days: 2)));
  take('$_l(today|tonight|היום|הערב)$_r', (m) {
    date = today;
    final w = m.group(1)!.toLowerCase();
    if ((w == 'tonight' || w == 'הערב') && startMin == null) startMin = 20 * 60;
  });
  take('$_l(tomorrow|tmrw|tmr|מחר)$_r', (_) => date = today.add(const Duration(days: 1)));
  take('$_l(?:in|בעוד)\\s+(\\d+)\\s+(days?|weeks?|ימים|שבועות)$_r', (m) {
    final n = int.parse(m.group(1)!);
    final weeks = m.group(2)!.startsWith('w') || m.group(2)!.startsWith('ש');
    date = today.add(Duration(days: n * (weeks ? 7 : 1)));
  });
  take('$_l(?:(next|this|on)\\s+)?(?:ב?יום\\s+|ב)?($wd)$_r', (m) {
    date = nextWeekday(
      _weekdayNames[m.group(2)!.toLowerCase()]!,
      next: m.group(1)?.toLowerCase() == 'next',
    );
  });
  final mo = _monthPattern.join('|');
  DateTime? dateFor(int month, int day, String? year) {
    if (day < 1 || day > 31) return null;
    var y = year == null ? now.year : int.parse(year);
    if (y < 100) y += 2000;
    var d = DateTime(y, month, day);
    if (d.month != month) return null;
    // "Jan 5" in December means next January.
    if (year == null && d.isBefore(today)) d = DateTime(y + 1, month, day);
    return d;
  }

  take('$_l(?:on\\s+)?(?:ב-?)?($mo)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?$_r', (m) {
    date = dateFor(_monthNames[m.group(1)!.toLowerCase()]!, int.parse(m.group(2)!), m.group(3)) ?? date;
  });
  take('$_l(?:on\\s+)?(?:ב-?)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?:ב)?($mo)\\.?(?:,?\\s+(\\d{4}))?$_r', (m) {
    date = dateFor(_monthNames[m.group(2)!.toLowerCase()]!, int.parse(m.group(1)!), m.group(3)) ?? date;
  });
  take('$_l(\\d{4})-(\\d{2})-(\\d{2})$_r', (m) {
    date = dateFor(int.parse(m.group(2)!), int.parse(m.group(3)!), m.group(1)) ?? date;
  });
  take('$_l(?:on\\s+|ב-?)?(\\d{1,2})[/.](\\d{1,2})(?:[/.](\\d{2,4}))?$_r', (m) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final (day, month) = dayFirst ? (a, b) : (b, a);
    if (month >= 1 && month <= 12) date = dateFor(month, day, m.group(3)) ?? date;
  });

  // --- Place: "at Cafe Noir", "@ the office" (what's left after times).
  take(r'(?:\s@\s*|\sat\s+)([A-Z֐-׿][^,;]*?)\s*$', (m) {
    location = m.group(1)!.trim();
  });

  final title = rest
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s+(on|at|from|in|ב|ב-)\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^\s*(on|at)\s+', caseSensitive: false), '')
      .trim()
      .replaceAll(RegExp(r'[\s,;:-]+$'), '')
      .trim();

  final hasDate = date != null;
  final hasTime = startMin != null;
  var day = date ?? today;
  if (hasTime) {
    // "3pm" with no day: today, or tomorrow once 3pm has passed.
    final s = day.add(Duration(minutes: startMin!));
    if (!hasDate && s.isBefore(now)) day = day.add(const Duration(days: 1));
    final start = DateTime(day.year, day.month, day.day, startMin! ~/ 60, startMin! % 60);
    var end = endMin != null
        ? DateTime(day.year, day.month, day.day, endMin! ~/ 60, endMin! % 60)
        : start.add(Duration(minutes: durationMin ?? defaultMinutes));
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return QuickAdd(
      title: title,
      start: start,
      end: end,
      allDay: false,
      hasDate: hasDate,
      hasTime: true,
      location: location,
      rule: rule,
    );
  }
  return QuickAdd(
    title: title,
    start: day,
    end: DateTime(day.year, day.month, day.day + 1),
    allDay: true,
    hasDate: hasDate,
    hasTime: false,
    location: location,
    rule: rule,
  );
}
