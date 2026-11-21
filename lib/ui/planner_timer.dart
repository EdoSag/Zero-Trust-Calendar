import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/calendar_event.dart';
import '../planner/planner_actions.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../util/format.dart';
import 'planner_block_sheet.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Timing work on a task: "Start now" puts a block at this moment, "Stop"
/// ends it at the time that was really worked, "Log time" adds time
/// already spent. Each is a block of the Planned calendar, so the time
/// worked counts toward the task like any done block and syncs like any
/// event.

/// How long a message with Undo stays. (Flutter keeps a snackbar that has
/// an action open until it is tapped unless it is told otherwise.)
const _undoFor = Duration(seconds: 6);

/// The time worked on a block being timed, as words.
String plannerElapsed(AppL10n l, DateTime started, DateTime now) {
  final minutes = now.difference(started).inMinutes;
  return minutes < 1 ? l.plannerLessThanAMinute : formatPlanMinutes(l, minutes);
}

void _say(
  ScaffoldMessengerState messenger,
  AppL10n l,
  String message, {
  Future<void> Function()? undo,
}) {
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

/// "Start now" on [block], with a way to undo. Returns whether it started.
Future<bool> startPlannerBlock(BuildContext context, WidgetRef ref, CalendarEvent block) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final actions = ref.read(plannerActionsProvider);
  try {
    await actions.start(block);
    _say(messenger, l, l.plannerTimerStarted, undo: () => actions.restore(block));
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    return false;
  }
}

/// "Start now" on [task]: its next block, or a new one.
Future<bool> startPlannerTask(BuildContext context, WidgetRef ref, PlannerTask task) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final actions = ref.read(plannerActionsProvider);
  final before = {for (final b in ref.read(plannerBlocksProvider)) b.id: b};
  try {
    final started = await actions.startTask(task);
    final old = before[started.id];
    _say(
      messenger,
      l,
      l.plannerTimerStarted,
      // A block that was there goes back where it was; a new one goes.
      undo: () => old == null ? actions.remove(started) : actions.restore(old),
    );
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    return false;
  }
}

/// "Stop" on the block being timed, with a way to undo (the timer then
/// runs on, and a task it finished is opened again).
Future<bool> stopPlannerBlock(BuildContext context, WidgetRef ref, CalendarEvent block) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final actions = ref.read(plannerActionsProvider);
  try {
    final (block: saved, :finished) = await actions.stop(block);
    final worked = formatPlanMinutes(l, saved.duration.inMinutes);
    _say(
      messenger,
      l,
      finished == null ? l.plannerTimerStopped(worked) : l.plannerTimerStoppedFinished(worked),
      undo: () async {
        await actions.restore(block);
        if (finished != null) await actions.reopenTask(finished);
      },
    );
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    return false;
  }
}

/// Lengths offered for time already worked, in minutes.
const planLogChoices = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240];

/// "Log time worked" on [task]: asks how long, and adds it ending now.
Future<bool> logPlannerTime(BuildContext context, WidgetRef ref, PlannerTask task) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final actions = ref.read(plannerActionsProvider);
  final minutes = await showDialog<int>(
    context: context,
    builder: (dialog) => SimpleDialog(
      key: const ValueKey('planner-log-time-dialog'),
      title: Text(l.plannerLogTimeTitle),
      children: [
        for (final m in planLogChoices)
          SimpleDialogOption(
            key: ValueKey('planner-log-$m'),
            onPressed: () => Navigator.of(dialog).pop(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(formatPlanMinutes(l, m)),
            ),
          ),
      ],
    ),
  );
  if (minutes == null) return false;
  try {
    final (:block, :finished) = await actions.logTime(task, minutes);
    final worked = formatPlanMinutes(l, minutes);
    _say(
      messenger,
      l,
      finished == null ? l.plannerTimeLogged(worked) : l.plannerTimeLoggedFinished(worked),
      undo: () async {
        await actions.remove(block);
        if (finished != null) await actions.reopenTask(finished);
      },
    );
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    return false;
  }
}

/// "Working on: Write report · Started 13:05 · 42 minutes", with Stop.
/// Across the top of the calendar and of the Planner's screen while a
/// block is being timed; nothing otherwise.
class PlannerRunningBar extends ConsumerStatefulWidget {
  const PlannerRunningBar({super.key, this.now});

  /// The clock, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<PlannerRunningBar> createState() => _PlannerRunningBarState();
}

class _PlannerRunningBarState extends ConsumerState<PlannerRunningBar> {
  Timer? _tick;
  bool _busy = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// The minutes shown move on while a block is being timed, and only then.
  void _keepTime(bool running) {
    if (!running) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final block = ref
        .watch(plannerBlocksProvider)
        .where((b) => PlanMark.of(b)!.runningAt(now))
        .firstOrNull;
    _keepTime(block != null);
    if (block == null) return const SizedBox.shrink();
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final started = PlanMark.of(block)!.started!;
    final title = block.title.trim().isEmpty ? l.noTitle : block.title.trim();
    return Material(
      key: const ValueKey('planner-running'),
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => showPlannerBlock(context, block),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.plannerWorkingOn}: $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l.plannerRunningSince(
                        formatTime(context, started),
                        plannerElapsed(l, started, now),
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The app's filled buttons are full width unless told otherwise.
              FilledButton.icon(
                key: const ValueKey('planner-running-stop'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await stopPlannerBlock(context, ref, block);
                        if (mounted) setState(() => _busy = false);
                      },
                icon: const Icon(Icons.stop),
                label: Text(l.plannerStop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
