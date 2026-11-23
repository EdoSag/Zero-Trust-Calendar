import 'hebrew_date.dart';

/// The Jewish holidays and fasts shown on the calendar (K-1).
enum JewishHoliday {
  erevRoshHashana,
  roshHashana1,
  roshHashana2,
  tzomGedaliah,
  erevYomKippur,
  yomKippur,
  erevSukkot,
  sukkot1,
  sukkot2,
  cholHamoedSukkot,
  hoshanaRaba,
  sheminiAtzeret,
  simchatTorah,
  hanukkah,
  asaraBeTevet,
  tuBiShvat,
  taanitEsther,
  purim,
  shushanPurim,
  erevPesach,
  pesach1,
  pesach2,
  cholHamoedPesach,
  pesach7,
  pesach8,
  yomHaShoah,
  yomHaZikaron,
  yomHaAtzmaut,
  lagBaOmer,
  yomYerushalayim,
  erevShavuot,
  shavuot1,
  shavuot2,
  shivaAsarBeTammuz,
  tishaBeAv,
  tuBeAv;

  /// A day of rest (Yom Tov): no work, candles the evening before.
  bool get yomTov => const {
    roshHashana1,
    roshHashana2,
    yomKippur,
    sukkot1,
    sukkot2,
    sheminiAtzeret,
    simchatTorah,
    pesach1,
    pesach2,
    pesach7,
    pesach8,
    shavuot1,
    shavuot2,
  }.contains(this);

  bool get fast => const {
    tzomGedaliah,
    yomKippur,
    asaraBeTevet,
    taanitEsther,
    shivaAsarBeTammuz,
    tishaBeAv,
  }.contains(this);
}

/// One holiday on one civil day. [night] counts Hanukkah's candles (1 to 8).
class JewishHolidayDay {
  const JewishHolidayDay(this.day, this.holiday, {this.night});
  final DateTime day;
  final JewishHoliday holiday;
  final int? night;
}

