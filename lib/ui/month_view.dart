import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'jewish_calendar_page.dart';
import 'navigation.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Month grid, swiped left and right. Tapping a day opens it in the day
/// view; a long press starts a new all-day event on it.
class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key, required this.onOpenDay});

  final void Function(DateTime day) onOpenDay;

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  static const _origin = 1200; // Page for the focused month at start.
  late final DateTime _anchor;
  late final PageController _pages;

  @override
  void initState() {
    super.initState();
    final f = ref.read(focusedDayProvider);
    _anchor = DateTime(f.year, f.month);
    _pages = PageController(initialPage: _origin);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DateTime _monthFor(int page) =>
      DateTime(_anchor.year, _anchor.month + page - _origin);

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedDayProvider, (_, DateTime day) {
      final target = _origin +
          (day.year - _anchor.year) * 12 +
          (day.month - _anchor.month);
      if (_pages.hasClients && _pages.page?.round() != target) {
        _pages.jumpToPage(target);
      }
    });
    return PageView.builder(
      controller: _pages,
      onPageChanged: (page) {
        final month = _monthFor(page);
        final focused = ref.read(focusedDayProvider);
        if (focused.year != month.year || focused.month != month.month) {
          final today = DateTime.now();
          ref.read(focusedDayProvider.notifier).set(
            today.year == month.year && today.month == month.month
                ? today
                : month,
          );
        }
      },
      itemBuilder: (context, page) => _MonthPage(
        month: _monthFor(page),
        onOpenDay: widget.onOpenDay,
      ),
    );
  }
}

class _MonthPage extends ConsumerWidget {
  const _MonthPage({required this.month, required this.onOpenDay});

  final DateTime month;
  final void Function(DateTime day) onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(calendarSettingsProvider);
    final weekStart = weekStartOf(context, settings);
    final first = startOfWeek(month, weekStart);
    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    final allWeeks =
        ((lastOfMonth.difference(first).inHours / 24).round() + 1 + 6) ~/ 7;
    final range = DateRange(first, addDays(first, allWeeks * 7));
    final entries = ref.watch(entriesProvider(range)).value ?? const [];
    final theme = Theme.of(context);
    final today = dayOf(DateTime.now());
    // "Hide weekends": those columns go; so does a row left with no day of
    // this month.
    final hidden = settings.hideWeekends ? weekendDays(context) : const <int>{};
    final columns = [
      for (var i = 0; i < 7; i++)
        if (!hidden.contains(addDays(first, i).weekday)) i,
    ];
    final weeks = [
      for (var w = 0; w < allWeeks; w++)
        if (columns.any((d) => addDays(first, w * 7 + d).month == month.month)) w,
    ];
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (settings.showWeekNumbers) const SizedBox(width: weekNumberWidth),
              for (final i in columns)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.E().format(addDays(first, i)),
                      style: labelStyle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (final w in weeks)
                Expanded(
                  child: Row(
                    children: [
                      if (settings.showWeekNumbers)
                        WeekNumberLabel(rowStart: addDays(first, w * 7)),
                      for (final d in columns)
                        Expanded(
                          child: _DayCell(
                            day: addDays(first, w * 7 + d),
                            inMonth: addDays(first, w * 7 + d).month == month.month,
                            isToday: addDays(first, w * 7 + d) == today,
                            entries: [
                              for (final e in entries)
                                if (e.coversDay(addDays(first, w * 7 + d))) e,
                            ],
                            onTap: () => onOpenDay(addDays(first, w * 7 + d)),
                            onLongPress: () => createEvent(
                              context,
                              start: addDays(first, w * 7 + d),
                              allDay: true,
                            ),
                          ),
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

/// Width of the week number column beside the month and year views.
const double weekNumberWidth = 26;

/// The week number beside a row of days starting on [rowStart] ("W47").
class WeekNumberLabel extends StatelessWidget {
  const WeekNumberLabel({
    super.key,
    required this.rowStart,
    this.width = weekNumberWidth,
    this.fontSize,
    this.centered = false,
  });

  final DateTime rowStart;
  final double width;
  final double? fontSize;

  /// Centred in its row (the small month grids); otherwise at the top,
  /// level with the day numbers.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = weekNumberOfRow(rowStart);
    return SizedBox(
      width: width,
      child: Semantics(
        label: context.l10n.weekNumberLong(n),
        excludeSemantics: true,
        child: Container(
          alignment: centered ? Alignment.center : Alignment.topCenter,
          padding: centered ? null : const EdgeInsets.only(top: 6),
          child: Text(
            '$n',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: fontSize,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.entries,
    required this.onTap,
    required this.onLongPress,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<CalendarEntry> entries;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(
            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.5),
            start: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const header = 24.0;
            const chip = 16.5;
            final fit = ((constraints.maxHeight - header) / chip).floor();
            final shown = entries.length <= fit ? entries.length : (fit - 1).clamp(0, entries.length);
            final more = entries.length - shown;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: header,
                  child: _withHebrewDate(
                    context,
                    ref,
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: isToday
                          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                          : null,
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isToday
                              ? scheme.onPrimary
                              : inMonth
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontWeight: isToday ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final e in entries.take(shown))
                  EntryChip(entry: e, onTap: () => openEntry(context, ref, e)),
                if (more > 0)
                  Text(
                    '+$more',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The day number centred, or with "Hebrew dates" on, at the start with
  /// the Hebrew day at the end (K-1).
  Widget _withHebrewDate(BuildContext context, WidgetRef ref, Widget number) {
    if (!ref.watch(calendarSettingsProvider.select((s) => s.hebrewDates))) {
      return Center(child: number);
    }
    final theme = Theme.of(context);
    return Row(
      children: [
        number,
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            hebrewCellLabel(context, day),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: inMonth ? 0.9 : 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
