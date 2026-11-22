import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/working_hours.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import 'planner_page.dart' show PlannerHoursPage;
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The account's working hours now (K-7).
Map<int, List<MinuteRange>> currentWorkingHours(WidgetRef ref) => workingHoursOf(
  ref.read(plannerSettingsProvider).value ?? const PlannerSettings(),
  plannerDefaultWeekStart(),
);

/// Settings row: working hours, shared with the Planner's work hours.
class WorkingHoursTile extends ConsumerWidget {
  const WorkingHoursTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(plannerSettingsProvider).value ?? const PlannerSettings();
    final hours = workingHoursOf(settings, plannerDefaultWeekStart());
    return ListTile(
      leading: const Icon(Icons.work_history_outlined),
      title: Text(l.workingHours),
      subtitle: Text('${describePlanHours(context, hours)}\n${l.workingHoursHint}'),
      isThreeLine: true,
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final picked = await Navigator.of(context).push(
          MaterialPageRoute<Map<int, List<MinuteRange>>>(
            builder: (_) => PlannerHoursPage(title: l.workingHours, hours: hours),
          ),
        );
        if (picked == null) return;
        final now = ref.read(plannerSettingsProvider).value ?? const PlannerSettings();
        try {
          await ref
              .read(plannerControllerProvider.notifier)
              .saveSettings(withWorkingHours(now, picked, plannerDefaultWeekStart()));
        } on Object catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
        }
      },
    );
  }
}
