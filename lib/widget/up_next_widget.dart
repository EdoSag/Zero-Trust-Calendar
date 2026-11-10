import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/entries.dart';
import '../util/format.dart';

/// One row of the "Up next" home-screen widget.
@immutable
class UpNextRow {
  const UpNextRow({required this.time, required this.title, required this.color});
  final String time;
  final String title;
  final String color;

  @override
  bool operator ==(Object other) =>
      other is UpNextRow && other.time == time && other.title == title && other.color == color;

  @override
  int get hashCode => Object.hash(time, title, color);
}

/// The widget's rows: the next five entries still to come today or later.
/// Titles only when [showTitles]; otherwise every row says "Event".
List<UpNextRow> upNextRows(
  List<CalendarEntry> entries, {
  required DateTime now,
  required bool showTitles,
  required String Function(DateTime) formatTime,
  int max = 5,
}) {
  final today = dayOf(now);
  final upcoming = [
    for (final e in entries)
      if (e.kind != EntryKind.task && (e.allDay ? !e.end.isBefore(addDays(today, 1)) : e.end.isAfter(now)))
        e,
  ]..sort((a, b) {
      final da = a.allDay ? dayOf(a.start).isBefore(today) ? today : a.start : a.start;
      final db = b.allDay ? dayOf(b.start).isBefore(today) ? today : b.start : b.start;
      final c = da.compareTo(db);
      return c != 0 ? c : CalendarEntry.compare(a, b);
    });
  String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  return [
    for (final e in upcoming.take(max))
      UpNextRow(
        time: () {
          final start = e.start.isBefore(today) ? today : e.start;
          final day = sameDay(start, now)
              ? ''
              : sameDay(start, addDays(today, 1))
              ? 'Tomorrow '
              : '${relativeDay(start)} ';
          return e.allDay ? '${day}all day'.trim() : '$day${formatTime(start)}'.trim();
        }(),
        title: showTitles ? e.title : (e.kind == EntryKind.birthday ? 'Birthday' : 'Event'),
        color: hex(e.color),
      ),
  ];
}

const _provider = 'dev.sagron.zerotrustcalendar.widget.UpNextWidgetProvider';

/// Saves the rows for the Android widget and redraws it. No-op elsewhere.
Future<void> publishUpNext(List<UpNextRow> rows) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await HomeWidget.saveWidgetData<bool>('upnext_locked', false);
    await HomeWidget.saveWidgetData<String>('upnext_header', 'Up next');
    await HomeWidget.saveWidgetData<int>('upnext_count', rows.length);
    await HomeWidget.saveWidgetData<String>('upnext_empty', 'Nothing coming up');
    for (var i = 0; i < 5; i++) {
      final r = i < rows.length ? rows[i] : null;
      await HomeWidget.saveWidgetData<String>('upnext_${i}_time', r?.time);
      await HomeWidget.saveWidgetData<String>('upnext_${i}_title', r?.title);
      await HomeWidget.saveWidgetData<String>('upnext_${i}_color', r?.color);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  } on Object {
    // No widget support on this device.
  }
}

/// Signed out: the widget forgets everything it showed and shows a lock.
Future<void> clearUpNext() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await HomeWidget.saveWidgetData<bool>('upnext_locked', true);
    await HomeWidget.saveWidgetData<int>('upnext_count', 0);
    for (var i = 0; i < 5; i++) {
      await HomeWidget.saveWidgetData<String>('upnext_${i}_title', null);
      await HomeWidget.saveWidgetData<String>('upnext_${i}_time', null);
    }
    await HomeWidget.saveWidgetData<String>('upnext_empty', 'Open ZT Calendar to see what\'s next');
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  } on Object {
    // Nothing to clear.
  }
}
