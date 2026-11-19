import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../planner/planner_actions.dart';
import '../planner/planner_model.dart';
import '../util/format.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// A minute of the day as the phone writes times: "12:30" or "12:30 PM".
String formatMinuteOfDay(BuildContext context, int minute) =>
    formatTime(context, DateTime(2000, 1, 1, minute ~/ 60, minute % 60));

/// "Mon, Wed, Fri · 1 h · around 18:00", or "Every day · ...".
String describeHabit(BuildContext context, PlannerHabit h) {
  final l = context.l10n;
  final short = DateFormat.E(l.localeName);
  final days = h.days.length == 7
      ? l.plannerEveryDay
      : [
          for (final d in plannerWeekdays())
            if (h.days.contains(d)) short.format(DateTime(2026, 11, 15 + d)),
        ].join(', ');
  return [
    days,
    formatPlanMinutes(l, h.minutes),
    l.plannerAround(formatMinuteOfDay(context, h.ideal)),
  ].join(' · ');
}

/// Choices to start a new habit from, then the editor.
Future<void> addPlannerHabit(BuildContext context) async {
  final l = context.l10n;
  final weekStart = plannerDefaultWeekStart();
  final id = const Uuid().v4();
  final picked = await showDialog<PlannerHabit>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(l.plannerAddHabit),
      children: [
        for (final (icon, habit) in [
          (Icons.restaurant, PlannerHabit.lunch(id, l.plannerHabitLunch)),
          (
            Icons.fitness_center,
            PlannerHabit.exercise(id, l.plannerHabitExercise, {
              for (final i in const [0, 2, 4]) (weekStart - 1 + i) % 7 + 1,
            }),
          ),
          (
            Icons.edit_outlined,
            PlannerHabit(
              id: id,
              title: '',
              minutes: 30,
              days: const {1, 2, 3, 4, 5, 6, 7},
              ideal: 9 * 60,
              earliest: 7 * 60,
              latest: 21 * 60,
            ),
          ),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialog).pop(habit),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 16),
                Expanded(child: Text(habit.title.isEmpty ? l.plannerHabitOther : habit.title)),
              ],
            ),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlannerHabitPage(habit: picked, isNew: true)),
  );
}

/// Edits one habit: name, days, length, when, what happens when there's
/// no room, which hours; pause or delete it.
class PlannerHabitPage extends ConsumerStatefulWidget {
  const PlannerHabitPage({super.key, required this.habit, this.isNew = false});
  final PlannerHabit habit;
  final bool isNew;

  @override
  ConsumerState<PlannerHabitPage> createState() => _PlannerHabitPageState();
}

class _PlannerHabitPageState extends ConsumerState<PlannerHabitPage> {
  late PlannerHabit _habit = widget.habit;
  late final _title = TextEditingController(text: widget.habit.title);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _fits => _habit.latest - _habit.earliest >= _habit.minutes;

