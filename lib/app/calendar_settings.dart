import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// The calendar view on screen.
enum CalendarView { schedule, day, threeDay, week, month }

/// Calendar's own per-install settings, kept with the core's preferences.
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.view = CalendarView.month,
    this.showTasks = true,
    this.showBirthdays = true,
    this.widgetTitles = false,
    this.notificationTitles = true,
    this.defaultReminder = 10,
    this.defaultAllDayReminder,
    this.weekStart,
    this.defaultDuration = 60,
  });

  final CalendarView view;

  /// ZT Tasks tasks with a due date shown on the calendar.
  final bool showTasks;

  /// ZT Contacts birthdays shown on the calendar.
  final bool showBirthdays;

  /// Event titles on the home-screen widget. Off: rows say "Event".
  final bool widgetTitles;

  /// Event titles in reminder notifications. Off: "Event at 14:00".
  final bool notificationTitles;

  /// Minutes before a new timed event, or null for none.
  final int? defaultReminder;

  /// Minutes before 9:00 on the day of a new all-day event, or null.
  final int? defaultAllDayReminder;

  /// [DateTime.monday] .. [DateTime.sunday], or null for the locale's.
  final int? weekStart;

  /// Minutes a new event lasts.
  final int defaultDuration;

  static const _unset = Object();

  CalendarSettings copyWith({
    CalendarView? view,
    bool? showTasks,
    bool? showBirthdays,
    bool? widgetTitles,
    bool? notificationTitles,
    Object? defaultReminder = _unset,
    Object? defaultAllDayReminder = _unset,
    Object? weekStart = _unset,
    int? defaultDuration,
  }) => CalendarSettings(
    view: view ?? this.view,
    showTasks: showTasks ?? this.showTasks,
    showBirthdays: showBirthdays ?? this.showBirthdays,
    widgetTitles: widgetTitles ?? this.widgetTitles,
    notificationTitles: notificationTitles ?? this.notificationTitles,
    defaultReminder: identical(defaultReminder, _unset)
        ? this.defaultReminder
        : defaultReminder as int?,
    defaultAllDayReminder: identical(defaultAllDayReminder, _unset)
        ? this.defaultAllDayReminder
        : defaultAllDayReminder as int?,
    weekStart: identical(weekStart, _unset) ? this.weekStart : weekStart as int?,
    defaultDuration: defaultDuration ?? this.defaultDuration,
  );

  Map<String, String> toPrefs() => {
    'view': view.name,
    'showTasks': '$showTasks',
    'showBirthdays': '$showBirthdays',
    'widgetTitles': '$widgetTitles',
    'notificationTitles': '$notificationTitles',
    'defaultReminder': '${defaultReminder ?? 'none'}',
    'defaultAllDayReminder': '${defaultAllDayReminder ?? 'none'}',
    'weekStart': '${weekStart ?? 'locale'}',
    'defaultDuration': '$defaultDuration',
  };

  static CalendarSettings fromPrefs(Map<String, String?> p) {
    const d = CalendarSettings();
    bool b(String k, bool fallback) =>
        p[k] == null ? fallback : p[k] == 'true';
    return CalendarSettings(
      view: CalendarView.values.asNameMap()[p['view']] ?? d.view,
      showTasks: b('showTasks', d.showTasks),
      showBirthdays: b('showBirthdays', d.showBirthdays),
      widgetTitles: b('widgetTitles', d.widgetTitles),
      notificationTitles: b('notificationTitles', d.notificationTitles),
      defaultReminder: p['defaultReminder'] == null
          ? d.defaultReminder
          : int.tryParse(p['defaultReminder']!),
      defaultAllDayReminder: p['defaultAllDayReminder'] == null
          ? d.defaultAllDayReminder
          : int.tryParse(p['defaultAllDayReminder']!),
      weekStart: int.tryParse(p['weekStart'] ?? ''),
      defaultDuration:
          int.tryParse(p['defaultDuration'] ?? '') ?? d.defaultDuration,
    );
  }
}

final calendarSettingsProvider =
    NotifierProvider<CalendarSettingsController, CalendarSettings>(
      CalendarSettingsController.new,
    );

class CalendarSettingsController extends Notifier<CalendarSettings> {
  static const _prefix = 'calendar_';
  bool _changed = false;

  @override
  CalendarSettings build() {
    _load();
    return const CalendarSettings();
  }

  Future<void> _load() async {
    final store = ref.read(ztPreferencesStoreProvider);
    final values = <String, String?>{};
    try {
      for (final key in const CalendarSettings().toPrefs().keys) {
        values[key] = await store.read('$_prefix$key');
      }
    } on Object {
      return; // Unreadable: keep the defaults.
    }
    if (_changed) return;
    state = CalendarSettings.fromPrefs(values);
  }

  Future<void> update(CalendarSettings Function(CalendarSettings) change) async {
    _changed = true;
    final next = change(state);
    final before = state.toPrefs();
    state = next;
    final store = ref.read(ztPreferencesStoreProvider);
    for (final e in next.toPrefs().entries) {
      if (before[e.key] != e.value) {
        try {
          await store.write('$_prefix${e.key}', e.value);
        } on Object {
          // Kept for this run only.
        }
      }
    }
  }
}
