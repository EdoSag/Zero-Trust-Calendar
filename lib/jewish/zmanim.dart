import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../util/time_zones.dart';
import 'jewish_holidays.dart';

/// A city Shabbat times are computed for (K-1). No location permission:
/// the user picks one.
class ZmanimCity {
  const ZmanimCity(
    this.id,
    this.nameEn,
    this.nameHe,
    this.latitude,
    this.longitude,
    this.timeZone, {
    this.israel = false,
    this.candleMinutes = 18,
  });

  final String id;
  final String nameEn;
  final String nameHe;
  final double latitude;
  final double longitude;

  /// IANA zone, for which day a sunset belongs to.
  final String timeZone;

  /// Holidays are kept as in Israel (one festival day).
  final bool israel;

  /// Candles are lit this many minutes before sunset (40 in Jerusalem, 30
  /// in Haifa, 20 in Petah Tikva, 18 elsewhere, as most Israeli and
  /// community calendars do).
  final int candleMinutes;

  String name({required bool hebrew}) => hebrew ? nameHe : nameEn;
}

const zmanimCities = <ZmanimCity>[
  ZmanimCity('jerusalem', 'Jerusalem', 'ירושלים', 31.7683, 35.2137, 'Asia/Jerusalem', israel: true, candleMinutes: 40),
  ZmanimCity('tel-aviv', 'Tel Aviv', 'תל אביב', 32.0853, 34.7818, 'Asia/Jerusalem', israel: true),
  ZmanimCity('haifa', 'Haifa', 'חיפה', 32.7940, 34.9896, 'Asia/Jerusalem', israel: true, candleMinutes: 30),
  ZmanimCity('beer-sheva', "Be'er Sheva", 'באר שבע', 31.2518, 34.7913, 'Asia/Jerusalem', israel: true),
  ZmanimCity('petah-tikva', 'Petah Tikva', 'פתח תקווה', 32.0840, 34.8878, 'Asia/Jerusalem', israel: true, candleMinutes: 20),
  ZmanimCity('rishon-lezion', 'Rishon LeZion', 'ראשון לציון', 31.9730, 34.7925, 'Asia/Jerusalem', israel: true),
  ZmanimCity('netanya', 'Netanya', 'נתניה', 32.3215, 34.8532, 'Asia/Jerusalem', israel: true),
  ZmanimCity('ashdod', 'Ashdod', 'אשדוד', 31.8014, 34.6435, 'Asia/Jerusalem', israel: true),
  ZmanimCity('herzliya', 'Herzliya', 'הרצליה', 32.1624, 34.8447, 'Asia/Jerusalem', israel: true),
  ZmanimCity('raanana', "Ra'anana", 'רעננה', 32.1848, 34.8713, 'Asia/Jerusalem', israel: true),
  ZmanimCity('modiin', "Modi'in", 'מודיעין', 31.8980, 35.0104, 'Asia/Jerusalem', israel: true),
  ZmanimCity('tiberias', 'Tiberias', 'טבריה', 32.7959, 35.5310, 'Asia/Jerusalem', israel: true),
  ZmanimCity('safed', 'Safed', 'צפת', 32.9646, 35.4960, 'Asia/Jerusalem', israel: true),
  ZmanimCity('eilat', 'Eilat', 'אילת', 29.5577, 34.9519, 'Asia/Jerusalem', israel: true),
  ZmanimCity('new-york', 'New York', 'ניו יורק', 40.7128, -74.0060, 'America/New_York'),
  ZmanimCity('miami', 'Miami', 'מיאמי', 25.7617, -80.1918, 'America/New_York'),
  ZmanimCity('chicago', 'Chicago', 'שיקגו', 41.8781, -87.6298, 'America/Chicago'),
  ZmanimCity('los-angeles', 'Los Angeles', 'לוס אנג׳לס', 34.0522, -118.2437, 'America/Los_Angeles'),
  ZmanimCity('toronto', 'Toronto', 'טורונטו', 43.6532, -79.3832, 'America/Toronto'),
  ZmanimCity('mexico-city', 'Mexico City', 'מקסיקו סיטי', 19.4326, -99.1332, 'America/Mexico_City'),
  ZmanimCity('sao-paulo', 'São Paulo', 'סאו פאולו', -23.5505, -46.6333, 'America/Sao_Paulo'),
  ZmanimCity('buenos-aires', 'Buenos Aires', 'בואנוס איירס', -34.6037, -58.3816, 'America/Argentina/Buenos_Aires'),
  ZmanimCity('london', 'London', 'לונדון', 51.5074, -0.1278, 'Europe/London'),
  ZmanimCity('paris', 'Paris', 'פריז', 48.8566, 2.3522, 'Europe/Paris'),
  ZmanimCity('antwerp', 'Antwerp', 'אנטוורפן', 51.2194, 4.4025, 'Europe/Brussels'),
  ZmanimCity('berlin', 'Berlin', 'ברלין', 52.5200, 13.4050, 'Europe/Berlin'),
  ZmanimCity('moscow', 'Moscow', 'מוסקבה', 55.7558, 37.6173, 'Europe/Moscow'),
  ZmanimCity('kyiv', 'Kyiv', 'קייב', 50.4501, 30.5234, 'Europe/Kyiv'),
  ZmanimCity('johannesburg', 'Johannesburg', 'יוהנסבורג', -26.2041, 28.0473, 'Africa/Johannesburg'),
  ZmanimCity('melbourne', 'Melbourne', 'מלבורן', -37.8136, 144.9631, 'Australia/Melbourne'),
  ZmanimCity('sydney', 'Sydney', 'סידני', -33.8688, 151.2093, 'Australia/Sydney'),
];

