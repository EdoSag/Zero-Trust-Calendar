import 'package:flutter/material.dart';

import '../data/entries.dart';
import '../util/format.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

IconData? entryIcon(CalendarEntry e) => switch (e.kind) {
  EntryKind.task => Icons.task_alt,
  EntryKind.birthday => Icons.cake_outlined,
  EntryKind.event =>
    (e.event?.noteIds.isNotEmpty ?? false) ? Icons.sticky_note_2_outlined : null,
};

/// A small coloured label, for the month grid and the all-day strip.
class EntryChip extends StatelessWidget {
  const EntryChip({
    super.key,
    required this.entry,
    this.onTap,
    this.showTime = false,
    this.dense = true,
  });

  final CalendarEntry entry;
  final VoidCallback? onTap;
  final bool showTime;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = eventColor(entry.color);
    final filled = entry.allDay || entry.spansDays;
    final text = showTime && !entry.allDay
        ? '${formatTime(context, entry.start)} ${entry.title}'
        : entry.title;
    final fg = filled ? onColor(color) : Theme.of(context).colorScheme.onSurface;
    final style = TextStyle(
      fontSize: dense ? 11 : 13,
      height: 1.2,
      color: fg,
      fontWeight: FontWeight.w500,
    );
    final icon = entryIcon(entry);
    return Semantics(
      button: onTap != null,
      label: '${entry.title}, ${entry.allDay ? context.l10n.allDayLower : formatTime(context, entry.start)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1.5),
          padding: EdgeInsets.symmetric(horizontal: 3, vertical: dense ? 1 : 3),
          decoration: BoxDecoration(
            color: filled ? color : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (!filled)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsetsDirectional.only(end: 3),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              if (icon != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 2),
                  child: Icon(icon, size: dense ? 10 : 13, color: fg),
                ),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in the schedule and in lists: colour bar, title, time, place.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.onTap, this.day});

  final CalendarEntry entry;
  final VoidCallback? onTap;

  /// The day this row is listed under, for multi-day entries' times.
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = eventColor(entry.color);
    String when;
    if (entry.allDay) {
      when = context.l10n.allDay;
    } else if (day != null && !sameDay(entry.start, day!) ) {
      when = sameDay(entry.end, day!) ? context.l10n.untilTime(formatTime(context, entry.end)) : context.l10n.allDay;
    } else {
      when = entry.kind == EntryKind.task
          ? context.l10n.dueAt(formatTime(context, entry.start))
          : formatSpan(context, entry.start, entry.end, false);
    }
    final location = entry.event?.location ?? '';
    final icon = entryIcon(entry);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: BorderDirectional(start: BorderSide(color: color, width: 4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [when, if (location.isNotEmpty) location].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (entry.isOccurrenceOfSeries)
                Icon(Icons.repeat, size: 16, color: theme.colorScheme.onSurfaceVariant),
              if (icon != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
