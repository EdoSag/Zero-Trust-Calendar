import 'package:uuid/uuid.dart';

import '../model/calendar_event.dart';
import '../model/recurrence.dart';

/// Which occurrences of a repeating event a change applies to.
enum SeriesScope { thisEvent, thisAndFollowing, allEvents }

/// The saves and deletes one edit of a repeating event turns into. Pure,
/// so it is tested without storage.
class SeriesChange {
  SeriesChange({this.save = const [], this.delete = const []});
  final List<CalendarEvent> save;
  final List<String> delete;
}

abstract final class SeriesEdits {
  /// [series] edited to [edited] from its occurrence at [occurrence], for
  /// [scope]. [edited] carries the occurrence's new start and end.
  static SeriesChange edit({
    required CalendarEvent series,
    required DateTime occurrence,
    required CalendarEvent edited,
    required SeriesScope scope,
    List<CalendarEvent> exceptions = const [],
  }) {
    switch (scope) {
      case SeriesScope.thisEvent:
        return SeriesChange(
          save: [
            series.copyWith(exceptions: {...series.exceptions, occurrence}),
            edited.copyWith(
              id: const Uuid().v4(),
              rrule: null,
              exceptions: const {},
              seriesId: series.id,
              originalStart: occurrence,
              icalUid: null,
            ),
          ],
        );
      case SeriesScope.allEvents:
        // Moving one occurrence moves the whole series by as much.
        final shift = edited.start.difference(occurrence);
        final newStart = edited.allDay
            ? DateTime(
                series.start.year,
                series.start.month,
                series.start.day + (shift.inHours / 24).round(),
              )
            : series.start.add(shift);
        final newEnd = edited.allDay
            ? DateTime(
                newStart.year,
                newStart.month,
                newStart.day + (edited.duration.inHours / 24).round(),
              )
            : newStart.add(edited.duration);
        final rule = edited.recurrence;
        // A changed rule or time drops occurrence changes that no longer fit.
        final keepExceptions =
            shift == Duration.zero && edited.rrule == series.rrule;
        return SeriesChange(
          save: [
            edited.copyWith(
              id: series.id,
              start: newStart,
              end: newEnd,
              rrule: rule?.toString(),
              exceptions: keepExceptions ? series.exceptions : const {},
              seriesId: null,
              originalStart: null,
              icalUid: series.icalUid,
              createdAt: series.createdAt,
            ),
          ],
          delete: keepExceptions ? const [] : [for (final e in exceptions) e.id],
        );
      case SeriesScope.thisAndFollowing:
        if (!occurrence.isAfter(series.start)) {
          return edit(
            series: series,
            occurrence: occurrence,
            edited: edited,
            scope: SeriesScope.allEvents,
            exceptions: exceptions,
          );
        }
        final ended = endBefore(series, occurrence);
        final oldRule = series.recurrence;
        final newRule = edited.recurrence;
        var nextRule = newRule;
        // A COUNT is split between the two series.
        if (oldRule?.count != null && newRule != null && newRule.count == oldRule!.count) {
          final before = oldRule.between(series.start, series.start, occurrence).length;
          final left = oldRule.count! - before;
          nextRule = RecurrenceRule.tryParse(
            newRule.copyWith(clearEnd: true).toString(),
          )?.copyWith(count: left < 1 ? 1 : left);
        }
        return SeriesChange(
          save: [
            ended,
            edited.copyWith(
              id: const Uuid().v4(),
              rrule: nextRule?.toString(),
              exceptions: {
                for (final x in series.exceptions)
                  if (!x.isBefore(occurrence)) x,
              },
              seriesId: null,
              originalStart: null,
              icalUid: null,
            ),
          ],
          delete: [
            for (final e in exceptions)
              if (e.originalStart != null && !e.originalStart!.isBefore(occurrence)) e.id,
          ],
        );
    }
  }

  /// Deleting the occurrence at [occurrence] of [series].
  static SeriesChange delete({
    required CalendarEvent series,
    required DateTime occurrence,
    required SeriesScope scope,
    List<CalendarEvent> exceptions = const [],
  }) {
    switch (scope) {
      case SeriesScope.thisEvent:
        return SeriesChange(
          save: [series.copyWith(exceptions: {...series.exceptions, occurrence})],
        );
      case SeriesScope.thisAndFollowing when occurrence.isAfter(series.start):
        return SeriesChange(
          save: [endBefore(series, occurrence)],
          delete: [
            for (final e in exceptions)
              if (e.originalStart != null && !e.originalStart!.isBefore(occurrence)) e.id,
          ],
        );
      case SeriesScope.thisAndFollowing:
      case SeriesScope.allEvents:
        return SeriesChange(
          delete: [series.id, for (final e in exceptions) e.id],
        );
    }
  }

  /// [series] ending just before [occurrence].
  static CalendarEvent endBefore(CalendarEvent series, DateTime occurrence) {
    final rule = series.recurrence!;
    final lastStart = rule
        .between(series.start, series.start, occurrence)
        .lastOrNull;
    final until = lastStart ?? series.start;
    final ended = rule.copyWith(clearEnd: true);
    final withUntil = RecurrenceRule(
      frequency: ended.frequency,
      interval: ended.interval,
      until: series.allDay ? DateTime(until.year, until.month, until.day, 23, 59, 59) : until,
      byDay: ended.byDay,
      byMonthDay: ended.byMonthDay,
      byMonth: ended.byMonth,
      bySetPos: ended.bySetPos,
      weekStart: ended.weekStart,
    );
    return series.copyWith(
      rrule: withUntil.toString(),
      exceptions: {
        for (final x in series.exceptions)
          if (x.isBefore(occurrence)) x,
      },
    );
  }
}
