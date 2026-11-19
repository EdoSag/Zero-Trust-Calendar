import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zero_trust_core/zero_trust_core.dart' show ztPlanProvider;
import 'package:zt_scheduler/zt_scheduler.dart';

import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'linked_app_launcher.dart';
import '../planner/planner_access.dart';
import '../planner/planner_actions.dart';
import 'find_task_time_page.dart';
import 'planner_habit_page.dart';
import 'planner_risks.dart';
import 'planner_setup_page.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The Planner: what is planned this week, the tasks it plans, and its
/// settings. Before it is turned on, a short explanation and the setup.
class PlannerPage extends ConsumerWidget {
  const PlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(plannerSettingsProvider);
    final settings = async.value;
    return Scaffold(
      appBar: AppBar(title: Text(l.planner)),
      body: settings == null
          ? Center(
              child: async.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.plannerCouldNotPlan('${async.error}')),
                    )
                  : const CircularProgressIndicator(),
            )
          : settings.enabled
          ? _PlannerBody(settings: settings)
          : const _PlannerIntro(),
    );
  }
}

/// Opens "Find a time for a task".
void openFindTaskTime(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => const FindTaskTimePage()),
);

/// The automatic Planner is part of Plus: what that means for this account,
/// with the free "Find a time" and a way to check the plan again.
class PlannerPlusCard extends ConsumerWidget {
  const PlannerPlusCard({super.key, this.paused = false});

  /// The Planner was on: its blocks stay, but nothing moves them.
  final bool paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('planner-plus'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    paused ? l.plannerPausedTitle : l.plannerPlusTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(paused ? l.plannerPausedBody : l.plannerPlusBody),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('planner-find-time'),
              onPressed: () => openFindTaskTime(context),
              icon: const Icon(Icons.manage_search),
              label: Text(l.findTimeForTask),
            ),
            TextButton(
              key: const ValueKey('planner-check-plan'),
              onPressed: () => ref.invalidate(ztPlanProvider),
              child: Text(l.plannerCheckPlan),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannerIntro extends ConsumerWidget {
  const _PlannerIntro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final allowed = ref.watch(plannerAllowedProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(plannerIcon, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(l.plannerIntroTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(l.plannerIntroBody),
        const SizedBox(height: 12),
        Text(
          l.plannerIntroPrivacy,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (allowed == false)
          const PlannerPlusCard()
        else ...[
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlannerSetupPage()),
            ),
            child: Text(l.plannerSetUp),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('planner-find-time'),
            onPressed: () => openFindTaskTime(context),
            icon: const Icon(Icons.manage_search),
            label: Text(l.findTimeForTask),
          ),
        ],
      ],
    );
  }
}

class _PlannerBody extends ConsumerWidget {
  const _PlannerBody({required this.settings});
  final PlannerSettings settings;

