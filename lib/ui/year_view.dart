import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import 'mini_month.dart';
import 'navigation.dart';

/// Year view (K11): the twelve months as small grids, swiped left and
/// right by year. Days with something on them are tinted. Tapping a day
/// opens it in the day view; tapping a month's name opens that month.
class YearView extends ConsumerStatefulWidget {
  const YearView({super.key, required this.onOpenDay, required this.onOpenMonth});

  final void Function(DateTime day) onOpenDay;
  final void Function(DateTime month) onOpenMonth;

  @override
  ConsumerState<YearView> createState() => _YearViewState();
}

class _YearViewState extends ConsumerState<YearView> {
  static const _origin = 500; // Page for the focused year at start.
  late final int _anchor = ref.read(focusedDayProvider).year;
  late final PageController _pages = PageController(initialPage: _origin);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedDayProvider, (_, DateTime day) {
      final target = _origin + day.year - _anchor;
      if (_pages.hasClients && _pages.page?.round() != target) {
        _pages.jumpToPage(target);
      }
    });
    return PageView.builder(
      controller: _pages,
      onPageChanged: (page) {
        final year = _anchor + page - _origin;
        final focused = ref.read(focusedDayProvider);
        if (focused.year != year) {
          final today = DateTime.now();
          // This year: today. Another year: the same day there.
          ref.read(focusedDayProvider.notifier).set(
            today.year == year ? today : DateTime(year, focused.month, 1),
          );
        }
      },
      itemBuilder: (context, page) => _YearPage(
        year: _anchor + page - _origin,
        onOpenDay: widget.onOpenDay,
        onOpenMonth: widget.onOpenMonth,
      ),
    );
  }
}

class _YearPage extends ConsumerWidget {
  const _YearPage({required this.year, required this.onOpenDay, required this.onOpenMonth});

  final int year;
  final void Function(DateTime day) onOpenDay;
  final void Function(DateTime month) onOpenMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(calendarSettingsProvider);
    final weekStart = weekStartOf(context, settings);
    final range = DateRange(DateTime(year), DateTime(year + 1));
    final entries = ref.watch(entriesProvider(range)).value ?? const [];
    final busy = busyDays(entries, range);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 3 across on a phone, 4 on a tablet or in landscape, 6 when wide.
        final perRow = width >= 1200 ? 6 : width >= 600 ? 4 : 3;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
          child: Column(
            children: [
              for (var r = 0; r < 12 ~/ perRow; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < perRow; c++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: MiniMonth(
                              month: DateTime(year, r * perRow + c + 1),
                              weekStart: weekStart,
                              busy: busy,
                              showWeekNumbers: settings.showWeekNumbers,
                              onTapDay: onOpenDay,
                              onTapTitle: () => onOpenMonth(DateTime(year, r * perRow + c + 1)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
