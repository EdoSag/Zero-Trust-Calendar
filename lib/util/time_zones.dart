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
