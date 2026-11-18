import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../planner/planner_plan.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'linked_app_launcher.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Opens the sheet for one of the Planner's blocks.
Future<void> showPlannerBlock(BuildContext context, CalendarEvent block) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: PlannerBlockView(blockId: block.id),
          ),
        ),
      ),
    );

/// One Planner block: its task, when it is planned and why there, and the
/// way to tick the task off. (Done, lock and move come with the next part
/// of the Planner.)
class PlannerBlockView extends ConsumerStatefulWidget {
  const PlannerBlockView({super.key, required this.blockId});
  final String blockId;

  @override
  ConsumerState<PlannerBlockView> createState() => _PlannerBlockViewState();
}

class _PlannerBlockViewState extends ConsumerState<PlannerBlockView> {
  bool _busy = false;

  Future<void> _finish(String taskId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final mirror = await ref.read(linkedMirrorProvider(LinkedApp.tasks).future);
      await mirror.setTaskCompleted(taskId, true);
      if (navigator.canPop()) navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.plannerTaskFinishedSaved),
            duration: const Duration(seconds: 4),
          ),
        );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotUpdateTask('$e'))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final blocks = ref.watch(plannerBlocksProvider);
    final block = blocks.where((b) => b.id == widget.blockId).firstOrNull;
    final mark = PlanMark.of(block);
    if (block == null || mark == null) {
      // The Planner moved the time to another block, or the task is done.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(l.plannerBlockGone),
      );
    }
    final calendars = ref.watch(calendarsProvider).value ?? const <ZtCalendarInfo>[];
    final color = Color(
      block.color ??
          calendars.where((c) => c.id == plannerCalendarId).firstOrNull?.color ??
          plannerColor,
    );
    final group = planGroups(blocks)[mark.group] ?? [block];
    final task = (ref.watch(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
        .where((t) => t.id == mark.itemId)
        .firstOrNull;
    final title = block.title.trim().isEmpty ? l.noTitle : block.title.trim();
    final due = task?.due;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(mark.done ? Icons.check_circle_outline : plannerIcon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  decoration: mark.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${relativeDay(block.start)}, ${formatSpan(context, block.start, block.end, false)}'
          ' · ${formatPlanMinutes(l, block.duration.inMinutes)}',
        ),
        if (group.length > 1) ...[
          const SizedBox(height: 4),
          Text(l.plannerBlockPart(group.indexOf(block) + 1, group.length)),
        ],
        if (due != null) ...[
          const SizedBox(height: 4),
          Text(
            l.dueAt(
              '${relativeDay(due)}'
              '${task!.dueHasTime ? ', ${formatTime(context, due)}' : ''}',
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          planReasonText(l, mark.reason),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!mark.done) ...[
          const SizedBox(height: 4),
          Text(
            l.plannerBlockMoves,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (task != null && !task.completed)
          if (task.repeats)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.aRepeatingTaskTickIt, style: theme.textTheme.bodySmall),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _finish(task.id),
                icon: const Icon(Icons.task_alt),
                label: Text(l.plannerTaskFinished),
              ),
            ),
        FilledButton.tonalIcon(
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) navigator.pop();
            openLinkedApp(LinkedApp.tasks);
          },
          icon: const Icon(Icons.open_in_new),
          label: Text(l.openZtTasks),
        ),
      ],
    );
  }
}
