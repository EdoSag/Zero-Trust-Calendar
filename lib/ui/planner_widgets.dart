import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zt_scheduler/zt_scheduler.dart';

import '../planner/planner_model.dart';
import '../util/format.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// "45 minutes", "2 hours", "1 h 30 min".
String formatPlanMinutes(AppL10n l, int minutes) {
  if (minutes < 60) return l.nMinutes(minutes);
  if (minutes % 60 == 0) return l.nHours(minutes ~/ 60);
  return l.plannerHoursMinutes(minutes ~/ 60, minutes % 60);
}

/// Why a block is where it is, as a sentence.
String planReasonText(AppL10n l, PlanReason? reason) => switch (reason) {
  PlanReason.deadline => l.plannerReasonDeadline,
  PlanReason.late => l.plannerReasonLate,
  PlanReason.locked => l.plannerReasonLocked,
  PlanReason.done => l.plannerReasonDone,
  _ => l.plannerReasonEarliest,
};

/// Lengths offered for a task, a block and the daily limit, in minutes.
const planLengthChoices = [15, 30, 45, 60, 90, 120, 180, 240, 300, 360, 480];
const planChunkChoices = [15, 30, 45, 60, 90, 120, 180, 240];
const planBreakChoices = [0, 5, 10, 15, 30];
const planDayChoices = [60, 120, 180, 240, 300, 360, 420, 480, 600, 720];

/// Asks for one of [choices] (minutes). Returns null when cancelled.
Future<int?> pickPlanMinutes(
  BuildContext context, {
  required String title,
  required List<int> choices,
  required int current,
  String? zeroLabel,
}) {
  final l = context.l10n;
  final all = {...choices, current}.toList()..sort();
  return showDialog<int>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(title),
      children: [
        for (final m in all)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialog).pop(m),
            child: Row(
              children: [
                Icon(
                  m == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: m == current ? Theme.of(dialog).colorScheme.primary : null,
                ),
                const SizedBox(width: 16),
                Text(m == 0 && zeroLabel != null ? zeroLabel : formatPlanMinutes(l, m)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// The weekdays in the order the app's language starts its week.
List<int> plannerWeekdays() => currentL10n.localeName.startsWith('he')
    ? const [7, 1, 2, 3, 4, 5, 6]
    : const [1, 2, 3, 4, 5, 6, 7];

/// The first day of the week for the default hours: Sunday in Hebrew
/// (work week Sunday to Thursday), Monday otherwise.
int plannerDefaultWeekStart() =>
    currentL10n.localeName.startsWith('he') ? DateTime.sunday : DateTime.monday;

/// "Sun to Thu, 09:00 to 17:00", or the days listed when their hours
/// differ, for the settings row.
String describePlanHours(BuildContext context, Map<int, List<MinuteRange>> hours) {
  final l = context.l10n;
  final days = [
    for (final d in plannerWeekdays())
      if ((hours[d] ?? const []).isNotEmpty) d,
  ];
  if (days.isEmpty) return l.plannerNoHours;
  final short = DateFormat.E(l.localeName);
  String name(int d) => short.format(DateTime(2024, 1, d));
  String clock(int m) =>
      formatTime(context, DateTime(2000, 1, 1, (m ~/ 60) % 24, m % 60));
  String ranges(int d) =>
      [for (final (s, e) in hours[d]!) ltr('${clock(s)}–${clock(e)}')].join(', ');
  final same = days.every((d) => ranges(d) == ranges(days.first));
  if (!same) return days.map(name).join(', ');
  final order = plannerWeekdays();
  final run = order.indexOf(days.last) - order.indexOf(days.first) + 1 == days.length;
  final which = days.length > 2 && run
      ? l.spanTo(name(days.first), name(days.last))
      : days.map(name).join(', ');
  return '$which, ${ranges(days.first)}';
}

/// One week of hours: each day on or off, with its time ranges.
class WeeklyHoursEditor extends StatelessWidget {
  const WeeklyHoursEditor({super.key, required this.hours, required this.onChanged});

  /// Weekday ([DateTime.monday] .. [DateTime.sunday]) to its ranges.
  final Map<int, List<MinuteRange>> hours;
  final ValueChanged<Map<int, List<MinuteRange>>> onChanged;

  void _set(int day, List<MinuteRange> ranges) {
    final sorted = [...ranges]..sort((a, b) => a.$1.compareTo(b.$1));
    onChanged({...hours, day: sorted});
  }

  Future<void> _pick(BuildContext context, int day, int index) async {
    final ranges = hours[day]!;
    final (s, e) = ranges[index];
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s ~/ 60, minute: s % 60),
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      // A range that ends at midnight is stored as 1440; the picker only
      // takes hours 0-23, so show it as 00:00.
      initialTime: TimeOfDay(hour: (e ~/ 60) % 24, minute: e % 60),
    );
    if (end == null || !context.mounted) return;
    final from = start.hour * 60 + start.minute;
    var to = end.hour * 60 + end.minute;
    if (to == 0) to = 1440;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
    if (to <= from) return say(context.l10n.plannerHoursEndFirst);
    final others = [...ranges]..removeAt(index);
    if (others.any((r) => r.$1 < to && from < r.$2)) {
      return say(context.l10n.plannerHoursOverlap);
    }
    _set(day, [...others, (from, to)]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dayName = DateFormat.EEEE(l.localeName);
    String clock(int m) =>
        formatTime(context, DateTime(2000, 1, 1, (m ~/ 60) % 24, m % 60));
    return Column(
      children: [
        for (final day in plannerWeekdays())
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 124,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: (hours[day] ?? const []).isNotEmpty,
                    // 1 January 2024 was a Monday.
                    title: Text(
                      dayName.format(DateTime(2024, 1, day)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (on) =>
                        _set(day, on == true ? const [(9 * 60, 17 * 60)] : const []),
                  ),
                ),
                Expanded(
                  child: (hours[day] ?? const []).isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            l.plannerDayOff,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : Wrap(
                          spacing: 4,
                          children: [
                            for (final (i, r) in hours[day]!.indexed)
                              InputChip(
                                label: Text(
                                  '${clock(r.$1)}–${clock(r.$2)}',
                                  textDirection: TextDirection.ltr,
                                ),
                                onPressed: () => _pick(context, day, i),
                                onDeleted: () =>
                                    _set(day, [...hours[day]!]..removeAt(i)),
                              ),
                            if (hours[day]!.length < 3 && hours[day]!.last.$2 <= 1380)
                              IconButton(
                                tooltip: l.bookingAddHours,
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  final last = hours[day]!.last.$2;
                                  _set(day, [
                                    ...hours[day]!,
                                    (last + 60 > 1380 ? 1380 : last + 60, (last + 180).clamp(0, 1440)),
                                  ]);
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
