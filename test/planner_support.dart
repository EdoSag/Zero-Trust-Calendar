import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_config.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/data/shared_calendars.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';

/// The account as the Planner sees it, kept in memory: events, calendars,
/// the Planner's settings and the tasks of ZT Tasks. Every write goes back
/// out through the same streams the app listens to.
class FakeAccount {
  FakeAccount({
    List<CalendarEvent> events = const [],
    List<PlannerTask> tasks = const [],
    this.settings = const PlannerSettings(),
    this.tasksRefreshOk = true,
    this.synced = true,
  }) : events = [...events],
       tasks = [...tasks];

  List<CalendarEvent> events;
  List<PlannerTask> tasks;
  PlannerSettings settings;
  List<ZtCalendarInfo> calendars = [ZtCalendarInfo.personal];

  /// As [LinkedMirror.lastRefreshOk]: null while the first pull runs.
  bool? tasksRefreshOk;
  bool synced;

  /// Every write, in order: `save <id>`, `delete <id>`, `settings`,
  /// `calendar`, `task <id> <changes>`.
  final log = <String>[];

  final _events = StreamController<List<CalendarEvent>>.broadcast();
  final _tasks = StreamController<PlannerTaskList>.broadcast();
  final _settings = StreamController<PlannerSettings>.broadcast();
  final _calendars = StreamController<List<ZtCalendarInfo>>.broadcast();

  void emit() {
    _events.add([...events]);
    _tasks.add(PlannerTaskList([...tasks], refreshOk: tasksRefreshOk));
    _settings.add(settings);
    _calendars.add([...calendars]);
  }

  Stream<T> _from<T>(StreamController<T> c, T Function() now) async* {
    yield now();
    yield* c.stream;
  }

  void setTask(String id, Map<String, Object?> changes) {
    log.add('task $id $changes');
    tasks = [
      for (final t in tasks)
        if (t.id != id)
          t
        else
          PlannerTask(
            id: t.id,
            title: t.title,
            minutes: changes.containsKey('planMinutes')
                ? changes['planMinutes'] as int?
                : t.minutes,
            priority: t.priority,
            due: t.due,
            dueHasTime: t.dueHasTime,
            auto: changes.containsKey('planAuto') ? changes['planAuto'] as bool? : t.auto,
            hoursId: changes.containsKey('planHours')
                ? (changes['planHours'] as String?) ?? workHoursId
                : t.hoursId,
            completed: t.completed,
            repeats: t.repeats,
            dueRaw: t.dueRaw,
            createdAt: t.createdAt,
          ),
    ];
    emit();
  }

  List<CalendarEvent> get blocks => [
    for (final e in events)
      if (PlanMark.of(e) != null) e,
  ]..sort((a, b) => a.start.compareTo(b.start));

  List<Override> get overrides => [
    ztAppConfigProvider.overrideWithValue(calendarAppConfig),
    ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
    reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
    eventsProvider.overrideWith((ref) => _from(_events, () => [...events])),
    calendarsProvider.overrideWith((ref) => _from(_calendars, () => [...calendars])),
    sharedCalendarsProvider.overrideWith((ref) async => const <SharedCalendar>[]),
    feedsProvider.overrideWith((ref) => Stream.value(const <CalendarFeed>[])),
    linkedNotesProvider.overrideWith((ref) => Stream.value(const <LinkedNote>[])),
    linkedTasksProvider.overrideWith((ref) => Stream.value(const <LinkedTask>[])),
    linkedContactsProvider.overrideWith((ref) => Stream.value(const <LinkedContact>[])),
    plannerSettingsProvider.overrideWith((ref) => _from(_settings, () => settings)),
    plannerTasksProvider.overrideWith(
      (ref) => _from(_tasks, () => PlannerTaskList([...tasks], refreshOk: tasksRefreshOk)),
    ),
    plannerSyncedProvider.overrideWith((ref) => synced),
    plannerWriterProvider.overrideWith((ref) => _FakeWriter(ref, this)),
    plannerTaskWriterProvider.overrideWithValue((id, changes) async => setTask(id, changes)),
  ];

  /// The app around [home], with the real theme and both languages.
  Widget app(Widget home, {Locale? locale, List<Override> more = const []}) => ProviderScope(
    overrides: [...overrides, ...more],
    child: MaterialApp(
      theme: ZtTheme.light(accent: ZtTheme.accentFor(calendarAppConfig)),
      locale: locale,
      supportedLocales: ZtLanguages.supported,
      localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
      home: home,
    ),
  );
}

class _FakeWriter extends PlannerWriter {
  _FakeWriter(super.ref, this.account);
  final FakeAccount account;

  @override
  Future<void> saveBlock(CalendarEvent block) async {
    account.log.add('save ${block.id}');
    account.events = [
      for (final e in account.events)
        if (e.id != block.id) e,
      block,
    ];
    account.emit();
  }

  @override
  Future<void> deleteBlock(String id) async {
    account.log.add('delete $id');
    account.events = [
      for (final e in account.events)
        if (e.id != id) e,
    ];
    account.emit();
  }

  @override
  Future<void> saveSettings(PlannerSettings settings) async {
    account.log.add('settings');
    account.settings = settings;
    account.emit();
  }

  @override
  Future<void> ensureCalendar(String name) async {
    if (account.calendars.any((c) => c.id == plannerCalendarId)) return;
    account.log.add('calendar');
    account.calendars = [
      ...account.calendars,
      ZtCalendarInfo(id: plannerCalendarId, name: name, color: plannerColor),
    ];
    account.emit();
  }
}
