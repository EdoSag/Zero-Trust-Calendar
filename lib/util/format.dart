import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../model/calendar_event.dart';
import '../model/recurrence.dart';

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// The first day of the week holding [d], weeks starting on [weekStart].
DateTime startOfWeek(DateTime d, int weekStart) {
  final offset = (d.weekday - weekStart + 7) % 7;
  return DateTime(d.year, d.month, d.day - offset);
}

/// The locale's first day of the week as [DateTime.monday] .. sunday.
int localeWeekStart(BuildContext context) {
  final index = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0=Sun
  return index == 0 ? DateTime.sunday : index;
}

String formatTime(BuildContext context, DateTime t) {
  final use24 = MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false;
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(t),
    alwaysUse24HourFormat: use24,
  );
}

/// A short hour label for the timeline: "9 AM" or "09:00".
String formatHour(BuildContext context, int hour) {
  final use24 = MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false;
  if (use24) return '${hour.toString().padLeft(2, '0')}:00';
  return DateFormat.j().format(DateTime(2000, 1, 1, hour));
}

String formatDay(DateTime d) => DateFormat.MMMEd().format(d);

String formatLongDay(DateTime d) => DateFormat.yMMMMEEEEd().format(d);

String formatMonthYear(DateTime d) => DateFormat.yMMMM().format(d);

/// "Today", "Tomorrow", "Yesterday" or "Tue, Nov 10".
String relativeDay(DateTime d, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final diff = dayOf(d).difference(today).inHours / 24;
  return switch (diff.round()) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ =>
      d.year == today.year
          ? DateFormat.MMMEd().format(d)
          : DateFormat.yMMMEd().format(d),
  };
}

/// "10:00 to 11:00", "All day", "Nov 10 to Nov 12".
String formatSpan(BuildContext context, DateTime start, DateTime end, bool allDay) {
  if (allDay) {
    final last = addDays(end, -1);
    if (!last.isAfter(start)) return 'All day';
    return '${formatDay(start)} to ${formatDay(last)}';
  }
  if (sameDay(start, end) || end == addDays(dayOf(start), 1)) {
    return '${formatTime(context, start)} to ${formatTime(context, end)}';
  }
  return '${formatDay(start)} ${formatTime(context, start)} to '
      '${formatDay(end)} ${formatTime(context, end)}';
}

/// "10 minutes before", "1 day before", "At the start".
String reminderLabel(int minutes, {bool allDay = false}) {
  if (allDay) {
    // Relative to 9:00 on the day.
    if (minutes == 0) return 'On the day at 9:00';
    if (minutes % (24 * 60) == 0) {
      final days = minutes ~/ (24 * 60);
      return days == 1 ? 'The day before at 9:00' : '$days days before at 9:00';
    }
  }
  if (minutes == 0) return 'At the start';
  if (minutes % (7 * 24 * 60) == 0) {
    final w = minutes ~/ (7 * 24 * 60);
    return w == 1 ? '1 week before' : '$w weeks before';
  }
  if (minutes % (24 * 60) == 0) {
    final d = minutes ~/ (24 * 60);
    return d == 1 ? '1 day before' : '$d days before';
  }
  if (minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return h == 1 ? '1 hour before' : '$h hours before';
  }
  return minutes == 1 ? '1 minute before' : '$minutes minutes before';
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _ordinal(int n) => switch (n) {
  1 => 'first',
  2 => 'second',
  3 => 'third',
  4 => 'fourth',
  5 => 'fifth',
  -1 => 'last',
  -2 => 'second to last',
  _ => '${n}th',
};

/// "Every week on Monday and Wednesday, 10 times".
String describeRule(RecurrenceRule? rule, DateTime start) {
  if (rule == null) return 'Does not repeat';
  final n = rule.interval;
  String every(String one, String many) => n == 1 ? 'Every $one' : 'Every $n $many';
  var text = switch (rule.frequency) {
    Frequency.daily => every('day', 'days'),
    Frequency.weekly => every('week', 'weeks'),
    Frequency.monthly => every('month', 'months'),
    Frequency.yearly => every('year', 'years'),
  };
  if (rule.frequency == Frequency.weekly) {
    final days = rule.byDay.isEmpty
        ? [start.weekday]
        : (rule.byDay.map((d) => d.weekday).toSet().toList()..sort());
    if (days.length == 5 && days.every((d) => d <= 5)) {
      text = n == 1 ? 'Every weekday' : '$text on weekdays';
    } else if (days.length == 7) {
      text = '$text on every day';
    } else {
      final names = days.map((d) => _weekdayNames[d - 1]).toList();
      final joined = names.length == 1
          ? names.first
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
      text = '$text on $joined';
    }
  } else if (rule.frequency == Frequency.monthly) {
    if (rule.byDay.length == 1 && rule.byDay.first.n != null) {
      final d = rule.byDay.first;
      text = '$text on the ${_ordinal(d.n!)} ${_weekdayNames[d.weekday - 1]}';
    } else if (rule.byDay.length == 1 && rule.bySetPos.length == 1) {
      text =
          '$text on the ${_ordinal(rule.bySetPos.first)} '
          '${_weekdayNames[rule.byDay.first.weekday - 1]}';
    } else if (rule.byMonthDay.length == 1) {
      final d = rule.byMonthDay.first;
      text = d == -1 ? '$text on the last day' : '$text on day $d';
    } else if (rule.byDay.isEmpty && rule.byMonthDay.isEmpty) {
      text = '$text on day ${start.day}';
    }
  } else if (rule.frequency == Frequency.yearly && rule.byMonth.length <= 1) {
    text = '$text on ${DateFormat.MMMMd().format(start)}';
  }
  if (rule.count != null) {
    text += rule.count == 1 ? ', once' : ', ${rule.count} times';
  } else if (rule.until != null) {
    text += ', until ${DateFormat.yMMMd().format(rule.until!)}';
  }
  return text;
}

Color eventColor(int argb) => Color(argb);

/// Black or white text, whichever reads better on [background].
Color onColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

String calendarName(List<ZtCalendarInfo> calendars, String id) {
  for (final c in calendars) {
    if (c.id == id) return c.name;
  }
  return 'Personal';
}
