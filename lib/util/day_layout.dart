/// Where a timed entry sits in a day column: its column and the number of
/// columns in its group of overlapping entries.
class Placement<T> {
  Placement(this.item, this.start, this.end, this.column, this.columns);
  final T item;
  final DateTime start;
  final DateTime end;
  final int column;
  int columns;
}

/// Lays out overlapping entries side by side, like every calendar app:
/// entries that overlap (directly or through a chain) share the width,
/// each in the first free column. Entries shorter than [minLength] are
/// treated as that long, so they don't draw on top of each other.
List<Placement<T>> layoutDay<T>(
  List<(T, DateTime, DateTime)> entries, {
  Duration minLength = const Duration(minutes: 20),
}) {
  final sorted = [...entries]
    ..sort((a, b) {
      final s = a.$2.compareTo(b.$2);
      return s != 0 ? s : b.$3.compareTo(a.$3);
    });
  final out = <Placement<T>>[];
  var group = <Placement<T>>[];
  var columnEnds = <DateTime>[];
  DateTime? groupEnd;

  void closeGroup() {
    for (final p in group) {
      p.columns = columnEnds.length;
    }
    group = [];
    columnEnds = [];
    groupEnd = null;
  }

  for (final (item, start, end) in sorted) {
    final visualEnd = end.difference(start) < minLength
        ? start.add(minLength)
        : end;
    if (groupEnd != null && !start.isBefore(groupEnd!)) closeGroup();
    var column = columnEnds.indexWhere((e) => !e.isAfter(start));
    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(visualEnd);
    } else {
      columnEnds[column] = visualEnd;
    }
    final p = Placement(item, start, end, column, 1);
    group.add(p);
    out.add(p);
    if (groupEnd == null || visualEnd.isAfter(groupEnd!)) groupEnd = visualEnd;
  }
  closeGroup();
  return out;
}
