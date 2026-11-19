import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../data/shared_calendars.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import 'planner_actions.dart';
import 'planner_access.dart';
import 'planner_answers.dart';
import 'planner_model.dart';
import 'planner_plan.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The Planner's settings are one item with `kind: planner-settings`.
final plannerSettingsCollection = ZtCollection<PlannerSettings>(
  kind: 'planner-settings',
  version: 1,
  fromJson: (id, json, updatedAt) => PlannerSettings.fromJson(json, updatedAt),
  toJson: (s) => s.toJson(),
  idOf: (_) => PlannerSettings.itemId,
);

/// The Planner's settings, or the defaults (off) when it was never set up.
final plannerSettingsProvider = StreamProvider<PlannerSettings>((ref) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  PlannerSettings pick(List<PlannerSettings> list) =>
      list.firstOrNull ?? const PlannerSettings();
  if (store is ZtLocalStore) {
    yield* plannerSettingsCollection.watch(store).map(pick);
  } else {
    yield pick(await plannerSettingsCollection.list(store));
  }
});

/// The Planner's blocks, soonest first.
final plannerBlocksProvider = Provider<List<CalendarEvent>>((ref) {
  final events = ref.watch(eventsProvider).value ?? const <CalendarEvent>[];
  return [
    for (final e in events)
      if (PlanMark.of(e) != null) e,
  ]..sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
});

/// Whether this session's first sync of Calendar has finished (or failed,
/// when offline) and none is running. Before that, the events on this
/// device may be older than what another device wrote.
final plannerSyncedProvider = Provider<bool>((ref) {
  final sync = ref.watch(ztSyncControllerProvider);
  return !sync.isSyncing && (sync.lastSyncedAt != null || sync.error != null);
});

/// Where the Planner writes: blocks, its settings and its calendar, all
/// through the shared sync controller. Tests replace it.
class PlannerWriter {
  PlannerWriter(this._ref);
  final Ref _ref;

  Future<void> saveBlock(CalendarEvent block) =>
      _ref.read(calendarRepositoryProvider).saveEvent(block);

  Future<void> deleteBlock(String id) =>
      _ref.read(calendarRepositoryProvider).deleteEvent(id);

  Future<void> saveSettings(PlannerSettings settings) async {
    await plannerSettingsCollection.save(
      _ref.read(ztSyncControllerProvider.notifier),
      await _ref.read(ztLocalStoreProvider.future),
      settings,
    );
  }

  /// Makes the Planned calendar, called [name], unless it exists.
  Future<void> ensureCalendar(String name) async {
    final store = await _ref.read(ztLocalStoreProvider.future);
    if (await calendarsCollection.get(store, plannerCalendarId) != null) return;
    await _ref.read(calendarRepositoryProvider).saveCalendar(
      ZtCalendarInfo(id: plannerCalendarId, name: name, color: plannerColor),
    );
  }
}

final plannerWriterProvider = Provider<PlannerWriter>(PlannerWriter.new);

/// What the Planner last did.
@immutable
class PlannerStatus {
  const PlannerStatus({this.last, this.error, this.waiting});

  /// The last plan that was made and saved on this device.
  final PlannerOutcome? last;

  /// Why the last run failed, or null.
  final Object? error;

  /// Why the Planner isn't planning right now, or null.
  final PlannerWaiting? waiting;
}

enum PlannerWaiting {
  /// The Planner is off.
  off,

  /// Events, calendars or tasks are still loading, or a sync is running:
  /// planning now could undo what another device did.
  loading,

  /// The account's plan doesn't include the Planner (it is part of Plus).
  /// Blocks stay where they are; nothing is planned or moved.
  needsPlus,
}

final plannerControllerProvider =
    NotifierProvider<PlannerController, PlannerStatus>(PlannerController.new);

/// Keeps the plan up to date while Calendar is unlocked.
///
/// It plans again a moment after anything it reads changes (events, tasks,
/// calendars, its settings), after every sync, on resume, when a block's
/// time passes, and when a block's notification is answered. A run that finds nothing to change writes nothing,
/// so two devices looking at the same data don't take turns rewriting it.
///
/// It never plans from half-loaded data: it waits until this session's
/// first sync of Calendar and of the ZT Tasks copy has finished. Otherwise a
/// newly installed phone would plan before it knew the blocks another
/// device already marked done, and overwrite them.
class PlannerController extends Notifier<PlannerStatus> {
  /// Small changes are grouped, so the calendar doesn't flicker.
  static const debounce = Duration(milliseconds: 1500);

