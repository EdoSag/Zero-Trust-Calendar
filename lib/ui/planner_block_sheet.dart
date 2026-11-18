import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_scheduler/zt_scheduler.dart' show PlanReason;

import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../planner/planner_actions.dart';
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

/// How long a message with Undo stays. (Flutter keeps a snackbar that has
/// an action open until it is tapped unless it is told otherwise.)
const _undoFor = Duration(seconds: 6);

/// Moves [block] to [start] (a drag in the day or week view, or "Move" on
/// its sheet) and locks it there, with a way to undo.
Future<void> movePlannerBlock(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent block,
  DateTime start, [
  DateTime? end,
]) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final when = '${formatDay(start)}, ${formatTime(context, start)}';
  final actions = ref.read(plannerActionsProvider);
  try {
    await actions.move(block, start, end);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l.plannerMovedAndLocked(when)),
          duration: _undoFor,
          persist: false,
          action: SnackBarAction(
            label: l.undo,
            onPressed: () => actions.restore(block).ignore(),
          ),
        ),
      );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.couldNotMove('$e'))));
  }
}

/// One Planner block: its task, when it is planned and why there, and what
/// can be done with it: done, task finished, need more time, not now, lock
/// here, move.
class PlannerBlockView extends ConsumerStatefulWidget {
  const PlannerBlockView({super.key, required this.blockId});
  final String blockId;

  @override
  ConsumerState<PlannerBlockView> createState() => _PlannerBlockViewState();
}

class _PlannerBlockViewState extends ConsumerState<PlannerBlockView> {
  bool _busy = false;

