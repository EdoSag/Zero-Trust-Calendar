import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import '../util/day_layout.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'navigation.dart';

const double _hourHeight = 56;
const double _gutter = 52;

/// Day, 3-day and week views: day columns over a 24-hour timeline, with
/// all-day entries in a strip on top. Swipe for the next days; tap an empty
/// hour to add an event there.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.days, required this.onOpenDay});

  /// 1, 3 or 7. A 7-day view starts on the week's first day.
  final int days;
  final void Function(DateTime day) onOpenDay;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  static const _origin = 10000;
  DateTime? _anchorOrNull;
  DateTime get _anchor => _anchorOrNull!;
  late PageController _pages;

  /// Shared by all pages, so swiping keeps the hours in view.
  double _scrollOffset = _hourHeight * 7.5;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: _origin);
    final now = DateTime.now();
    // Working hours, or the current time when that is later.
    _scrollOffset = _hourHeight * (now.hour - 1.5).clamp(7, 16);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs the locale (week start), so not in initState.
    _anchorOrNull ??= _pageStart(ref.read(focusedDayProvider));
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.days != widget.days) {
      _anchorOrNull = _pageStart(ref.read(focusedDayProvider));
      _pages.dispose();
      _pages = PageController(initialPage: _origin);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DateTime _pageStart(DateTime day) {
    if (widget.days == 7) {
      final settings = ref.read(calendarSettingsProvider);
      return startOfWeek(day, weekStartOf(context, settings));
    }
    return dayOf(day);
  }

  DateTime _startFor(int page) => addDays(_anchor, (page - _origin) * widget.days);

  int _pageFor(DateTime day) {
    final diff = (dayOf(day).difference(_anchor).inHours / 24).round();
    return _origin + (diff / widget.days).floor();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedDayProvider, (_, DateTime day) {
      final target = _pageFor(day);
      if (_pages.hasClients && _pages.page?.round() != target) {
        _pages.jumpToPage(target);
      }
    });
    return PageView.builder(
      controller: _pages,
      onPageChanged: (page) {
        final start = _startFor(page);
        final focused = ref.read(focusedDayProvider);
        final end = addDays(start, widget.days);
        if (focused.isBefore(start) || !focused.isBefore(end)) {
          final today = dayOf(DateTime.now());
          ref.read(focusedDayProvider.notifier).set(
            !today.isBefore(start) && today.isBefore(end) ? today : start,
          );
        }
      },
      itemBuilder: (context, page) => _TimelinePage(
        start: _startFor(page),
        days: widget.days,
        initialOffset: _scrollOffset,
        onScrolled: (o) => _scrollOffset = o,
        onOpenDay: widget.onOpenDay,
      ),
    );
  }
}

class _TimelinePage extends ConsumerStatefulWidget {
  const _TimelinePage({
    required this.start,
    required this.days,
    required this.initialOffset,
    required this.onScrolled,
    required this.onOpenDay,
  });

  final DateTime start;
  final int days;
  final double initialOffset;
  final ValueChanged<double> onScrolled;
  final void Function(DateTime day) onOpenDay;

  @override
  ConsumerState<_TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<_TimelinePage> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.initialOffset,
  );
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => widget.onScrolled(_scroll.offset));
    // Moves the "now" line.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = [for (var i = 0; i < widget.days; i++) addDays(widget.start, i)];
    final range = DateRange(widget.start, addDays(widget.start, widget.days));
    final entries = ref.watch(entriesProvider(range)).value ?? const [];
    final allDay = entries.where((e) => e.spansDays).toList();
    final timed = entries.where((e) => !e.spansDays).toList();
    final today = dayOf(DateTime.now());

    return Column(
      children: [
        // Day headers.
        Row(
          children: [
            const SizedBox(width: _gutter),
            for (final d in days)
              Expanded(
                child: InkWell(
                  onTap: widget.days == 1 ? null : () => widget.onOpenDay(d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Text(
                          DateFormat.E().format(d),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: d == today ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: d == today
                              ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                              : null,
                          child: Text(
                            '${d.day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: d == today ? scheme.onPrimary : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        // All-day strip.
        if (allDay.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 92),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: _gutter),
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Column(
                          children: [
                            for (final e in allDay)
                              if (e.coversDay(d))
                                EntryChip(
                                  entry: e,
                                  dense: widget.days > 3,
                                  onTap: () => openEntry(context, ref, e),
                                ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: _hourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * _hourHeight - 7,
                            right: 6,
                            child: Text(
                              formatHour(context, h),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: _DayColumn(
                        day: d,
                        isToday: d == today,
                        entries: [for (final e in timed) if (e.coversDay(d)) e],
                        compact: widget.days > 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.entries,
    required this.compact,
  });

  final DateTime day;
  final bool isToday;
  final List<CalendarEntry> entries;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dayEnd = addDays(day, 1);
    final placements = layoutDay([
      for (final e in entries)
        (
          e,
          e.start.isBefore(day) ? day : e.start,
          e.end.isAfter(dayEnd) ? dayEnd : e.end,
        ),
    ]);
    double y(DateTime t) =>
        (t.difference(day).inMinutes / 60).clamp(0, 24) * _hourHeight;
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final hour = (details.localPosition.dy / _hourHeight).floor().clamp(0, 23);
            final half = (details.localPosition.dy % _hourHeight) >= _hourHeight / 2;
            createEvent(
              context,
              start: DateTime(day.year, day.month, day.day, hour, half ? 30 : 0),
            );
          },
          child: Stack(
            children: [
              // Hour lines.
              for (var h = 0; h < 24; h++)
                Positioned(
                  top: h * _hourHeight,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 0.5,
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(width: 0.5, color: scheme.outlineVariant),
              ),
              for (final p in placements)
                Positioned(
                  top: y(p.start) + 1,
                  height: (y(p.end) - y(p.start)).clamp(18.0, double.infinity) - 2,
                  left: width / p.columns * p.column + 1,
                  width: width / p.columns - 2,
                  child: _TimedBlock(entry: p.item, compact: compact),
                ),
              if (isToday)
                Positioned(
                  top: y(now) - 1,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(child: Container(height: 2, color: scheme.error)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimedBlock extends ConsumerWidget {
  const _TimedBlock({required this.entry, required this.compact});

  final CalendarEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = eventColor(entry.color);
    final fg = onColor(color);
    final isTask = entry.kind == EntryKind.task;
    return Semantics(
      button: true,
      label: '${entry.title}, ${formatSpan(context, entry.start, entry.end, false)}',
      excludeSemantics: true,
      child: Material(
        color: isTask ? color.withValues(alpha: 0.25) : color,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openEntry(context, ref, entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: LayoutBuilder(
              builder: (context, c) {
                final tall = c.maxHeight > 34;
                final textColor = isTask
                    ? Theme.of(context).colorScheme.onSurface
                    : fg;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: tall ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: compact ? 11 : 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        decoration: isTask && (entry.task?.completed ?? false)
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (tall && !compact)
                      Text(
                        [
                          formatSpan(context, entry.start, entry.end, false),
                          if ((entry.event?.location ?? '').isNotEmpty)
                            entry.event!.location,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