  /// Where this device remembers [PlannerSettings.planSignature] of the
  /// settings it last planned with (its own preferences, not synced).
  static const plannedWithKey = 'planner.plannedWith';

  Timer? _debounce;
  Timer? _clock;
  bool _running = false;
  bool _again = false;
  bool _rebuild = false;

  /// The run that is in flight, so turning the Planner off can wait for it.
  Future<void>? _current;

  /// Set while the Planner is being turned off, and until the settings say
  /// so themselves: nothing is planned or written meanwhile.
  bool _turnedOff = false;

  /// Ids of the blocks the run in flight has saved that aren't done.
  final _written = <String>{};

  @override
  PlannerStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _clock?.cancel();
    });
    ref.listen(plannerSettingsProvider, (_, next) {
      // The settings now say "off" themselves.
      if (next.value?.enabled == false) _turnedOff = false;
      schedule();
    });
    ref.listen(allEventsProvider, (_, _) => schedule());
    ref.listen(calendarsProvider, (_, _) => schedule());
    ref.listen(plannerTasksProvider, (_, _) => schedule());
    // Shared and subscribed calendars count as busy, and the Planner waits
    // for them: plan when they have loaded, even if no event changed.
    ref.listen(sharedCalendarsProvider, (_, _) => schedule());
    ref.listen(feedsProvider, (_, _) => schedule());
    // Plus bought, given or ended.
    ref.listen(plannerAllowedProvider, (_, _) => schedule());
    ref.listen(plannerSyncedProvider, (_, synced) {
      if (synced) schedule();
    });
    // A button on a block's notification, pressed while the app is open.
    final answers = ref.read(plannerAnswerBoxProvider).arrived.listen((_) => schedule());
    ref.onDispose(answers.cancel);
    schedule();
    return const PlannerStatus(waiting: PlannerWaiting.loading);
  }

  /// Plans again a moment from now. [rebuild] places every movable block
  /// afresh (after a change to the settings, or "Tidy up").
  void schedule({bool rebuild = false}) {
    if (rebuild) _rebuild = true;
    _debounce?.cancel();
    _debounce = Timer(debounce, () => runNow().ignore());
  }

  /// Plans now and saves what changed.
  Future<void> runNow({bool rebuild = false}) async {
    if (rebuild) _rebuild = true;
    _debounce?.cancel();
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final run = _current = _run();
    try {
      await run;
    } finally {
      _running = false;
      if (identical(_current, run)) _current = null;
      if (_again && ref.mounted) {
        _again = false;
        schedule();
      }
    }
  }

  Future<void> _run() async {
    try {
      // The settings this device last planned with. When they differ from
      // the ones in force (changed on another device, or the app closed
      // before it planned), blocks that are left where they are would never
      // be checked against the new limits: every movable block is placed
      // afresh. A device that never planned takes the plan as it is.
      final plannedWith = await _plannedWith();
      if (!ref.mounted) return;
      final inputs = _inputs();
      if (inputs == null) return;
      // Answers given on notifications while Calendar was locked come
      // first. They change blocks and tasks, so the plan is made from what
      // they leave, on the next run.
      final answers = await ref.read(plannerAnswerBoxProvider).take();
      if (!ref.mounted) return;
      if (answers.isNotEmpty) {
        final failed = await ref.read(plannerActionsProvider).applyAnswers(answers);
        // What could not be saved waits for the next run.
        await ref.read(plannerAnswerBoxProvider).putBack(failed);
        if (!ref.mounted) return;
        if (failed.length < answers.length) {
          _again = true;
          return;
        }
        // Nothing was applied, so nothing changed: plan as usual.
      }
      final signature = inputs.settings.planSignature;
      final rebuildNow = _rebuild || (plannedWith != null && plannedWith != signature);
      _rebuild = false;
      final outcome = computePlan(
        now: DateTime.now(),
        settings: inputs.settings,
        events: inputs.events,
        calendars: inputs.calendars,
        tasks: inputs.tasks,
        rebuild: rebuildNow,
      );
      if (!await _apply(outcome)) {
        // Turned off halfway: what was written is removed by the turn-off.
        if (rebuildNow) _rebuild = true;
        return;
      }
      _written.clear();
      if (plannedWith != signature) await _rememberPlannedWith(signature);
      if (!ref.mounted) return;
      state = PlannerStatus(last: outcome);
      _armClock(outcome.blocksAfter(inputs.events), outcome.at);
    } on Object catch (e) {
      if (ref.mounted) state = PlannerStatus(last: state.last, error: e);
    }
  }

  Future<String?> _plannedWith() async {
    try {
      return await ref.read(ztPreferencesStoreProvider).read(plannedWithKey);
    } on Object {
      return null; // Unreadable: plan as a device that never planned.
    }
  }

  Future<void> _rememberPlannedWith(String signature) async {
    try {
      await ref.read(ztPreferencesStoreProvider).write(plannedWithKey, signature);
    } on Object {
      // Not kept: the next run places the blocks afresh once more.
    }
  }

  /// What a plan made now would be, without saving anything: the setup's
  /// preview. Null while the calendar or the tasks are still loading.
  /// [switchOn] are tasks to count as switched on, before that is saved.
  PlannerOutcome? preview(
    PlannerSettings settings, {
    Set<String> switchOn = const {},
  }) {
    final on = settings.copyWith(enabled: true);
    final inputs = _inputs(settings: on);
    if (inputs == null) return null;
    return computePlan(
      now: DateTime.now(),
      settings: on,
      events: inputs.events,
      calendars: inputs.calendars,
      tasks: [
        for (final t in inputs.tasks) switchOn.contains(t.id) ? t.withAuto(true) : t,
      ],
      rebuild: true,
    );
  }

  /// The blocks a plan made now from [settings] would have, with the
  /// tasks and events passed through [tasks] and [events] first, without
  /// saving anything: the AI helper's before and after. Blocks stay where
  /// they are unless [rebuild], as a run does (it rebuilds when the
  /// settings' [PlannerSettings.planSignature] changed). Null while
  /// anything is still loading.
  List<CalendarEvent>? previewWith(
    PlannerSettings settings, {
    DateTime? now,
    bool rebuild = false,
    List<PlannerTask> Function(List<PlannerTask>)? tasks,
    List<CalendarEvent> Function(List<CalendarEvent>)? events,
  }) {
    final inputs = _inputs(settings: settings.copyWith(enabled: true));
    if (inputs == null) return null;
    final all = events == null ? inputs.events : events(inputs.events);
    final outcome = computePlan(
      now: now ?? DateTime.now(),
      settings: inputs.settings,
      events: all,
      calendars: inputs.calendars,
      tasks: tasks == null ? inputs.tasks : tasks(inputs.tasks),
      rebuild: rebuild,
    );
    return outcome.blocksAfter(all);
  }

  /// Saves the Planner's settings. Turning the Planner on makes sure the
  /// Planned calendar exists; turning it off waits for a run that is in
  /// flight and then removes the blocks that aren't done. A change to where
  /// blocks may go plans the week afresh, here and on every other device
  /// (each notices that the settings are not the ones it last planned
  /// with).
  Future<void> saveSettings(PlannerSettings settings) async {
    final before = switch (ref.read(plannerSettingsProvider)) {
      AsyncData(:final value) => value,
      _ => const PlannerSettings(),
    };
    final writer = ref.read(plannerWriterProvider);
    if (settings.enabled) {
      await writer.ensureCalendar(
        appL10nFor(ref.read(ztLanguageProvider)).plannedCalendarName,
      );
      _turnedOff = false;
    } else if (before.enabled) {
      // No new run starts, and a run that is saving blocks stops after the
      // one it is on. Only then are the blocks removed, so none is written
      // behind the cleanup's back and left on the calendar.
      _turnedOff = true;
      _clock?.cancel();
      _debounce?.cancel();
      try {
        await _current;
      } on Object {
        // That run's failure is its own.
      }
      final ids = {
        for (final e in ref.read(plannerBlocksProvider))
          if (!PlanMark.of(e)!.done) e.id,
        // Blocks that run saved may not have reached the list yet.
        ..._written,
      };
      for (final id in ids) {
        await writer.deleteBlock(id);
      }
      _written.clear();
      if (ref.mounted) state = const PlannerStatus(waiting: PlannerWaiting.off);
    }
    try {
      await writer.saveSettings(settings);
    } on Object {
      // Still on, as far as the settings go: keep planning.
      if (!settings.enabled && _turnedOff) {
        _turnedOff = false;
        schedule();
      }
      rethrow;
    }
    if (settings.enabled) schedule(rebuild: true);
  }

  ({
    PlannerSettings settings,
    List<CalendarEvent> events,
    List<ZtCalendarInfo> calendars,
    List<PlannerTask> tasks,
  })?
  _inputs({PlannerSettings? settings}) {
    final preview = settings != null;
    final s = settings ??
        switch (ref.read(plannerSettingsProvider)) {
          AsyncData(:final value) => value,
          _ => null,
        };
    if (_turnedOff && !preview) {
      state = const PlannerStatus(waiting: PlannerWaiting.off);
      return null;
    }
    if (s == null || !s.enabled) {
      // Off: its blocks are gone, so answers about them mean nothing.
      if (s != null && !preview) ref.read(plannerAnswerBoxProvider).take().ignore();
      state = PlannerStatus(
        waiting: s == null ? PlannerWaiting.loading : PlannerWaiting.off,
      );
      return null;
    }
    // Only a plan known to lack the Planner pauses it; an unknown one
    // (offline, still loading) doesn't.
    if (!preview && ref.read(plannerAllowedProvider) == false) {
      state = PlannerStatus(last: state.last, waiting: PlannerWaiting.needsPlus);
      return null;
    }
    final synced = ref.read(plannerSyncedProvider);
    final events = switch (ref.read(allEventsProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final calendars = switch (ref.read(calendarsProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final tasks = switch (ref.read(plannerTasksProvider)) {
      AsyncData(:final value) when value.ready => value.tasks,
      _ => null,
    };
    // Shared and subscribed calendars' events count as busy: wait for them
    // (unless they failed to load, which must not stop the Planner).
    final shared = ref.read(sharedCalendarsProvider);
    final feeds = ref.read(feedsProvider);
    final othersReady =
        (shared.hasValue || shared.hasError) && (feeds.hasValue || feeds.hasError);
    if (!synced || events == null || calendars == null || tasks == null || !othersReady) {
      if (!preview) {
        state = PlannerStatus(last: state.last, waiting: PlannerWaiting.loading);
      }
      return null;
    }
    return (settings: s, events: events, calendars: calendars, tasks: tasks);
  }

  /// Saves what [outcome] changes. False when the Planner was turned off
  /// meanwhile: it stops before the next write.
  Future<bool> _apply(PlannerOutcome outcome) async {
    _written.clear();
    if (outcome.changesNothing) return !_turnedOff;
    final writer = ref.read(plannerWriterProvider);
    for (final e in outcome.save) {
      if (_turnedOff) return false;
      await writer.saveBlock(e);
      if (!PlanMark.of(e)!.done) _written.add(e.id);
    }
    for (final id in outcome.delete) {
      if (_turnedOff) return false;
      await writer.deleteBlock(id);
    }
    return !_turnedOff;
  }

  /// Plans again when the next block ends (it then waits for an answer, or
  /// counts as done) and just after midnight (yesterday's unanswered blocks
  /// go back to their tasks).
  void _armClock(List<CalendarEvent> blocks, DateTime now) {
    _clock?.cancel();
    var next = DateTime(now.year, now.month, now.day + 1);
    for (final b in blocks) {
      if (PlanMark.of(b)?.done ?? true) continue;
      if (b.end.isAfter(now) && b.end.isBefore(next)) next = b.end;
    }
    _clock = Timer(
      next.difference(now) + const Duration(seconds: 20),
      () => runNow().ignore(),
    );
  }
}
