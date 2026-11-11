import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'navigation.dart';

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
    final weeks =
        ((lastOfMonth.difference(first).inHours / 24).round() + 1 + 6) ~/ 7;
    final range = DateRange(first, addDays(first, weeks * 7));
    final entries = ref.watch(entriesProvider(range)).value ?? const [];
    final theme = Theme.of(context);
    final today = dayOf(DateTime.now());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.E().format(addDays(first, i)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
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
                  child: Center(
                    child: Container(
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
}
