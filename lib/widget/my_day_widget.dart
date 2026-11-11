import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/entries.dart';
import '../model/linked_items.dart';
import '../util/format.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// What the "My day" home-screen widget (W15) shows: the next event, and
/// the ZT Tasks tasks due today that are still open.
@immutable
class MyDay {
  const MyDay({
    required this.date,
    this.nextTime,
    this.nextTitle,
    this.nextColor,
    this.tasks = const [],
    this.overdue = 0,
  });

  /// Today, as a caption ("Wednesday, 11 November").
  final String date;

  /// The next event still to come today or later, or null for none in the
  /// next two weeks.
  final String? nextTime;
  final String? nextTitle;
  final String? nextColor;

  /// Today's open tasks: (time or "", title).
  final List<(String, String)> tasks;

  /// Open tasks from earlier days.
  final int overdue;

  @override
  bool operator ==(Object other) =>
      other is MyDay &&
      other.date == date &&
      other.nextTime == nextTime &&
      other.nextTitle == nextTitle &&
      other.nextColor == nextColor &&
      listEquals(other.tasks, tasks) &&
      other.overdue == overdue;

  @override
  int get hashCode => Object.hash(
    date,
    nextTime,
    nextTitle,
    nextColor,
    Object.hashAll(tasks),
    overdue,
  );
}

const myDayMaxTasks = 6;

/// Builds [MyDay] from the calendar's entries (events and birthdays) and
/// the linked tasks. Titles only when [showTitles]; otherwise "Event" and
/// "Task". Pure, so it is tested without a phone.
MyDay myDay({
  required List<CalendarEntry> entries,
  required List<LinkedTask> tasks,
  required DateTime now,
  required bool showTitles,
  required String Function(DateTime) formatTime,
  required String date,
  AppL10n? l10n,
}) {
  final l = l10n ?? currentL10n;
  final today = dayOf(now);
  final tomorrow = addDays(today, 1);
  CalendarEntry? next;
  DateTime? nextStart;
  for (final e in entries) {
    if (e.kind == EntryKind.task) continue;
    final ongoing = e.allDay ? !e.end.isBefore(tomorrow) : e.end.isAfter(now);
    if (!ongoing) continue;
    final start = e.start.isBefore(today) ? today : e.start;
    // Timed events still to start come before today's all-day ones, so the
    // widget answers "what's next" rather than "what's today".
    final key = e.allDay && sameDay(start, now) ? tomorrow : start;
    if (nextStart == null || key.isBefore(nextStart)) {
      next = e;
      nextStart = key;
    }
  }
  String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  String? nextTime;
  if (next != null) {
    final start = next.start.isBefore(today) ? today : next.start;
    final day = sameDay(start, now)
        ? ''
        : sameDay(start, tomorrow)
        ? '${l.tomorrow} '
        : '${relativeDay(start)} ';
    nextTime = next.allDay
        ? '$day${l.allDayLower}'.trim()
        : !next.start.isAfter(now)
        ? l.myDayNow
        : '$day${formatTime(start)}'.trim();
  }
  final open = [
    for (final t in tasks)
      if (!t.completed) t,
  ];
  final dueToday =
      [
        for (final t in open)
          if (sameDay(t.due, now)) t,
      ]..sort((a, b) {
        // Timed first, by time; then the rest by title.
        if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
        final c = a.due.compareTo(b.due);
        return c != 0
            ? c
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
  return MyDay(
    date: date,
    nextTime: nextTime,
    nextTitle: next == null
        ? null
        : showTitles
        ? next.title
        : next.kind == EntryKind.birthday
        ? l.birthday
        : l.event,
    nextColor: next == null ? null : hex(next.color),
    tasks: [
      for (final t in dueToday)
        (
          t.hasTime ? formatTime(t.due) : '',
          showTitles ? t.title : l.myDayTask,
        ),
    ],
    overdue: open.where((t) => t.due.isBefore(today)).length,
  );
}

const _provider = 'dev.sagron.zerotrustcalendar.widget.MyDayWidgetProvider';

/// Saves [day] for the Android widget and redraws it. No-op elsewhere.
Future<void> publishMyDay(MyDay day) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final l = currentL10n;
  try {
    await HomeWidget.saveWidgetData<bool>('myday_locked', false);
    await HomeWidget.saveWidgetData<String>('myday_header', l.myDay);
    await HomeWidget.saveWidgetData<String>('myday_date', day.date);
    await HomeWidget.saveWidgetData<String>('myday_next_label', l.myDayNext);
    await HomeWidget.saveWidgetData<String>('myday_next_time', day.nextTime);
    await HomeWidget.saveWidgetData<String>(
      'myday_next_title',
      day.nextTitle ?? l.nothingComingUp,
    );
    await HomeWidget.saveWidgetData<String>('myday_next_color', day.nextColor);
    await HomeWidget.saveWidgetData<String>(
      'myday_tasks_label',
      l.myDayTasksDue(day.tasks.length),
    );
    await HomeWidget.saveWidgetData<String>('myday_no_tasks', l.myDayNoTasks);
    await HomeWidget.saveWidgetData<String>(
      'myday_overdue',
      day.overdue == 0 ? null : l.myDayOverdue(day.overdue),
    );
    await HomeWidget.saveWidgetData<String>(
      'myday_text_more',
      l.widgetMore('{n}'),
    );
    await HomeWidget.saveWidgetData<int>('myday_count', day.tasks.length);
    for (var i = 0; i < myDayMaxTasks; i++) {
      final t = i < day.tasks.length ? day.tasks[i] : null;
      await HomeWidget.saveWidgetData<String>('myday_${i}_time', t?.$1);
      await HomeWidget.saveWidgetData<String>('myday_${i}_title', t?.$2);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  } on Object {
    // No widget support on this device.
  }
}

/// Signed out: the widget forgets everything it showed and shows a lock.
Future<void> clearMyDay() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await HomeWidget.saveWidgetData<bool>('myday_locked', true);
    await HomeWidget.saveWidgetData<int>('myday_count', 0);
    for (final k in const [
      'myday_next_time',
      'myday_next_title',
      'myday_next_color',
      'myday_overdue',
    ]) {
      await HomeWidget.saveWidgetData<String>(k, null);
    }
    for (var i = 0; i < myDayMaxTasks; i++) {
      await HomeWidget.saveWidgetData<String>('myday_${i}_time', null);
      await HomeWidget.saveWidgetData<String>('myday_${i}_title', null);
    }
    await HomeWidget.saveWidgetData<String>(
      'myday_locked_text',
      currentL10n.widgetSignedOut,
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  } on Object {
    // Nothing to clear.
  }
}
