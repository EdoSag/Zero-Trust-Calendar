import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../model/calendar_event.dart';
import '../model/recurrence.dart';
import '../l10n/l10n.dart';

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
    0 => currentL10n.today,
    1 => currentL10n.tomorrow,
    -1 => currentL10n.yesterday,
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
    if (!last.isAfter(start)) return currentL10n.allDay;
    return currentL10n.spanTo(formatDay(start), formatDay(last));
  }
  if (sameDay(start, end) || end == addDays(dayOf(start), 1)) {
    return currentL10n.spanTo(formatTime(context, start), formatTime(context, end));
  }
  return currentL10n.spanTo('${formatDay(start)} ${formatTime(context, start)}',
      '${formatDay(end)} ${formatTime(context, end)}');
}

/// "10 minutes before", "1 day before", "At the start".
String reminderLabel(int minutes, {bool allDay = false}) {
  final l = currentL10n;
  if (allDay) {
    // Relative to 9:00 on the day.
    if (minutes == 0) return l.reminderOnTheDay;
    if (minutes % (24 * 60) == 0) {
      return l.reminderDaysBeforeAt9(minutes ~/ (24 * 60));
    }
  }
  if (minutes == 0) return l.reminderAtStart;
  if (minutes % (7 * 24 * 60) == 0) {
    return l.reminderWeeksBefore(minutes ~/ (7 * 24 * 60));
  }
  if (minutes % (24 * 60) == 0) {
    return l.reminderDaysBefore(minutes ~/ (24 * 60));
  }
  if (minutes % 60 == 0) {
    return l.reminderHoursBefore(minutes ~/ 60);
  }
  return l.reminderMinutesBefore(minutes);
}

/// "Monday" in the app's language (1 = Monday, as [DateTime.weekday]).
String weekdayName(int weekday) =>
    DateFormat.EEEE().format(DateTime(2024, 1, weekday)); // Jan 1 2024: Monday

String _ordinal(int n) {
  final l = currentL10n;
  return switch (n) {
    1 => l.ordFirst,
    2 => l.ordSecond,
    3 => l.ordThird,
    4 => l.ordFourth,
    5 => l.ordFifth,
    -1 => l.ordLast,
    -2 => l.ordSecondToLast,
    _ => '$n',
  };
}

/// "On the first Monday" for a monthly repeat.
String monthlyWeekdayLabel(int n, int weekday) =>
    currentL10n.onTheNthWeekday(_ordinal(n), weekdayName(weekday));

/// "Every week on Monday and Wednesday, 10 times".
String describeRule(RecurrenceRule? rule, DateTime start) {
  final l = currentL10n;
  if (rule == null) return l.doesNotRepeat;
  final n = rule.interval;
  var text = switch (rule.frequency) {
    Frequency.daily => l.everyNDays(n),
    Frequency.weekly => l.everyNWeeks(n),
    Frequency.monthly => l.everyNMonths(n),
    Frequency.yearly => l.everyNYears(n),
  };
  if (rule.frequency == Frequency.weekly) {
    final days = rule.byDay.isEmpty
        ? [start.weekday]
        : (rule.byDay.map((d) => d.weekday).toSet().toList()..sort());
    if (days.length == 5 && days.every((d) => d <= 5)) {
      text = n == 1 ? l.everyWeekday : l.ruleOnWeekdays(text);
    } else if (days.length == 7) {
      text = l.ruleOnEveryDay(text);
    } else {
      final names = days.map(weekdayName).toList();
      final joined = names.length == 1
          ? names.first
          : l.listAnd(names.sublist(0, names.length - 1).join(', '), names.last);
      text = l.ruleOnDays(text, joined);
    }
  } else if (rule.frequency == Frequency.monthly) {
    if (rule.byDay.length == 1 && rule.byDay.first.n != null) {
      final d = rule.byDay.first;
      text = l.ruleOnNthWeekday(text, _ordinal(d.n!), weekdayName(d.weekday));
    } else if (rule.byDay.length == 1 && rule.bySetPos.length == 1) {
      text = l.ruleOnNthWeekday(text, _ordinal(rule.bySetPos.first),
          weekdayName(rule.byDay.first.weekday));
    } else if (rule.byMonthDay.length == 1) {
      final d = rule.byMonthDay.first;
      text = d == -1 ? l.ruleOnLastDay(text) : l.ruleOnDay(text, d);
    } else if (rule.byDay.isEmpty && rule.byMonthDay.isEmpty) {
      text = l.ruleOnDay(text, start.day);
    }
  } else if (rule.frequency == Frequency.yearly && rule.byMonth.length <= 1) {
    text = l.ruleOnDate(text, DateFormat.MMMMd().format(start));
  }
  if (rule.count != null) {
    text += l.ruleTimes(rule.count!);
  } else if (rule.until != null) {
    text += l.ruleUntil(DateFormat.yMMMd().format(rule.until!));
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
  return currentL10n.personal;
}
