import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/entries.dart';
import '../util/format.dart';
import 'month_view.dart' show WeekNumberLabel;

/// The days in [range] that have at least one entry on them, for the
/// marks in the year view and the side panel's month.
Set<DateTime> busyDays(Iterable<CalendarEntry> entries, DateRange range) {
  final out = <DateTime>{};
  for (final e in entries) {
    var day = dayOf(e.start.isBefore(range.from) ? range.from : e.start);
    final last = e.end.isAfter(range.to) ? range.to : e.end;
    // An entry with no length still marks its own day.
    do {
      out.add(day);
      day = addDays(day, 1);
    } while (day.isBefore(last));
  }
  return out;
}

/// A small month grid: the year view's twelve, and the month in the
/// tablet side panel. Always six rows, so months line up side by side.
class MiniMonth extends StatelessWidget {
  const MiniMonth({
    super.key,
    required this.month,
    required this.weekStart,
    required this.onTapDay,
    this.busy = const {},
    this.selected,
    this.showWeekNumbers = false,
    this.showOtherMonths = false,
    this.onTapTitle,
    this.header,
    this.maxCellHeight = 36,
  });

  final DateTime month;
  final int weekStart;
  final ValueChanged<DateTime> onTapDay;

  /// Days drawn with a tint: something is on them.
  final Set<DateTime> busy;

  /// The day the calendar is on (the side panel), outlined.
  final DateTime? selected;
  final bool showWeekNumbers;

  /// Days of the months before and after, dimmed (the side panel). Off,
  /// they are left blank (the year view).
  final bool showOtherMonths;
  final VoidCallback? onTapTitle;

  /// Replaces the month name row (the side panel puts arrows there).
  final Widget? header;
  final double maxCellHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = startOfWeek(DateTime(month.year, month.month), weekStart);
    final today = dayOf(DateTime.now());
    final isThisMonth = month.year == today.year && month.month == today.month;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = 7 + (showWeekNumbers ? 1 : 0);
        final cellWidth = constraints.maxWidth / columns;
        final cellHeight = math.min(cellWidth, maxCellHeight);
        final fontSize = (cellHeight * 0.45).clamp(8.0, 13.0);
        final dayStyle = theme.textTheme.labelSmall?.copyWith(fontSize: fontSize);

        Widget dayCell(DateTime day) {
          final inMonth = day.month == month.month;
          if (!inMonth && !showOtherMonths) return SizedBox(width: cellWidth, height: cellHeight);
          final isToday = day == today;
          final isSelected = selected != null && sameDay(day, selected!) && !isToday;
          final isBusy = busy.contains(day);
          final circle = math.min(cellWidth, cellHeight) - 2;
          return SizedBox(
            width: cellWidth,
            height: cellHeight,
            child: Semantics(
              button: true,
              selected: isSelected,
              label: formatLongDay(day),
              excludeSemantics: true,
              child: InkResponse(
                radius: circle / 2 + 2,
                onTap: () => onTapDay(day),
                child: Center(
                  child: Container(
                    width: circle,
                    height: circle,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday
                          ? scheme.primary
                          : isBusy
                          ? scheme.primary.withValues(alpha: 0.16)
                          : null,
                      border: isSelected ? Border.all(color: scheme.primary, width: 1.5) : null,
                    ),
                    child: Text(
                      '${day.day}',
                      style: dayStyle?.copyWith(
                        color: isToday
                            ? scheme.onPrimary
                            : inMonth
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontWeight: isToday || isBusy ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header ??
                InkWell(
                  onTap: onTapTitle,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 4),
                    child: Text(
                      DateFormat.MMMM().format(month),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isThisMonth ? scheme.primary : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            Row(
              children: [
                if (showWeekNumbers) SizedBox(width: cellWidth),
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: cellWidth,
                    child: Text(
                      // Narrow names: "M", or "ב׳" in Hebrew.
                      DateFormat('EEEEE').format(addDays(first, i)),
                      textAlign: TextAlign.center,
                      style: dayStyle?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            for (var w = 0; w < 6; w++)
              Row(
                children: [
                  if (showWeekNumbers)
                    SizedBox(
                      height: cellHeight,
                      child: WeekNumberLabel(
                        rowStart: addDays(first, w * 7),
                        width: cellWidth,
                        fontSize: fontSize * 0.85,
                        centered: true,
                      ),
                    ),
                  for (var d = 0; d < 7; d++) dayCell(addDays(first, w * 7 + d)),
                ],
              ),
          ],
        );
      },
    );
  }
}