  Future<void> _save(BuildContext context, WidgetRef ref, PlannerSettings next) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(plannerControllerProvider.notifier).saveSettings(next);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    }
  }

  Future<void> _setTask(
    BuildContext context,
    WidgetRef ref,
    String id,
    Map<String, Object?> changes,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(plannerTaskWriterProvider)(id, changes);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotUpdateTask('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final status = ref.watch(plannerControllerProvider);
    final blocks = ref.watch(plannerBlocksProvider);
    final taskList = ref.watch(plannerTasksProvider).value;
    final calendars = ref.watch(calendarsProvider).value ?? const <ZtCalendarInfo>[];
    final open = [
      for (final t in taskList?.tasks ?? const <PlannerTask>[])
        if (!t.completed) t,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final planned = [for (final t in open) if (t.plannedUnder(settings.tasks)) t];
    final others = [for (final t in open) if (!t.plannedUnder(settings.tasks)) t];
    final risks = status.last?.result.risks ?? const <PlanRisk>[];

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );

    Widget minutesTile({
      required String title,
      required int value,
      required List<int> choices,
      required PlannerSettings Function(int) apply,
      String? zeroLabel,
    }) => ListTile(
      title: Text(title),
      trailing: Text(
        value == 0 && zeroLabel != null ? zeroLabel : formatPlanMinutes(l, value),
        style: theme.textTheme.bodyMedium,
      ),
      onTap: () async {
        final picked = await pickPlanMinutes(
          context,
          title: title,
          choices: choices,
          current: value,
          zeroLabel: zeroLabel,
        );
        if (picked != null && picked != value && context.mounted) {
          await _save(context, ref, apply(picked));
        }
      },
    );

    Widget hoursTile(String title, String id) => ListTile(
      title: Text(title),
      subtitle: Text(describePlanHours(context, settings.hours[id] ?? const {})),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await Navigator.of(context).push(
          MaterialPageRoute<Map<int, List<MinuteRange>>>(
            builder: (_) => PlannerHoursPage(
              title: title,
              hours: settings.hours[id] ?? const {},
            ),
          ),
        );
        if (picked != null && context.mounted) {
          await _save(context, ref, settings.copyWith(hours: {...settings.hours, id: picked}));
        }
      },
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (status.waiting == PlannerWaiting.needsPlus) const PlannerPlusCard(paused: true),
        header(l.plannerNext7Days),
        _WeekCard(settings: settings, blocks: blocks),
        if (status.waiting == PlannerWaiting.loading)
          ListTile(
            dense: true,
            leading: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text(l.plannerWaitingForSync),
          ),
        if (status.error != null)
          ListTile(
            dense: true,
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(l.plannerCouldNotPlan('${status.error}')),
          ),
        for (final r in risks) PlannerRiskTile(risk: r),

        header(l.plannerTasksToPlan),
        if (taskList == null)
          ListTile(dense: true, title: Text(l.plannerLoadingTasks))
        else if (planned.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              open.isEmpty ? l.plannerNoOpenTasks : l.plannerNoTasksSwitchedOn,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final t in planned)
          _TaskTile(
            task: t,
            settings: settings,
            blocks: blocks,
            on: true,
            onSwitch: (on) => _setTask(context, ref, t.id, {'planAuto': on}),
            onTap: () => _editTask(context, ref, t),
          ),
        if (others.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('planner-other-tasks'),
            title: Text(l.plannerOtherTasks(others.length)),
            initiallyExpanded: planned.isEmpty,
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              for (final t in others)
                _TaskTile(
                  task: t,
                  settings: settings,
                  blocks: blocks,
                  on: false,
                  onSwitch: (on) => _setTask(context, ref, t.id, {'planAuto': on}),
                  onTap: () => _editTask(context, ref, t),
                ),
            ],
          ),
        if (taskList != null && open.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => openLinkedApp(LinkedApp.tasks),
              icon: const Icon(Icons.open_in_new),
              label: Text(l.openZtTasks),
            ),
          ),

        header(l.plannerHabits),
        if (settings.habits.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              l.plannerNoHabits,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final h in settings.habits)
          ListTile(
            key: ValueKey('planner-habit-${h.id}'),
            leading: Icon(h.paused ? Icons.pause_circle_outline : Icons.repeat),
            title: Text(h.title.isEmpty ? l.plannerHabitUntitled : h.title),
            subtitle: Text(h.paused ? l.plannerHabitPausedShort : describeHabit(context, h)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PlannerHabitPage(habit: h)),
            ),
          ),
        ListTile(
          key: const ValueKey('planner-focus'),
          leading: const Icon(Icons.center_focus_strong_outlined),
          title: Text(l.plannerFocusGoal),
          subtitle: Text(
            settings.focusMinutesPerWeek == 0
                ? l.plannerFocusOff
                : l.plannerFocusPerWeek(formatPlanMinutes(l, settings.focusMinutesPerWeek)),
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final picked = await pickPlanMinutes(
              context,
              title: l.plannerFocusGoal,
              choices: const [0, 120, 240, 300, 360, 480, 600, 720, 900, 1200],
              current: settings.focusMinutesPerWeek,
              zeroLabel: l.plannerFocusOffShort,
            );
            if (picked == null || picked == settings.focusMinutesPerWeek) return;
            try {
              await ref.read(plannerActionsProvider).setFocusGoal(picked, l.plannerFocusBlockTitle);
            } on Object catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('planner-add-habit'),
              onPressed: () => addPlannerHabit(context),
              icon: const Icon(Icons.add),
              label: Text(l.plannerAddHabit),
            ),
          ),
        ),

        header(l.settings),
        hoursTile(l.plannerWorkHours, workHoursId),
        hoursTile(l.plannerPersonalHours, personalHoursId),
        ListTile(
          title: Text(l.plannerWhichTasks),
          subtitle: Text(
            settings.tasks == PlannerTasksChoice.all
                ? l.plannerAllTasks
                : l.plannerOnlySwitchedOn,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final picked = await showDialog<PlannerTasksChoice>(
              context: context,
              builder: (dialog) => SimpleDialog(
                title: Text(l.plannerWhichTasks),
                children: [
                  for (final c in PlannerTasksChoice.values)
                    SimpleDialogOption(
                      onPressed: () => Navigator.of(dialog).pop(c),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          c == settings.tasks
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(
                          c == PlannerTasksChoice.all
                              ? l.plannerAllTasks
                              : l.plannerOnlySwitchedOn,
                        ),
                        subtitle: Text(
                          c == PlannerTasksChoice.all
                              ? l.plannerAllTasksHint
                              : l.plannerOnlySwitchedOnHint,
                        ),
                      ),
                    ),
                ],
              ),
            );
            if (picked != null && picked != settings.tasks && context.mounted) {
              await _save(context, ref, settings.copyWith(tasks: picked));
            }
          },
        ),
        minutesTile(
          title: l.plannerUsualLength,
          value: settings.defaultMinutes,
          choices: planLengthChoices,
          apply: (m) => settings.copyWith(defaultMinutes: m),
        ),
        minutesTile(
          title: l.plannerShortestBlock,
          value: settings.minChunk,
          choices: planChunkChoices,
          apply: (m) => settings.copyWith(
            minChunk: m,
            maxChunk: settings.maxChunk < m ? m : settings.maxChunk,
          ),
        ),
        minutesTile(
          title: l.plannerLongestBlock,
          value: settings.maxChunk,
          choices: planChunkChoices,
          apply: (m) => settings.copyWith(
            maxChunk: m,
            minChunk: settings.minChunk > m ? m : settings.minChunk,
          ),
        ),
        minutesTile(
          title: l.plannerBreakAfterMeetings,
          value: settings.breakAfterMeetings,
          choices: planBreakChoices,
          zeroLabel: l.plannerNoBreak,
          apply: (m) => settings.copyWith(breakAfterMeetings: m),
        ),
        minutesTile(
          title: l.plannerMostPerDay,
          value: settings.maxMinutesPerDay,
          choices: planDayChoices,
          apply: (m) => settings.copyWith(maxMinutesPerDay: m),
        ),
        ListTile(
          title: Text(l.plannerBusyCalendars),
          subtitle: Text(() {
            final counted = [
              for (final c in calendars)
                if (c.id != plannerCalendarId &&
                    !c.hidden &&
                    !settings.freeCalendarIds.contains(c.id))
                  c.name,
            ];
            return counted.isEmpty ? l.plannerNoBusyCalendars : counted.join(', ');
          }(), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PlannerBusyCalendarsPage()),
          ),
        ),
        SwitchListTile(
          title: Text(l.plannerPassedCountAsDone),
          subtitle: Text(
            settings.pastBlocks == PastBlocks.countAsDone
                ? l.plannerPassedCountAsDoneOn
                : l.plannerPassedCountAsDoneOff,
          ),
          value: settings.pastBlocks == PastBlocks.countAsDone,
          onChanged: (on) => _save(
            context,
            ref,
            settings.copyWith(
              pastBlocks: on ? PastBlocks.countAsDone : PastBlocks.askThenReplan,
            ),
          ),
        ),
        SwitchListTile(
          title: Text(l.plannerRemindAtStart),
          value: settings.remindAtStart,
          onChanged: (on) => _save(context, ref, settings.copyWith(remindAtStart: on)),
        ),
        if (settings.pastBlocks != PastBlocks.countAsDone)
          SwitchListTile(
            title: Text(l.plannerAskAtEnd),
            subtitle: Text(l.plannerAskAtEndHint),
            value: settings.askAtEnd,
            onChanged: (on) => _save(context, ref, settings.copyWith(askAtEnd: on)),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.auto_fix_high_outlined),
          title: Text(l.plannerTidyUp),
          subtitle: Text(l.plannerTidyUpHint),
          onTap: () {
            ref.read(plannerControllerProvider.notifier).runNow(rebuild: true).ignore();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(l.plannerTidiedUp),
                  duration: const Duration(seconds: 3),
                ),
              );
          },
        ),
        ListTile(
          leading: Icon(Icons.power_settings_new, color: theme.colorScheme.error),
          title: Text(l.plannerTurnOff, style: TextStyle(color: theme.colorScheme.error)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(l.plannerTurnOffTitle),
                content: Text(l.plannerTurnOffBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(d).pop(false),
                    child: Text(l.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(d).pop(true),
                    child: Text(l.plannerTurnOff),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await _save(context, ref, settings.copyWith(enabled: false));
            }
          },
        ),
      ],
    );
  }

  /// A task's length and which hours it is planned in.
  Future<void> _editTask(BuildContext context, WidgetRef ref, PlannerTask task) async {
    final l = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => Consumer(
        builder: (sheet, ref, _) {
          // The task as stored now, so the sheet shows each change.
          final t = (ref.watch(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
                  .where((x) => x.id == task.id)
                  .firstOrNull ??
              task;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      t.title.isEmpty ? l.noTitle : t.title,
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: const Icon(Icons.timelapse),
                    title: Text(l.plannerTaskLength),
                    subtitle: Text(
                      t.minutes == null
                          ? l.plannerLengthGuess(formatPlanMinutes(l, settings.defaultMinutes))
                          : formatPlanMinutes(l, t.minutes!),
                    ),
                    onTap: () async {
                      final picked = await pickPlanMinutes(
                        sheet,
                        title: l.plannerTaskLength,
                        choices: [0, ...planLengthChoices],
                        current: t.minutes ?? 0,
                        zeroLabel: l.plannerLengthGuess(
                          formatPlanMinutes(l, settings.defaultMinutes),
                        ),
                      );
                      if (picked == null || !sheet.mounted) return;
                      await _setTask(sheet, ref, t.id, {
                        'planMinutes': picked == 0 ? null : picked,
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                    child: Text(l.plannerPlanIn, style: Theme.of(sheet).textTheme.labelLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: workHoursId, label: Text(l.plannerWorkHours)),
                        ButtonSegment(
                          value: personalHoursId,
                          label: Text(l.plannerPersonalHours),
                        ),
                      ],
                      selected: {t.hoursId},
                      showSelectedIcon: false,
                      onSelectionChanged: (picked) => _setTask(sheet, ref, t.id, {
                        'planHours': picked.first == workHoursId ? null : picked.first,
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        openLinkedApp(LinkedApp.tasks);
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l.openZtTasks),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Planned time on each of the next seven days, against the daily limit.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.settings, required this.blocks});
  final PlannerSettings settings;
  final List<CalendarEvent> blocks;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final today = dayOf(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) addDays(today, i)];
    final week = plannerWeekNumbers(blocks, today);
    final minutes = week.taskMinutesByDay;
    final total = minutes.values.fold(0, (a, b) => a + b);
    final limit = settings.maxMinutesPerDay;
    final short = DateFormat.E(l.localeName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Semantics(
                      label: '${short.format(d)}, ${formatPlanMinutes(l, minutes[d]!)}',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            minutes[d] == 0 ? '' : _hours(minutes[d]!),
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            key: ValueKey('planner-bar-${dayKeyOf(d)}'),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            height: 4 + 52 * (minutes[d]! / limit).clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              color: minutes[d] == 0
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : const Color(plannerColor),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            short.format(d),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: d == today
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total == 0
                ? l.plannerNothingPlanned
                : l.plannerPlannedTotal(formatPlanMinutes(l, total)),
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            l.plannerDailyLimit(formatPlanMinutes(l, limit)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (settings.focusMinutesPerWeek > 0)
            Text(
              key: const ValueKey('planner-week-focus'),
              l.plannerWeekFocus(
                formatPlanMinutes(l, week.focusMinutes),
                formatPlanMinutes(l, settings.focusMinutesPerWeek),
              ),
              style: theme.textTheme.bodyMedium,
            ),
          if (week.habitBlocks > 0)
            Text(
              key: const ValueKey('planner-week-habits'),
              l.plannerWeekHabits(week.habitBlocks),
              style: theme.textTheme.bodyMedium,
            ),
          if (week.doneTaskMinutes > 0 || week.habitsKept + week.habitsSkipped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                key: const ValueKey('planner-week-past'),
                [
                  l.plannerLastWeekDone(formatPlanMinutes(l, week.doneTaskMinutes)),
                  if (week.habitsKept + week.habitsSkipped > 0)
                    l.plannerLastWeekHabits(week.habitsKept, week.habitsKept + week.habitsSkipped),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "1.5" hours, short enough to sit over a bar.
  static String _hours(int minutes) {
    final h = minutes / 60;
    return h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(1);
  }
}

/// What the Planner screen counts for a week.
class PlannerWeekNumbers {
  PlannerWeekNumbers({
    required this.taskMinutesByDay,
    this.focusMinutes = 0,
    this.habitBlocks = 0,
    this.doneTaskMinutes = 0,
    this.habitsKept = 0,
    this.habitsSkipped = 0,
  });

  /// Task time planned on each of the next seven days (habits and focus
  /// time aren't counted against the daily limit).
  final Map<DateTime, int> taskMinutesByDay;

  /// Focus time planned in the next seven days.
  final int focusMinutes;

  /// Habit blocks in the next seven days (focus time not counted).
  final int habitBlocks;

  /// The last seven days: task time done, habits kept and skipped.
  final int doneTaskMinutes;
  final int habitsKept;
  final int habitsSkipped;
}

/// Counts [blocks] for the seven days from [today], and the seven before.
PlannerWeekNumbers plannerWeekNumbers(List<CalendarEvent> blocks, DateTime today) {
  final days = [for (var i = 0; i < 7; i++) addDays(today, i)];
  final from = days.first;
  final to = addDays(today, 7);
  final pastFrom = addDays(today, -7);
  final byDay = {for (final d in days) d: 0};
  var focus = 0, habits = 0, done = 0, kept = 0, skipped = 0;
  for (final b in blocks) {
    final mark = PlanMark.of(b);
    if (mark == null) continue;
    final day = dayOf(b.start);
    final minutes = b.duration.inMinutes;
    final ahead = !day.isBefore(from) && day.isBefore(to);
    final behind = !day.isBefore(pastFrom) && day.isBefore(from);
    if (mark.isHabit) {
      final isFocus = mark.itemId == PlannerHabit.focusId;
      if (ahead && !mark.skipped) {
        if (isFocus) {
          focus += minutes;
        } else {
          habits++;
        }
      }
      if (behind && !isFocus && mark.done) mark.skipped ? skipped++ : kept++;
    } else {
      if (ahead) byDay[day] = byDay[day]! + minutes;
      if (behind && mark.done) done += minutes;
    }
  }
  return PlannerWeekNumbers(
    taskMinutesByDay: byDay,
    focusMinutes: focus,
    habitBlocks: habits,
    doneTaskMinutes: done,
    habitsKept: kept,
    habitsSkipped: skipped,
  );
}

/// `2026-11-18`, for widget keys.
String dayKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.settings,
    required this.blocks,
    required this.on,
    required this.onSwitch,
    required this.onTap,
  });

  final PlannerTask task;
  final PlannerSettings settings;
  final List<CalendarEvent> blocks;
  final bool on;
  final ValueChanged<bool> onSwitch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = DateTime.now();
    final mine = [
      for (final b in blocks)
        if (PlanMark.of(b) case final m? when m.itemId == task.id && m.occurrence == task.occurrence) b,
    ];
    final done = [
      for (final b in mine)
        if (PlanMark.of(b)!.done) b.duration.inMinutes,
    ].fold(0, (a, b) => a + b);
    final next = mine
        .where((b) => !PlanMark.of(b)!.done && b.end.isAfter(now))
        .firstOrNull;
    final length = task.minutes ?? settings.defaultMinutes;
    final due = task.due;
    final parts = [
      task.minutes == null
          ? l.plannerLengthGuess(formatPlanMinutes(l, length))
          : formatPlanMinutes(l, length),
      if (done > 0) l.plannerDoneOf(formatPlanMinutes(l, done)),
      if (due != null) l.dueAt(relativeDay(due)),
      if (on)
        next == null
            ? l.plannerNotPlannedYet
            : l.plannerNextBlock('${relativeDay(next.start)}, ${formatTime(context, next.start)}'),
    ];
    return SwitchListTile(
      key: ValueKey('planner-task-${task.id}'),
      title: Text(
        task.title.isEmpty ? l.noTitle : task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(parts.join(' · ')),
      value: on,
      onChanged: onSwitch,
      secondary: IconButton(
        tooltip: l.plannerTaskLength,
        icon: const Icon(Icons.tune),
        onPressed: onTap,
      ),
    );
  }
}

/// The hours of one kind (work or personal). Pops with the new hours when
/// saved.
class PlannerHoursPage extends StatefulWidget {
  const PlannerHoursPage({super.key, required this.title, required this.hours});
  final String title;
  final Map<int, List<MinuteRange>> hours;

  @override
  State<PlannerHoursPage> createState() => _PlannerHoursPageState();
}

class _PlannerHoursPageState extends State<PlannerHoursPage> {
  late Map<int, List<MinuteRange>> _hours = widget.hours;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_hours),
              child: Text(l.save),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(l.plannerHoursHint),
          ),
          WeeklyHoursEditor(
            hours: _hours,
            onChanged: (h) => setState(() => _hours = h),
          ),
        ],
      ),
    );
  }
}

