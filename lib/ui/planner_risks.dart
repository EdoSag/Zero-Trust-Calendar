import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import '../data/linked_apps.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../util/format.dart';
import 'linked_app_launcher.dart';
import 'planner_page.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The tasks the last plan could not fit before their due date (or at all),
/// most important first. Empty while the Planner is off.
final plannerRisksProvider = Provider<List<PlanRisk>>((ref) {
  final settings = ref.watch(plannerSettingsProvider).value;
  if (settings == null || !settings.enabled) return const [];
  return ref.watch(plannerControllerProvider).last?.result.risks ?? const [];
});

/// "2 tasks are at risk", across the top of the calendar. Nothing when
/// every task fits.
class PlannerRiskBanner extends ConsumerWidget {
  const PlannerRiskBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final risks = ref.watch(plannerRisksProvider);
    if (risks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => showPlannerRisks(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.plannerTasksAtRisk(risks.length),
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list behind the banner: each task, what is wrong, and what helps.
Future<void> showPlannerRisks(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: Consumer(
      builder: (context, ref, _) {
        final l = context.l10n;
        final theme = Theme.of(context);
        final risks = ref.watch(plannerRisksProvider);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(l.plannerAtRiskTitle, style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  risks.isEmpty ? l.plannerAtRiskNone : l.plannerAtRiskBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final r in risks) PlannerRiskTile(risk: r),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const PlannerPage()),
                    );
                  },
                  child: Text(l.plannerOpenPlanner),
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
);

/// One task at risk. A tap offers the fixes.
class PlannerRiskTile extends ConsumerWidget {
  const PlannerRiskTile({super.key, required this.risk});
  final PlanRisk risk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final task = (ref.watch(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
        .where((t) => t.id == risk.taskId)
        .firstOrNull;
    final title = (task?.title ?? '').isEmpty ? l.noTitle : task!.title;
    final due = task?.due;
    return ListTile(
      key: ValueKey('planner-risk-${risk.taskId}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          risk.minutesUnplanned > 0
              ? l.plannerRiskNoRoom(formatPlanMinutes(l, risk.minutesUnplanned))
              : l.plannerRiskLate(formatPlanMinutes(l, risk.minutesLate)),
          if (due != null) l.dueAt(relativeDay(due)),
        ].join(' · '),
      ),
      trailing: task == null ? null : const Icon(Icons.chevron_right),
      onTap: task == null ? null : () => _fix(context, ref, task),
    );
  }

  Future<void> _fix(BuildContext context, WidgetRef ref, PlannerTask task) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final settings = ref.read(plannerSettingsProvider).value ?? const PlannerSettings();
    final length = task.minutes ?? settings.defaultMinutes;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) {
        Widget option(String value, IconData icon, String label, [String? hint]) =>
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(value),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(label),
                subtitle: hint == null ? null : Text(hint),
              ),
            );
        return SimpleDialog(
          title: Text(task.title.isEmpty ? l.noTitle : task.title),
          children: [
            option(
              'length',
              Icons.timelapse,
              l.plannerFixLength,
              l.plannerFixLengthNow(formatPlanMinutes(l, length)),
            ),
            if (task.due != null && !task.repeats)
              option(
                'due',
                Icons.event_outlined,
                l.plannerFixDue,
                l.dueAt(relativeDay(task.due!)),
              ),
            option('off', Icons.block, l.plannerFixStop),
            option('tasks', Icons.open_in_new, l.openZtTasks),
          ],
        );
      },
    );
    if (choice == null || !context.mounted) return;
    try {
      switch (choice) {
        case 'length':
          final picked = await pickPlanMinutes(
            context,
            title: l.plannerTaskLength,
            choices: planLengthChoices,
            current: length,
          );
          if (picked != null && picked != length) {
            await ref.read(plannerTaskWriterProvider)(task.id, {'planMinutes': picked});
          }
        case 'due':
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final next = DateTime(task.due!.year, task.due!.month, task.due!.day + 1);
          final day = await showDatePicker(
            context: context,
            initialDate: next.isBefore(today) ? today : next,
            firstDate: today,
            lastDate: DateTime(today.year + 5, today.month, today.day),
          );
          if (day != null) await ref.read(plannerTaskDueWriterProvider)(task.id, day);
        case 'off':
          await ref.read(plannerTaskWriterProvider)(task.id, {'planAuto': false});
        case 'tasks':
          await openLinkedApp(LinkedApp.tasks);
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotUpdateTask('$e'))));
    }
  }
}