ZmanimCity? zmanimCity(String? id) => zmanimCities.where((c) => c.id == id).firstOrNull;

/// The sun's zenith at sunset (refraction and the sun's radius).
const sunsetZenith = 90.833;

/// Nightfall (tzeit hakochavim): the sun 8.5° below the horizon.
const nightfallZenith = 98.5;

/// When the sun passes [zenith] in the evening of the civil [day] at
/// [city], as an absolute time; null where it never gets that low (far
/// north in summer). The "Almanac for Computers" method (as NOAA's
/// sunrise and sunset tables), within about a minute.
DateTime? sunDownAt(DateTime day, ZmanimCity city, {double zenith = sunsetZenith}) {
  double rad(double deg) => deg * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  double norm(double v, double max) => (v % max + max) % max;

  final n = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(day.year)).inDays + 1;
  final lngHour = city.longitude / 15;
  final t = n + (18 - lngHour) / 24;
  final m = 0.9856 * t - 3.289;
  final l = norm(m + 1.916 * math.sin(rad(m)) + 0.020 * math.sin(rad(2 * m)) + 282.634, 360);
  var ra = norm(deg(math.atan(0.91764 * math.tan(rad(l)))), 360);
  ra = (ra + (l / 90).floor() * 90 - (ra / 90).floor() * 90) / 15;
  final sinDec = 0.39782 * math.sin(rad(l));
  final cosDec = math.cos(math.asin(sinDec));
  final cosH = (math.cos(rad(zenith)) - sinDec * math.sin(rad(city.latitude))) /
      (cosDec * math.cos(rad(city.latitude)));
  if (cosH < -1 || cosH > 1) return null;
  final h = deg(math.acos(cosH)) / 15;
  final localMean = h + ra - 0.06571 * t - 6.622;
  final ut = norm(localMean - lngHour, 24);
  var at = DateTime.utc(day.year, day.month, day.day).add(Duration(seconds: (ut * 3600).round()));
  // The UTC hour can land on the day before or after: keep the evening
  // that belongs to [day] in the city's own time.
  final location = zoneFor(city.timeZone);
  if (location == null) return at;
  final local = tz.TZDateTime.from(at, location);
  final wanted = DateTime(day.year, day.month, day.day);
  final got = DateTime(local.year, local.month, local.day);
  if (got.isBefore(wanted)) at = at.add(const Duration(days: 1));
  if (got.isAfter(wanted)) at = at.subtract(const Duration(days: 1));
  return at;
}

enum ZmanKind {
  /// Candles before sunset, before Shabbat or a Yom Tov.
  candles,

  /// Candles after nightfall, on the evening between two holy days.
  candlesAfter,

  /// Havdalah at nightfall, as a holy day ends.
  havdalah,
}

class Zman {
  const Zman(this.kind, this.at);
  final ZmanKind kind;
  final DateTime at;
}

/// Candle lighting and Havdalah for the evenings of the civil days from
/// [from] up to (not including) [to], at [city].
List<Zman> shabbatTimes(DateTime from, DateTime to, ZmanimCity city) {
  final out = <Zman>[];
  for (var day = DateTime(from.year, from.month, from.day);
      day.isBefore(to);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final next = DateTime(day.year, day.month, day.day + 1);
    final holyToday = isHolyDay(day, israel: city.israel);
    final holyTomorrow = isHolyDay(next, israel: city.israel);
    // Candles before sunset when a holy day starts this evening, also when
    // a Yom Tov on Friday runs into Shabbat (no lighting once Shabbat has
    // begun).
    final intoShabbat = holyToday && holyTomorrow && next.weekday == DateTime.saturday;
    if ((!holyToday && holyTomorrow) || intoShabbat) {
      final sunset = sunDownAt(day, city);
      if (sunset != null) {
        out.add(Zman(ZmanKind.candles, sunset.subtract(Duration(minutes: city.candleMinutes))));
      }
    } else if (holyToday) {
      final night = sunDownAt(day, city, zenith: nightfallZenith) ??
          sunDownAt(day, city)?.add(const Duration(minutes: 50));
      if (night == null) continue;
      out.add(Zman(holyTomorrow ? ZmanKind.candlesAfter : ZmanKind.havdalah, night));
    }
  }
  return out;
}
