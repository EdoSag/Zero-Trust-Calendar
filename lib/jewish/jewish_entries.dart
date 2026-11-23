import '../data/entries.dart';
import 'hebrew_date.dart';
import 'jewish_holidays.dart';
import 'zmanim.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// What a Jewish calendar entry is (K-1): a holiday, or a candle lighting
/// or Havdalah time at a city.
class JewishMark {
  const JewishMark({this.holiday, this.zman, this.city});
  final JewishHoliday? holiday;
  final ZmanKind? zman;
  final ZmanimCity? city;
}

const jewishHolidayColor = 0xFF3B82F6; // blue
const shabbatTimesColor = 0xFFF59E0B; // candle amber

/// The holiday's name in English or Hebrew.
String jewishHolidayName(JewishHoliday h, {required bool hebrew, int? night}) {
  final (en, he) = switch (h) {
    JewishHoliday.erevRoshHashana => ('Erev Rosh Hashana', 'ערב ראש השנה'),
    JewishHoliday.roshHashana1 => ('Rosh Hashana', 'ראש השנה'),
    JewishHoliday.roshHashana2 => ('Rosh Hashana, day 2', 'ראש השנה, יום ב׳'),
    JewishHoliday.tzomGedaliah => ('Fast of Gedaliah', 'צום גדליה'),
    JewishHoliday.erevYomKippur => ('Erev Yom Kippur', 'ערב יום כיפור'),
    JewishHoliday.yomKippur => ('Yom Kippur', 'יום כיפור'),
    JewishHoliday.erevSukkot => ('Erev Sukkot', 'ערב סוכות'),
    JewishHoliday.sukkot1 => ('Sukkot', 'סוכות'),
    JewishHoliday.sukkot2 => ('Sukkot, day 2', 'סוכות, יום ב׳'),
    JewishHoliday.cholHamoedSukkot => ("Sukkot (Chol HaMo'ed)", 'חול המועד סוכות'),
    JewishHoliday.hoshanaRaba => ('Hoshana Raba', 'הושענא רבה'),
    JewishHoliday.sheminiAtzeret => ('Shemini Atzeret', 'שמיני עצרת'),
    JewishHoliday.simchatTorah => ('Simchat Torah', 'שמחת תורה'),
    JewishHoliday.hanukkah => ('Hanukkah', 'חנוכה'),
    JewishHoliday.asaraBeTevet => ('Fast of 10 Tevet', 'עשרה בטבת'),
    JewishHoliday.tuBiShvat => ('Tu BiShvat', 'ט״ו בשבט'),
    JewishHoliday.taanitEsther => ('Fast of Esther', 'תענית אסתר'),
    JewishHoliday.purim => ('Purim', 'פורים'),
    JewishHoliday.shushanPurim => ('Shushan Purim', 'שושן פורים'),
    JewishHoliday.erevPesach => ('Erev Pesach', 'ערב פסח'),
    JewishHoliday.pesach1 => ('Pesach', 'פסח'),
    JewishHoliday.pesach2 => ('Pesach, day 2', 'פסח, יום ב׳'),
    JewishHoliday.cholHamoedPesach => ("Pesach (Chol HaMo'ed)", 'חול המועד פסח'),
    JewishHoliday.pesach7 => ('Pesach, day 7', 'שביעי של פסח'),
    JewishHoliday.pesach8 => ('Pesach, day 8', 'אחרון של פסח'),
    JewishHoliday.yomHaShoah => ('Yom HaShoah', 'יום השואה'),
    JewishHoliday.yomHaZikaron => ('Yom HaZikaron', 'יום הזיכרון'),
    JewishHoliday.yomHaAtzmaut => ("Yom Ha'Atzmaut", 'יום העצמאות'),
    JewishHoliday.lagBaOmer => ('Lag BaOmer', 'ל״ג בעומר'),
    JewishHoliday.yomYerushalayim => ('Yom Yerushalayim', 'יום ירושלים'),
    JewishHoliday.erevShavuot => ('Erev Shavuot', 'ערב שבועות'),
    JewishHoliday.shavuot1 => ('Shavuot', 'שבועות'),
    JewishHoliday.shavuot2 => ('Shavuot, day 2', 'שבועות, יום ב׳'),
    JewishHoliday.shivaAsarBeTammuz => ('Fast of 17 Tammuz', 'שבעה עשר בתמוז'),
    JewishHoliday.tishaBeAv => ("Tisha B'Av", 'תשעה באב'),
    JewishHoliday.tuBeAv => ("Tu B'Av", 'ט״ו באב'),
  };
  if (h == JewishHoliday.hanukkah && night != null) {
    return hebrew ? '$he: נר ${gematria(night)}' : '$en: ${night == 1 ? '1 candle' : '$night candles'}';
  }
  return hebrew ? he : en;
}

/// The Jewish calendar's entries in [range]: [holidays] when on, and
/// candle lighting and Havdalah at [city] when one is picked. [israel]
/// picks the holiday schedule when no city says.
List<CalendarEntry> jewishEntries({
  required DateRange range,
  required bool holidays,
  required ZmanimCity? city,
  required bool israel,
  required AppL10n l10n,
}) {
  final hebrew = l10n.localeName.startsWith('he');
  final out = <CalendarEntry>[];
  if (holidays) {
    for (final h in jewishHolidaysBetween(range.from, range.to, israel: city?.israel ?? israel)) {
      out.add(
        CalendarEntry(
          kind: EntryKind.jewish,
          title: jewishHolidayName(h.holiday, hebrew: hebrew, night: h.night),
          start: h.day,
          end: DateTime(h.day.year, h.day.month, h.day.day + 1),
          allDay: true,
          color: jewishHolidayColor,
          jewish: JewishMark(holiday: h.holiday),
        ),
      );
    }
  }
  if (city != null) {
    // The city's evenings can fall on another day on the phone when the
    // city keeps a different time zone, so take a day either side and keep
    // what lands in the range.
    final from = DateTime(range.from.year, range.from.month, range.from.day - 1);
    final to = DateTime(range.to.year, range.to.month, range.to.day + 1);
    for (final z in shabbatTimes(from, to, city)) {
      final at = z.at.toLocal();
      if (at.isBefore(range.from) || !at.isBefore(range.to)) continue;
      out.add(
        CalendarEntry(
          kind: EntryKind.jewish,
          title: switch (z.kind) {
            ZmanKind.candles => l10n.candleLighting,
            ZmanKind.candlesAfter => l10n.candleLightingAfter,
            ZmanKind.havdalah => l10n.havdalah,
          },
          start: at,
          // Drawn as a short block; lists show only the time.
          end: at.add(const Duration(minutes: 15)),
          allDay: false,
          color: shabbatTimesColor,
          jewish: JewishMark(zman: z.kind, city: city),
        ),
      );
    }
  }
  return out;
}
