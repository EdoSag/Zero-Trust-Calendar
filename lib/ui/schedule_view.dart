import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/entries.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'navigation.dart';

/// The agenda: days with something on them, from the focused day on, with
/// today marked even when it's empty.
class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  static const _chunk = 120;
  int _daysBack = 0;
  int _daysAhead = _chunk;

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(focusedDayProvider);
    final from = addDays(focused, -_daysBack);
    final to = addDays(focused, _daysAhead);
    final async = ref.watch(entriesProvider(DateRange(from, to)));
    final entries = async.value;
    if (entries == null) {
      return async.hasError
          ? Center(child: Text('Could not load events: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    final today = dayOf(DateTime.now());
    final byDay = <DateTime, List<CalendarEntry>>{};
    for (final e in entries) {
      // A multi-day entry is listed on each of its days in the range.
      var d = dayOf(e.start.isBefore(from) ? from : e.start);
      while (d.isBefore(to) && e.coversDay(d)) {
        (byDay[d] ??= []).add(e);
        d = addDays(d, 1);
      }
    }
    if (!today.isBefore(from) && today.isBefore(to)) byDay.putIfAbsent(today, () => []);
    final days = byDay.keys.toList()..sort();
    final theme = Theme.of(context);

    return ListView.builder(
      itemCount: days.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _daysBack += 30),
              icon: const Icon(Icons.expand_less),
              label: const Text('Show earlier'),
            ),
          );
        }
        if (i == days.length + 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            child: Column(
              children: [
                if (days.length <= 1 && (byDay[today]?.isEmpty ?? true))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Nothing planned. Tap + to add an event.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() => _daysAhead += _chunk),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Show until ${DateFormat.yMMMd().format(addDays(to, _chunk))}'),
                ),
              ],
            ),
          );
        }
        final day = days[i - 1];
        final list = byDay[day]!;
        final showMonth = i == 1 || days[i - 2].month != day.month;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showMonth)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  formatMonthYear(day),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Column(
                      children: [
                        Text(
                          DateFormat.E().format(day),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: day == today
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: day == today
                              ? BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                )
                              : null,
                          child: Text(
                            '${day.day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: day == today
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Text(
                              'Nothing today',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final e in list)
                                EntryTile(
                                  entry: e,
                                  day: day,
                                  onTap: () => openEntry(context, ref, e),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
