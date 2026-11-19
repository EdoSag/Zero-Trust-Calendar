import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../planner/task_time_finder.dart';
import '../util/format.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Saves the event "Find a time" makes. Tests replace it.
final findTimeEventSaverProvider = Provider<Future<void> Function(CalendarEvent)>(
  (ref) => (event) => ref.read(calendarRepositoryProvider).saveEvent(event),
);

/// "Find a time for a task" (free): pick a task from ZT Tasks, then one of
/// the free times Calendar suggests; it is added as an ordinary event
/// linked to the task. Nothing moves it afterwards.
class FindTaskTimePage extends ConsumerStatefulWidget {
  const FindTaskTimePage({super.key, this.now});

  /// The time to search from; the clock when null (tests set it).
  final DateTime? now;

  @override
  ConsumerState<FindTaskTimePage> createState() => _FindTaskTimePageState();
}

class _FindTaskTimePageState extends ConsumerState<FindTaskTimePage> {
  PlannerTask? _task;
  int _minutes = 60;
  String? _hoursId = workHoursId;
  bool _saving = false;

  static const _lengths = [15, 30, 45, 60, 90, 120, 180];

  void _pick(PlannerTask task, PlannerSettings settings) => setState(() {
    _task = task;
    _minutes = task.minutes ?? settings.defaultMinutes;
    // The task's own hours when it names some that are set.
    final hours = settings.hours[task.hoursId] ?? const {};
    _hoursId = hours.isEmpty ? workHoursId : task.hoursId;
  });

  /// The settings to search with: the Planner's, with default work hours
  /// when it was never set up.
  PlannerSettings _settings() {
    final s = ref.watch(plannerSettingsProvider).value ?? const PlannerSettings();
    final work = s.hours[workHoursId] ?? const {};
    return work.isNotEmpty
        ? s
        : s.copyWith(hours: {
            ...s.hours,
            workHoursId: PlannerSettings.defaultHours(plannerDefaultWeekStart())[workHoursId]!,
          });
  }

  Future<void> _add(PlannerTask task, (DateTime, DateTime) slot) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final reminder = ref.read(calendarSettingsProvider).defaultReminder;
    final when =
        '${relativeDay(slot.$1, now: widget.now)}, ${formatSpan(context, slot.$1, slot.$2, false)}';
    setState(() => _saving = true);
    try {
      await ref.read(findTimeEventSaverProvider)(
        CalendarEvent(
          id: const Uuid().v4(),
          title: task.title,
          start: slot.$1,
          end: slot.$2,
          taskIds: [task.id],
          reminders: [?reminder],
        ),
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.findTimeAdded(when)),
          duration: const Duration(seconds: 4),
          persist: false,
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final task = _task;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.findTimeForTask),
        leading: task == null
            ? null
            : BackButton(onPressed: () => setState(() => _task = null)),
      ),
      body: task == null ? _taskList(context) : _times(context, task),
    );
  }

  Widget _taskList(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(plannerTasksProvider);
    final list = async.value;
    final settings = _settings();
    if (list == null || (!list.ready && list.tasks.isEmpty)) {
      return Center(
        child: async.hasError
            ? Padding(padding: const EdgeInsets.all(24), child: Text(l.findTimeNoTasks))
            : const CircularProgressIndicator(),
      );
    }
    final open = [
      for (final t in list.tasks)
        if (!t.completed) t,
    ]..sort((a, b) {
      // Due first (soonest first), then by title.
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    if (open.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(l.findTimeNoTasks));
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(l.findTimePickTask, style: theme.textTheme.titleMedium),
        ),
        for (final t in open)
          ListTile(
            key: ValueKey('find-time-task-${t.id}'),
            leading: const Icon(Icons.task_alt),
            title: Text(t.title),
            subtitle: t.due == null ? null : Text(l.findTimeDue(relativeDay(t.due!, now: widget.now))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pick(t, settings),
          ),
      ],
    );
  }

  Widget _times(BuildContext context, PlannerTask task) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final settings = _settings();
    final events = ref.watch(allEventsProvider).value;
    final calendars = ref.watch(calendarsProvider).value ?? const <ZtCalendarInfo>[];
    final hasPersonal = (settings.hours[personalHoursId] ?? const {}).isNotEmpty;
    final slots = events == null
        ? null
        : findTaskTimes(
            now: widget.now ?? DateTime.now(),
            minutes: _minutes,
            settings: settings,
            hoursId: _hoursId,
            events: events,
            calendars: calendars,
          );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(task.title, style: theme.textTheme.titleLarge),
        ),
        ListTile(
          key: const ValueKey('find-time-length'),
          title: Text(l.plannerHabitLength),
          trailing: Text(formatPlanMinutes(l, _minutes)),
          onTap: () async {
            final m = await pickPlanMinutes(
              context,
              title: l.plannerHabitLength,
              choices: {..._lengths, _minutes}.toList()..sort(),
              current: _minutes,
            );
            if (m != null) setState(() => _minutes = m);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            key: const ValueKey('find-time-hours'),
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (id, label) in [
                (workHoursId, l.plannerWorkHours),
                if (hasPersonal) (personalHoursId, l.plannerPersonalHours),
                (null, l.plannerAnyTime),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _hoursId == id,
                  onSelected: (_) => setState(() => _hoursId = id),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            l.findTimeFreeTimes,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        if (slots == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (slots.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(l.findTimeNone))
        else
          for (final (i, slot) in slots.indexed)
            ListTile(
              key: ValueKey('find-time-slot-$i'),
              leading: const Icon(Icons.event_available),
              title: Text(relativeDay(slot.$1, now: widget.now)),
              subtitle: Text(formatSpan(context, slot.$1, slot.$2, false)),
              trailing: Text(l.findTimeAdd, style: TextStyle(color: theme.colorScheme.primary)),
              enabled: !_saving,
              onTap: () => _add(task, slot),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l.findTimeHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