/// The holidays of the Hebrew [year] (Tishrei to Elul), as kept in Israel
/// or, with [israel] false, outside it (second days of the festivals,
/// Simchat Torah on its own day).
List<JewishHolidayDay> holidaysOfHebrewYear(int year, {required bool israel}) {
  final out = <JewishHolidayDay>[];
  DateTime d(int month, int day) => HebrewDate(year, month, day).toDateTime();
  void add(int month, int day, JewishHoliday h) => out.add(JewishHolidayDay(d(month, day), h));
  // DateTime.weekday: Saturday 6, Friday 5, Sunday 7, Monday 1.
  int weekday(int month, int day) => d(month, day).weekday;

  // Tishrei.
  out.add(JewishHolidayDay(HebrewDate(year - 1, HebrewDate.elul, 29).toDateTime(), JewishHoliday.erevRoshHashana));
  add(HebrewDate.tishrei, 1, JewishHoliday.roshHashana1);
  add(HebrewDate.tishrei, 2, JewishHoliday.roshHashana2);
  add(HebrewDate.tishrei, weekday(HebrewDate.tishrei, 3) == DateTime.saturday ? 4 : 3, JewishHoliday.tzomGedaliah);
  add(HebrewDate.tishrei, 9, JewishHoliday.erevYomKippur);
  add(HebrewDate.tishrei, 10, JewishHoliday.yomKippur);
  add(HebrewDate.tishrei, 14, JewishHoliday.erevSukkot);
  add(HebrewDate.tishrei, 15, JewishHoliday.sukkot1);
  if (!israel) add(HebrewDate.tishrei, 16, JewishHoliday.sukkot2);
  for (var day = israel ? 16 : 17; day <= 20; day++) {
    add(HebrewDate.tishrei, day, JewishHoliday.cholHamoedSukkot);
  }
  add(HebrewDate.tishrei, 21, JewishHoliday.hoshanaRaba);
  if (israel) {
    // Shemini Atzeret and Simchat Torah are the same day in Israel.
    add(HebrewDate.tishrei, 22, JewishHoliday.simchatTorah);
  } else {
    add(HebrewDate.tishrei, 22, JewishHoliday.sheminiAtzeret);
    add(HebrewDate.tishrei, 23, JewishHoliday.simchatTorah);
  }

  // Hanukkah: eight days from 25 Kislev, into Tevet.
  final firstCandle = HebrewDate(year, HebrewDate.kislev, 25).fixed;
  for (var i = 0; i < 8; i++) {
    out.add(JewishHolidayDay(dateOfFixed(firstCandle + i), JewishHoliday.hanukkah, night: i + 1));
  }
  add(HebrewDate.tevet, 10, JewishHoliday.asaraBeTevet);
  add(HebrewDate.shevat, 15, JewishHoliday.tuBiShvat);

  // Purim is in Adar, or Adar II in a leap year.
  final adar = HebrewDate.isLeapYear(year) ? HebrewDate.adar2 : HebrewDate.adar;
  // The Fast of Esther moves to Thursday when 13 Adar is Shabbat.
  add(adar, weekday(adar, 13) == DateTime.saturday ? 11 : 13, JewishHoliday.taanitEsther);
  add(adar, 14, JewishHoliday.purim);
  add(adar, 15, JewishHoliday.shushanPurim);

  // Nisan.
  add(HebrewDate.nisan, 14, JewishHoliday.erevPesach);
  add(HebrewDate.nisan, 15, JewishHoliday.pesach1);
  if (!israel) add(HebrewDate.nisan, 16, JewishHoliday.pesach2);
  for (var day = israel ? 16 : 17; day <= 20; day++) {
    add(HebrewDate.nisan, day, JewishHoliday.cholHamoedPesach);
  }
  add(HebrewDate.nisan, 21, JewishHoliday.pesach7);
  if (!israel) add(HebrewDate.nisan, 22, JewishHoliday.pesach8);

  // Yom HaShoah: 27 Nisan, a day earlier from Friday, a day later from Sunday.
  final shoah = switch (weekday(HebrewDate.nisan, 27)) {
    DateTime.friday => 26,
    DateTime.sunday => 28,
    _ => 27,
  };
  add(HebrewDate.nisan, shoah, JewishHoliday.yomHaShoah);
  // Yom HaAtzmaut: 5 Iyar, moved back to Thursday from Friday or Shabbat,
  // and on to Tuesday from Monday (so Yom HaZikaron isn't on Sunday).
  final atzmaut = switch (weekday(HebrewDate.iyyar, 5)) {
    DateTime.friday => 4,
    DateTime.saturday => 3,
    DateTime.monday => 6,
    _ => 5,
  };
  add(HebrewDate.iyyar, atzmaut - 1, JewishHoliday.yomHaZikaron);
  add(HebrewDate.iyyar, atzmaut, JewishHoliday.yomHaAtzmaut);
  add(HebrewDate.iyyar, 18, JewishHoliday.lagBaOmer);
  add(HebrewDate.iyyar, 28, JewishHoliday.yomYerushalayim);

  add(HebrewDate.sivan, 5, JewishHoliday.erevShavuot);
  add(HebrewDate.sivan, 6, JewishHoliday.shavuot1);
  if (!israel) add(HebrewDate.sivan, 7, JewishHoliday.shavuot2);

  // Fasts that fall on Shabbat move to Sunday.
  add(HebrewDate.tammuz, weekday(HebrewDate.tammuz, 17) == DateTime.saturday ? 18 : 17,
      JewishHoliday.shivaAsarBeTammuz);
  add(HebrewDate.av, weekday(HebrewDate.av, 9) == DateTime.saturday ? 10 : 9, JewishHoliday.tishaBeAv);
  add(HebrewDate.av, 15, JewishHoliday.tuBeAv);
  return out;
}

/// The holidays on civil days from [from] up to (not including) [to].
List<JewishHolidayDay> jewishHolidaysBetween(DateTime from, DateTime to, {required bool israel}) {
  final first = HebrewDate.of(from).year;
  final last = HebrewDate.of(to).year;
  return [
    for (var y = first; y <= last + 1; y++)
      for (final h in holidaysOfHebrewYear(y, israel: israel))
        if (!h.day.isBefore(DateTime(from.year, from.month, from.day)) && h.day.isBefore(to)) h,
  ];
}

/// Shabbat or a Yom Tov: a day candles are lit for and Havdalah ends.
bool isHolyDay(DateTime day, {required bool israel}) {
  if (day.weekday == DateTime.saturday) return true;
  final h = HebrewDate.of(day);
  bool on(int month, int d) => h.month == month && h.day == d;
  return on(HebrewDate.tishrei, 1) ||
      on(HebrewDate.tishrei, 2) ||
      on(HebrewDate.tishrei, 10) ||
      on(HebrewDate.tishrei, 15) ||
      on(HebrewDate.tishrei, 22) ||
      on(HebrewDate.nisan, 15) ||
      on(HebrewDate.nisan, 21) ||
      on(HebrewDate.sivan, 6) ||
      (!israel &&
          (on(HebrewDate.tishrei, 16) ||
              on(HebrewDate.tishrei, 23) ||
              on(HebrewDate.nisan, 16) ||
              on(HebrewDate.nisan, 22) ||
              on(HebrewDate.sivan, 7)));
}
