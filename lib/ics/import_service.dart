import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../model/calendar_event.dart';
import 'ics.dart';

/// Turns .ics files, or a Google Takeout .zip of them (Takeout > Calendar
/// exports one .ics per calendar), into calendars and events to save.
class IcsImportPlan {
  IcsImportPlan({required this.newCalendars, required this.events, required this.skipped});
  final List<ZtCalendarInfo> newCalendars;
  final List<CalendarEvent> events;
  final int skipped;

  /// [files] are (file name, bytes). Events whose UID (and changed
  /// occurrence) is already in [existing] are skipped; each named calendar
  /// in the files maps to an existing calendar with that name, or a new one.
  static IcsImportPlan build({
    required List<(String, Uint8List)> files,
    required List<CalendarEvent> existing,
    required List<ZtCalendarInfo> calendars,
    String? intoCalendarId,
  }) {
    final texts = <(String, String)>[];
    for (final (name, bytes) in files) {
      if (name.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final f in archive.files) {
          if (f.isFile && f.name.toLowerCase().endsWith('.ics')) {
            texts.add((f.name, utf8.decode(f.content, allowMalformed: true)));
          }
        }
      } else {
        texts.add((name, utf8.decode(bytes, allowMalformed: true)));
      }
    }

    String key(String? uid, DateTime? original) =>
        '$uid|${original?.toUtc().toIso8601String() ?? ''}';
    final seen = {
      for (final e in existing)
        if (e.icalUid != null) key(e.icalUid, e.originalStart),
    };
    // Exceptions point at series by uid in the file; map them to the
    // existing series' id when the series is already here.
    final existingSeriesByUid = {
      for (final e in existing)
        if (e.icalUid != null && e.seriesId == null) e.icalUid!: e,
    };

    final byName = {for (final c in calendars) c.name.toLowerCase(): c};
    final newCalendars = <ZtCalendarInfo>[];
    final events = <CalendarEvent>[];
    var skipped = 0;
    var paletteIndex = calendars.length;

    for (final (fileName, text) in texts) {
      var calendarId = intoCalendarId;
      if (calendarId == null) {
        final parsedName = Ics.parse(text).name;
        final name = (parsedName == null || parsedName.isEmpty)
            ? _nameFromFile(fileName)
            : parsedName;
        final found = byName[name.toLowerCase()];
        if (found != null) {
          calendarId = found.id;
        } else {
          final created = ZtCalendarInfo(
            id: const Uuid().v4(),
            name: name,
            color: calendarPalette[paletteIndex++ % calendarPalette.length],
          );
          newCalendars.add(created);
          byName[name.toLowerCase()] = created;
          calendarId = created.id;
        }
      }
      final cal = Ics.parse(text, calendarId: calendarId);
      final idMap = <String, String>{};
      for (final e in cal.events) {
        if (e.seriesId == null && e.icalUid != null) {
          final existingSeries = existingSeriesByUid[e.icalUid!];
          if (existingSeries != null) idMap[e.id] = existingSeries.id;
        }
      }
      for (final e in cal.events) {
        if (seen.contains(key(e.icalUid, e.originalStart)) && e.icalUid != null) {
          skipped++;
          continue;
        }
        seen.add(key(e.icalUid, e.originalStart));
        final mappedSeries = e.seriesId == null ? null : idMap[e.seriesId] ?? e.seriesId;
        events.add(mappedSeries == e.seriesId ? e : e.copyWith(seriesId: mappedSeries));
      }
    }
    return IcsImportPlan(newCalendars: newCalendars, events: events, skipped: skipped);
  }

  /// `jane@gmail.com.ics` (Takeout's naming) becomes `jane@gmail.com`.
  static String _nameFromFile(String path) {
    var name = path.split('/').last;
    if (name.toLowerCase().endsWith('.ics')) {
      name = name.substring(0, name.length - 4);
    }
    return name.trim().isEmpty ? 'Imported' : name.trim();
  }
}
