import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../planner/planner_plan.dart';
import '../util/format.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The Planner's first-time setup: hours, which tasks, the defaults, and a
/// preview of the plan. Nothing is saved until "Turn on the Planner".
class PlannerSetupPage extends ConsumerStatefulWidget {
  const PlannerSetupPage({super.key});

  @override
  ConsumerState<PlannerSetupPage> createState() => _PlannerSetupPageState();
}

class _PlannerSetupPageState extends ConsumerState<PlannerSetupPage> {
  static const _steps = 4;
  int _step = 0;
  bool _saving = false;
  late PlannerSettings _settings;

  /// Tasks picked in step 2, switched on when the Planner is turned on.
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    // Settings from an earlier time the Planner was on are kept.
    final stored = ref.read(plannerSettingsProvider).value ?? const PlannerSettings();
    _settings = stored.hours.isEmpty
        ? stored.copyWith(hours: PlannerSettings.defaultHours(plannerDefaultWeekStart()))
        : stored;
  }

  Future<void> _turnOn() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l = context.l10n;
    setState(() => _saving = true);
    try {
      final setTask = ref.read(plannerTaskWriterProvider);
      for (final id in _picked) {
        await setTask(id, {'planAuto': true});
      }
      await ref
          .read(plannerControllerProvider.notifier)
          .saveSettings(_settings.copyWith(enabled: true));
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final last = _step == _steps - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.plannerSetUp),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _steps),
        ),
      ),
      body: switch (_step) {
        0 => _hoursStep(l, theme),
        1 => _tasksStep(l, theme),
        2 => _defaultsStep(l, theme),
        _ => _PreviewStep(settings: _settings, picked: _picked),
      },
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          // One above the other: the app's buttons are full width, which
          // fits a column and has no meaning inside a row.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: _saving
                    ? null
                    : last
                    ? _turnOn
                    : () => setState(() => _step++),
                child: Text(last ? l.plannerTurnOn : l.plannerNext),
              ),
              if (_step > 0)
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _step--),
                  child: Text(l.plannerBack),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(ThemeData theme, String title, String body) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );

  Widget _hoursStep(AppL10n l, ThemeData theme) {
    Widget section(String label, String id) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        WeeklyHoursEditor(
          hours: _settings.hours[id] ?? const {},
          onChanged: (h) => setState(
            () => _settings = _settings.copyWith(hours: {..._settings.hours, id: h}),
          ),
        ),
      ],
    );
    return ListView(
      children: [
        _title(theme, l.plannerStepHours, l.plannerStepHoursBody),
        section(l.plannerWorkHours, workHoursId),
        section(l.plannerPersonalHours, personalHoursId),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _tasksStep(AppL10n l, ThemeData theme) {
    final list = ref.watch(plannerTasksProvider).value;
    final open = [
      for (final t in list?.tasks ?? const <PlannerTask>[])
        if (!t.completed) t,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ListView(
      children: [
        _title(theme, l.plannerStepTasks, l.plannerStepTasksBody),
        RadioGroup<PlannerTasksChoice>(
          groupValue: _settings.tasks,
          onChanged: (c) => setState(
            () => _settings = _settings.copyWith(tasks: c ?? _settings.tasks),
          ),
          child: Column(
            children: [
              RadioListTile<PlannerTasksChoice>(
                value: PlannerTasksChoice.switchedOn,
                title: Text(l.plannerOnlySwitchedOn),
                subtitle: Text(l.plannerOnlySwitchedOnHint),
              ),
              RadioListTile<PlannerTasksChoice>(
                value: PlannerTasksChoice.all,
                title: Text(l.plannerAllTasks),
                subtitle: Text(l.plannerAllTasksHint),
              ),
            ],
          ),
        ),
        if (_settings.tasks == PlannerTasksChoice.switchedOn) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.plannerPickTasks, style: theme.textTheme.titleSmall),
          ),
          if (list == null)
            ListTile(dense: true, title: Text(l.plannerLoadingTasks))
          else if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(l.plannerNoOpenTasks),
            ),
          for (final t in open)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: t.auto == true || _picked.contains(t.id),
              // Already on in ZT Tasks: changed from the Planner later.
              enabled: t.auto != true,
              title: Text(
                t.title.isEmpty ? l.noTitle : t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: t.due == null ? null : Text(l.dueAt(relativeDay(t.due!))),
              onChanged: (on) => setState(
                () => on == true ? _picked.add(t.id) : _picked.remove(t.id),
              ),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _defaultsStep(AppL10n l, ThemeData theme) {
    Widget tile({
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
        if (picked != null && mounted) setState(() => _settings = apply(picked));
      },
    );
    return ListView(
      children: [
        _title(theme, l.plannerStepDefaults, l.plannerStepDefaultsBody),
        tile(
          title: l.plannerUsualLength,
          value: _settings.defaultMinutes,
          choices: planLengthChoices,
          apply: (m) => _settings.copyWith(defaultMinutes: m),
        ),
        tile(
          title: l.plannerShortestBlock,
          value: _settings.minChunk,
          choices: planChunkChoices,
          apply: (m) => _settings.copyWith(
            minChunk: m,
            maxChunk: _settings.maxChunk < m ? m : _settings.maxChunk,
          ),
        ),
        tile(
          title: l.plannerLongestBlock,
          value: _settings.maxChunk,
          choices: planChunkChoices,
          apply: (m) => _settings.copyWith(
            maxChunk: m,
            minChunk: _settings.minChunk > m ? m : _settings.minChunk,
          ),
        ),
        tile(
          title: l.plannerBreakAfterMeetings,
          value: _settings.breakAfterMeetings,
          choices: planBreakChoices,
          zeroLabel: l.plannerNoBreak,
          apply: (m) => _settings.copyWith(breakAfterMeetings: m),
        ),
        tile(
          title: l.plannerMostPerDay,
          value: _settings.maxMinutesPerDay,
          choices: planDayChoices,
          apply: (m) => _settings.copyWith(maxMinutesPerDay: m),
        ),
      ],
    );
  }
}

/// The plan as it would be, before anything is saved.
class _PreviewStep extends ConsumerWidget {
  const _PreviewStep({required this.settings, required this.picked});
  final PlannerSettings settings;
  final Set<String> picked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    // Rebuilds when the calendar or the tasks finish loading.
    ref.watch(plannerControllerProvider);
    ref.watch(plannerTasksProvider);
    ref.watch(plannerSyncedProvider);
    PlannerOutcome? outcome;
    Object? error;
    try {
      outcome = ref
          .read(plannerControllerProvider.notifier)
          .preview(settings, switchOn: picked);
    } on Object catch (e) {
      error = e;
    }
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.plannerStepPreview, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(l.plannerStepPreviewBody),
        ],
      ),
    );
    if (outcome == null) {
      return ListView(
        children: [
          header,
          ListTile(
            leading: error == null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(
              error == null ? l.plannerWaitingForSync : l.plannerCouldNotPlan('$error'),
            ),
          ),
        ],
      );
    }
    final now = DateTime.now();
    final blocks = [
      for (final b in outcome.save)
        if (b.end.isAfter(now)) b,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final groups = planGroups(blocks);
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final b in blocks) {
      (byDay[dayOf(b.start)] ??= []).add(b);
    }
    final dayFormat = DateFormat.MMMMEEEEd(l.localeName);
    return ListView(
      children: [
        header,
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              outcome.tasks.isEmpty ? l.plannerPreviewNoTasks : l.plannerPreviewNoRoom,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final r in outcome.result.risks)
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            title: Text(
              (outcome.tasks[r.taskId]?.title ?? '').isEmpty
                  ? l.noTitle
                  : outcome.tasks[r.taskId]!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              r.minutesUnplanned > 0
                  ? l.plannerRiskNoRoom(formatPlanMinutes(l, r.minutesUnplanned))
                  : l.plannerRiskLate(formatPlanMinutes(l, r.minutesLate)),
            ),
          ),
        for (final day in byDay.keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text(
              dayFormat.format(day),
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          for (final b in byDay[day]!)
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 96,
                child: Text(
                  formatSpan(context, b.start, b.end, false),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              title: Text(() {
                final title = b.title.trim().isEmpty ? l.noTitle : b.title.trim();
                final group = groups[PlanMark.of(b)!.group]!;
                return group.length > 1
                    ? l.plannerPartOf(title, group.indexOf(b) + 1, group.length)
                    : title;
              }(), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