  Future<int?> _pickTime(int minute, String help) async {
    final t = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: minute ~/ 60 % 24, minute: minute % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final title = _title.text.trim();
    // The ideal start always leaves room to finish inside the window.
    final latestStart = _habit.latest - _habit.minutes;
    final habit = _habit.copyWith(
      title: title.isEmpty ? l.plannerHabitUntitled : title,
      ideal: _habit.ideal.clamp(_habit.earliest, latestStart),
    );
    setState(() => _saving = true);
    try {
      await ref.read(plannerActionsProvider).saveHabit(habit);
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.plannerDeleteHabitTitle),
        content: Text(l.plannerDeleteHabitBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(plannerActionsProvider).deleteHabit(_habit.id);
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final short = DateFormat.E(l.localeName);
    final h = _habit;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? l.plannerAddHabit : l.plannerEditHabit),
        actions: [
          if (!widget.isNew)
            IconButton(
              key: const ValueKey('habit-delete'),
              icon: const Icon(Icons.delete_outline),
              tooltip: l.delete,
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('habit-title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.plannerHabitName,
                hintText: l.plannerHabitNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.plannerHabitDays, style: theme.textTheme.titleSmall),
          ),
          Padding(
            key: const ValueKey('habit-days'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in plannerWeekdays())
                  FilterChip(
                    key: ValueKey('habit-day-$d'),
                    label: Text(short.format(DateTime(2026, 11, 15 + d))),
                    selected: h.days.contains(d),
                    onSelected: (on) => setState(
                      () => _habit = _habit.copyWith(days: on ? {..._habit.days, d} : ({..._habit.days}..remove(d))),
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('habit-length'),
            title: Text(l.plannerHabitLength),
            trailing: Text(formatPlanMinutes(l, h.minutes)),
            onTap: () async {
              final m = await pickPlanMinutes(
                context,
                title: l.plannerHabitLength,
                choices: const [15, 30, 45, 60, 90, 120, 180],
                current: h.minutes,
              );
              if (m == null) return;
              setState(() {
                final min = _habit.minMinutes;
                _habit = _habit.copyWith(minutes: m, minMinutes: min != null && min >= m ? null : min);
              });
            },
          ),
          ListTile(
            key: const ValueKey('habit-ideal'),
            title: Text(l.plannerHabitIdeal),
            trailing: Text(formatMinuteOfDay(context, h.ideal)),
            onTap: () async {
              final m = await _pickTime(h.ideal, l.plannerHabitIdeal);
              if (m != null) setState(() => _habit = _habit.copyWith(ideal: m));
            },
          ),
          ListTile(
            key: const ValueKey('habit-window'),
            title: Text(l.plannerHabitWindow),
            subtitle: _fits ? null : Text(l.plannerHabitWindowTooShort, style: TextStyle(color: theme.colorScheme.error)),
            trailing: Text(
              l.plannerHabitBetween(
                formatMinuteOfDay(context, h.earliest),
                formatMinuteOfDay(context, h.latest % (24 * 60)),
              ),
            ),
            onTap: () async {
              final from = await _pickTime(h.earliest, l.plannerHabitFrom);
              if (from == null || !mounted) return;
              final to = await _pickTime(h.latest, l.plannerHabitTo);
              if (to == null) return;
              // Midnight as the end means the end of the day.
              final end = to == 0 ? 24 * 60 : to;
              if (end <= from) return;
              setState(() => _habit = _habit.copyWith(earliest: from, latest: end));
            },
          ),
          ListTile(
            key: const ValueKey('habit-no-room'),
            title: Text(l.plannerHabitNoRoom),
            subtitle: Text(
              h.minMinutes == null
                  ? l.plannerHabitSkipDay
                  : l.plannerHabitShortenTo(formatPlanMinutes(l, h.minMinutes!)),
            ),
            onTap: () async {
              final choices = [for (final m in const [15, 30, 45, 60, 90]) if (m < h.minutes) m];
              final picked = await pickPlanMinutes(
                context,
                title: l.plannerHabitNoRoom,
                choices: [0, ...choices],
                current: h.minMinutes ?? 0,
                zeroLabel: l.plannerHabitSkipDay,
              );
              if (picked != null) setState(() => _habit = _habit.copyWith(minMinutes: picked == 0 ? null : picked));
            },
          ),
          ListTile(
            key: const ValueKey('habit-hours'),
            title: Text(l.plannerPlanIn),
            trailing: Text(switch (h.hoursId) {
              workHoursId => l.plannerWorkHours,
              personalHoursId => l.plannerPersonalHours,
              _ => l.plannerAnyTime,
            }),
            onTap: () async {
              final picked = await showDialog<String>(
                context: context,
                builder: (dialog) => SimpleDialog(
                  title: Text(l.plannerPlanIn),
                  children: [
                    for (final (id, label) in [
                      ('', l.plannerAnyTime),
                      (workHoursId, l.plannerWorkHours),
                      (personalHoursId, l.plannerPersonalHours),
                    ])
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(dialog).pop(id),
                        child: Row(
                          children: [
                            Icon(
                              (h.hoursId ?? '') == id ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 20,
                            ),
                            const SizedBox(width: 16),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              );
              if (picked != null) setState(() => _habit = _habit.copyWith(hoursId: picked.isEmpty ? null : picked));
            },
          ),
          SwitchListTile(
            key: const ValueKey('habit-paused'),
            title: Text(l.plannerHabitPaused),
            subtitle: Text(l.plannerHabitPausedHint),
            value: h.paused,
            onChanged: (on) => setState(() => _habit = _habit.copyWith(paused: on)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          key: const ValueKey('habit-save'),
          onPressed: _saving || h.days.isEmpty || !_fits ? null : _save,
          child: Text(l.save),
        ),
      ),
    );
  }
}
