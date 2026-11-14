import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/entries.dart';
import '../util/format.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The month grid, today's agenda and date icon widgets (W9, K10).
///
/// The month grid and the date are drawn by the widgets themselves; the app
/// only hands the month grid which days have events (a coloured dot, never a
/// title) and the agenda its rows for today and tomorrow, so it still shows
/// the right day after midnight. Agenda titles follow "Show details on the
/// home screen" like "Up next": off, every row says "Event" with its time.

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The range the month grid gets dots for: the previous month to two months
/// ahead, so its arrows have something to show.
DateRange monthWidgetRange(DateTime now) =>
    DateRange(DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month + 3, 1));

/// For each day in [range] with an event or birthday: up to [max] colours,
/// earliest first. Tasks don't count.
Map<String, List<String>> monthDots(List<CalendarEntry> entries, DateRange range, {int max = 3}) {
  final sorted = [
    for (final e in entries)
      if (e.kind != EntryKind.task) e,
  ]..sort(CalendarEntry.compare);
  final out = <String, List<String>>{};
  for (var day = range.from; day.isBefore(range.to); day = addDays(day, 1)) {
    final colors = <String>[];
    for (final e in sorted) {
      if (!e.coversDay(day)) continue;
      final c = _hex(e.color);
      if (!colors.contains(c)) colors.add(c);
      if (colors.length == max) break;
    }
    if (colors.isNotEmpty) out[dayKey(day)] = colors;
  }
  return out;
}

/// One row of the agenda widget.
@immutable
class AgendaRow {
  const AgendaRow({required this.time, required this.title, required this.color, this.eventId, this.start, this.end});

  final String time;
  final String title;
  final String color;

  /// For a tap to open the event; null for birthdays.
  final String? eventId;

  /// The occurrence's start, for repeating events.
  final DateTime? start;

  /// When it is over (the widget hides it then, if still showing).
  final DateTime? end;

  Map<String, Object> toJson() => {
    't': time,
    'ti': title,
    'c': color,
    if (eventId != null) 'id': eventId!,
    if (start != null) 's': start!.toIso8601String(),
    if (end != null) 'e': end!.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is AgendaRow &&
      other.time == time &&
      other.title == title &&
      other.color == color &&
      other.eventId == eventId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(time, title, color, eventId, start, end);
}

/// [day]'s entries for the agenda: all-day ones first, then by time.
/// Titles only when [showTitles].
List<AgendaRow> agendaRows(
  List<CalendarEntry> entries, {
  required DateTime day,
  required bool showTitles,
  required String Function(DateTime) formatTime,
  AppL10n? l10n,
  int max = 30,
}) {
  final l = l10n ?? currentL10n;
  final on = [
    for (final e in entries)
      if (e.kind != EntryKind.task && e.coversDay(day)) e,
  ]..sort(CalendarEntry.compare);
  return [
    for (final e in on.take(max))
      AgendaRow(
        time: e.allDay || e.spansDays && e.start.isBefore(day) ? l.allDay : formatTime(e.start),
        title: showTitles ? e.title : (e.kind == EntryKind.birthday ? l.birthday : l.event),
        color: _hex(e.color),
        eventId: e.kind == EntryKind.event ? e.event?.id : null,
        start: e.kind == EntryKind.event && (e.event?.repeats ?? false) ? e.start : null,
        end: e.allDay ? null : e.end,
      ),
  ];
}

const _monthProvider = 'dev.sagron.zerotrustcalendar.widget.MonthWidgetProvider';
const _agendaProvider = 'dev.sagron.zerotrustcalendar.widget.AgendaWidgetProvider';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Saves the dots, the agenda rows (today and tomorrow, keyed by date) and
/// the week start, then redraws both widgets. No-op off Android.
Future<void> publishMonthAndAgenda({
  required Map<String, List<String>> dots,
  required Map<String, List<AgendaRow>> agenda,
  required int weekStart,
}) async {
  if (!_android) return;
  try {
    await HomeWidget.saveWidgetData<bool>('calendar_widgets_locked', false);
    await HomeWidget.saveWidgetData<String>('calendar_month_dots', jsonEncode(dots));
    await HomeWidget.saveWidgetData<int>('calendar_week_start', weekStart);
    await HomeWidget.saveWidgetData<String>(
      'calendar_agenda',
      jsonEncode({
        for (final MapEntry(:key, :value) in agenda.entries) key: [for (final r in value) r.toJson()],
      }),
    );
    await _saveTexts();
    await HomeWidget.updateWidget(qualifiedAndroidName: _monthProvider);
    await HomeWidget.updateWidget(qualifiedAndroidName: _agendaProvider);
  } on Object {
    // No widget support on this device.
  }
}

/// Signed out: no dots and no agenda; the agenda shows a lock.
Future<void> clearMonthAndAgenda() async {
  if (!_android) return;
  try {
    await HomeWidget.saveWidgetData<bool>('calendar_widgets_locked', true);
    await HomeWidget.saveWidgetData<String>('calendar_month_dots', null);
    await HomeWidget.saveWidgetData<String>('calendar_agenda', null);
    await _saveTexts();
    await HomeWidget.updateWidget(qualifiedAndroidName: _monthProvider);
    await HomeWidget.updateWidget(qualifiedAndroidName: _agendaProvider);
  } on Object {
    // Nothing to clear.
  }
}

/// The widgets' fixed texts and language, so month and day names follow the
/// app's language rather than the phone's.
Future<void> _saveTexts() async {
  final l = currentL10n;
  await HomeWidget.saveWidgetData<String>('calendar_widget_lang', l.localeName);
  await HomeWidget.saveWidgetData<String>('calendar_text_agenda_empty', l.widgetNothingElseToday);
  await HomeWidget.saveWidgetData<String>('calendar_text_agenda_open', l.openZtCalendarToSee);
  await HomeWidget.saveWidgetData<String>('calendar_text_signed_out', l.widgetSignedOut);
  await HomeWidget.saveWidgetData<String>('calendar_text_new_event', l.newEvent);
  await HomeWidget.saveWidgetData<String>('calendar_text_prev_month', l.widgetPreviousMonth);
  await HomeWidget.saveWidgetData<String>('calendar_text_next_month', l.widgetNextMonth);
}
