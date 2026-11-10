import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _ready = false;

/// The IANA zone [id] ("Europe/Berlin"), or null when unknown.
tz.Location? zoneFor(String? id) {
  if (id == null || id.isEmpty) return null;
  if (!_ready) {
    tzdata.initializeTimeZones();
    _ready = true;
  }
  try {
    return tz.getLocation(id);
  } on Object {
    return null;
  }
}

/// [t]'s wall-clock time in [zone], as a plain local DateTime with those
/// fields (for rule expansion, which works on wall-clock fields).
DateTime wallClockIn(tz.Location zone, DateTime t) {
  final z = tz.TZDateTime.from(t, zone);
  return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second);
}

/// The instant of wall-clock [wall] in [zone], as a local DateTime.
DateTime instantFromWall(tz.Location zone, DateTime wall) {
  final z = tz.TZDateTime(
    zone, wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second,
  );
  return DateTime.fromMillisecondsSinceEpoch(z.millisecondsSinceEpoch);
}

/// Every IANA zone id ("Asia/Jerusalem"), sorted, without the legacy
/// aliases ("US/Eastern", "Etc/GMT+3").
List<String> allZoneIds() {
  zoneFor('UTC');
  return [
    for (final id in tz.timeZoneDatabase.locations.keys)
      if (id.contains('/') &&
          !id.startsWith('Etc/') &&
          !id.startsWith('US/') &&
          !id.startsWith('SystemV/'))
        id,
  ]..sort();
}

/// "UTC+02:00" for [zone] at [at] (the phone's own zone when null).
String utcOffsetLabel(tz.Location? zone, DateTime at) {
  final offset = zone == null
      ? at.timeZoneOffset
      : tz.TZDateTime.from(at, zone).timeZoneOffset;
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final abs = minutes.abs();
  return 'UTC$sign${(abs ~/ 60).toString().padLeft(2, '0')}:'
      '${(abs % 60).toString().padLeft(2, '0')}';
}

/// Whether [zone]'s clock reads differently from the phone's at [at].
bool differsFromPhone(tz.Location zone, DateTime at) =>
    tz.TZDateTime.from(at, zone).timeZoneOffset != at.timeZoneOffset;

/// "Asia/Jerusalem" -> "Jerusalem", "America/Argentina/Buenos_Aires" ->
/// "Buenos Aires".
String zoneCity(String id) => id.split('/').last.replaceAll('_', ' ');