/// Which calendars' events keep the Planner away, and whether all-day
/// events do.
class PlannerBusyCalendarsPage extends ConsumerWidget {
  const PlannerBusyCalendarsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(plannerSettingsProvider).value ?? const PlannerSettings();
    final calendars = [
      for (final c in ref.watch(calendarsProvider).value ?? const <ZtCalendarInfo>[])
        if (c.id != plannerCalendarId) c,
    ];
    final controller = ref.read(plannerControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l.plannerBusyCalendars)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(l.plannerBusyCalendarsHint),
          ),
          for (final c in calendars)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Color(c.color),
              side: BorderSide(color: Color(c.color), width: 2),
              value: !c.hidden && !settings.freeCalendarIds.contains(c.id),
              title: Text(c.name),
              subtitle: c.hidden ? Text(l.plannerHiddenCalendar) : null,
              onChanged: c.hidden
                  ? null
                  : (on) => controller.saveSettings(
                      settings.copyWith(
                        freeCalendarIds: on == true
                            ? ({...settings.freeCalendarIds}..remove(c.id))
                            : {...settings.freeCalendarIds, c.id},
                      ),
                    ),
            ),
          const Divider(),
          SwitchListTile(
            title: Text(l.plannerAllDayBusy),
            subtitle: Text(l.plannerAllDayBusyHint),
            value: settings.allDayBusy,
            onChanged: (on) =>
                controller.saveSettings(settings.copyWith(allDayBusy: on)),
          ),
        ],
      ),
    );
  }
}