  /// Runs [action], closes the sheet and says [message]. [undo] adds an
  /// Undo button.
  Future<void> _run(
    Future<void> Function() action, {
    String? message,
    Future<void> Function()? undo,
    bool close = true,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
      if (close && navigator.canPop()) navigator.pop();
      if (message != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              duration: undo == null ? const Duration(seconds: 4) : _undoFor,
              persist: false,
              action: undo == null
                  ? null
                  : SnackBarAction(label: l.undo, onPressed: () => undo().ignore()),
            ),
          );
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(CalendarEvent block) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(plannerActionsProvider);
    String? finished;
    var saved = false;
    await _run(() async {
      finished = await actions.setDone(block, true);
      saved = true;
    });
    if (!saved) return;
    // Said after the fact, because only then is it known whether this was
    // the last of the task's time (the task is then ticked off as well).
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(finished == null ? l.plannerMarkedDone : l.plannerTaskFinishedSaved),
          duration: _undoFor,
          persist: false,
          action: SnackBarAction(
            label: l.undo,
            onPressed: () async {
              await actions.restore(block);
              if (finished != null) await actions.reopenTask(finished!);
            },
          ),
        ),
      );
  }

  Future<void> _needMoreTime(CalendarEvent block) async {
    final l = context.l10n;
    final extra = await showDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(l.plannerHowMuchMore),
        children: [
          for (final m in const [15, 30, 60, 120])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(formatPlanMinutes(l, m)),
              ),
            ),
        ],
      ),
    );
    if (extra == null || !mounted) return;
    await _run(
      () => ref.read(plannerActionsProvider).needMoreTime(block, extra),
      message: l.plannerAddedTime(formatPlanMinutes(l, extra)),
    );
  }

  Future<void> _notNow(CalendarEvent block) async {
    final l = context.l10n;
    final now = DateTime.now();
    final day = DateTime(block.start.year, block.start.month, block.start.day);
    final today = sameDay(block.start, now);
    final choices = <(String, DateTime)>[
      // The rest of the block's own day, when there is any left.
      if (block.end.isAfter(now) && sameDay(block.end, block.start))
        (today ? l.plannerLaterToday : l.plannerLaterThatDay, block.end),
      (today ? l.tomorrow : l.plannerTheDayAfter, DateTime(day.year, day.month, day.day + 1)),
      (l.plannerAWeekLater, DateTime(day.year, day.month, day.day + 7)),
    ];
    final until = await showDialog<DateTime>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(l.plannerNotNowUntil),
        children: [
          for (final (label, at) in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(at),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
    if (until == null || !mounted) return;
    await _run(
      () => ref.read(plannerActionsProvider).notNow(block, until),
      message: l.plannerPlannedAgainFrom(relativeDay(until)),
    );
  }

  Future<void> _move(CalendarEvent block) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final day = await showDatePicker(
      context: context,
      initialDate: block.start.isBefore(first) ? first : block.start,
      firstDate: first,
      lastDate: DateTime(first.year, first.month, first.day + 90),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(block.start),
    );
    if (time == null || !mounted) return;
    final navigator = Navigator.of(context);
    final start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await movePlannerBlock(context, ref, block, start);
    if (navigator.canPop()) navigator.pop();
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
    final conflicts =
        ref.watch(plannerControllerProvider).last?.result.conflicts ?? const <String>[];
    final title = block.title.trim().isEmpty ? l.noTitle : block.title.trim();
    final due = task?.due;
    final now = DateTime.now();
    final started = !block.start.isAfter(now);
    final passed = !block.end.isAfter(now);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget action(IconData icon, String label, VoidCallback onTap, {String? hint}) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
          subtitle: hint == null ? null : Text(hint),
          enabled: !_busy,
          onTap: onTap,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              mark.done
                  ? Icons.check_circle_outline
                  : mark.locked
                  ? Icons.lock_outline
                  : plannerIcon,
              color: color,
            ),
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
        Text(planReasonText(l, mark.done ? PlanReason.done : mark.reason), style: small),
        if (!mark.done && !mark.locked) ...[
          const SizedBox(height: 4),
          Text(l.plannerBlockMoves, style: small),
        ],
        if (!mark.done && conflicts.contains(block.id)) ...[
          const SizedBox(height: 4),
          Text(
            l.plannerBlockOverlaps,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (mark.done)
          action(
            Icons.undo,
            l.plannerNotDoneAfterAll,
            () => _run(
              () async => ref.read(plannerActionsProvider).setDone(block, false),
              message: l.plannerMarkedNotDone,
            ),
          )
        else ...[
          if (started)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _done(block),
                icon: const Icon(Icons.check),
                label: Text(l.plannerDone),
              ),
            ),
          if (!started)
            action(
              Icons.check,
              l.plannerAlreadyDone,
              () => _done(block),
              hint: l.plannerAlreadyDoneHint,
            ),
          if (task != null && !task.completed)
            if (task.repeats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.aRepeatingTaskTickIt, style: theme.textTheme.bodySmall),
              )
            else
              action(
                Icons.task_alt,
                l.plannerTaskFinished,
                () => _run(
                  () => ref.read(plannerActionsProvider).finishTask(task.id),
                  message: l.plannerTaskFinishedSaved,
                  undo: () => ref.read(plannerActionsProvider).reopenTask(task.id),
                ),
              ),
          if (task != null)
            action(
              Icons.more_time,
              l.plannerNeedMoreTime,
              () => _needMoreTime(block),
            ),
          if (passed)
            action(
              Icons.replay,
              l.plannerDidNotDoIt,
              () => _run(
                () => ref.read(plannerActionsProvider).didNot(block),
                message: l.plannerPlannedAgain,
              ),
              hint: l.plannerDidNotDoItHint,
            )
          else
            action(Icons.snooze, l.plannerNotNow, () => _notNow(block)),
          if (!started)
            action(
              mark.locked ? Icons.lock_open : Icons.lock_outline,
              mark.locked ? l.plannerUnlock : l.plannerLockHere,
              () => _run(
                () => ref.read(plannerActionsProvider).setLocked(block, !mark.locked),
                message: mark.locked ? l.plannerUnlocked : l.plannerLocked,
                close: false,
              ),
              hint: mark.locked ? null : l.plannerLockHereHint,
            ),
          action(Icons.open_with, l.move, () => _move(block)),
        ],
        action(Icons.open_in_new, l.openZtTasks, () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
          openLinkedApp(LinkedApp.tasks);
        }),
      ],
    );
  }
}
