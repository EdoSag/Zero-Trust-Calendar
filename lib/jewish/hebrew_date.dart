
/// A date in the Hebrew (Jewish) calendar, computed on the phone (K-1).
///
/// Arithmetic from Reingold and Dershowitz, "Calendrical Calculations":
/// months are numbered from Nisan (1) to Adar (12), with Adar II (13) in
/// leap years; the year starts on 1 Tishrei (7).
class HebrewDate {
  const HebrewDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const nisan = 1;
  static const iyyar = 2;
  static const sivan = 3;
  static const tammuz = 4;
  static const av = 5;
  static const elul = 6;
  static const tishrei = 7;
  static const cheshvan = 8;
  static const kislev = 9;
  static const tevet = 10;
  static const shevat = 11;
  static const adar = 12;
  static const adar2 = 13;

  /// Fixed day number (R.D.) of 1 Tishrei, year 1.
  static const _epoch = -1373427;

  static bool isLeapYear(int year) => (7 * year + 1) % 19 < 7;

  static int lastMonthOfYear(int year) => isLeapYear(year) ? adar2 : adar;

  static int _elapsedDays(int year) {
    final months = (235 * year - 234) ~/ 19;
    final parts = 12084 + 13753 * months;
    final days = 29 * months + parts ~/ 25920;
    return (3 * (days + 1)) % 7 < 3 ? days + 1 : days;
  }

  static int _yearLengthCorrection(int year) {
    final ny0 = _elapsedDays(year - 1);
    final ny1 = _elapsedDays(year);
    final ny2 = _elapsedDays(year + 1);
    if (ny2 - ny1 == 356) return 2;
    if (ny1 - ny0 == 382) return 1;
    return 0;
  }

  static final _newYears = <int, int>{};

  /// Fixed day of 1 Tishrei of [year].
  static int newYear(int year) =>
      _newYears[year] ??= _epoch + _elapsedDays(year) + _yearLengthCorrection(year);

  static int daysInYear(int year) => newYear(year + 1) - newYear(year);

  static bool _longCheshvan(int year) => daysInYear(year) % 10 == 5;
  static bool _shortKislev(int year) => daysInYear(year) % 10 == 3;

  static int daysInMonth(int month, int year) {
    if (month == iyyar || month == tammuz || month == elul || month == tevet || month == adar2) {
      return 29;
    }
    if (month == adar && !isLeapYear(year)) return 29;
    if (month == cheshvan && !_longCheshvan(year)) return 29;
    if (month == kislev && _shortKislev(year)) return 29;
    return 30;
  }

  /// Fixed day number of this date.
  int get fixed {
    var days = newYear(year) + day - 1;
    if (month < tishrei) {
      for (var m = tishrei; m <= lastMonthOfYear(year); m++) {
        days += daysInMonth(m, year);
      }
      for (var m = nisan; m < month; m++) {
        days += daysInMonth(m, year);
      }
    } else {
      for (var m = tishrei; m < month; m++) {
        days += daysInMonth(m, year);
      }
    }
    return days;
  }

  static HebrewDate fromFixed(int date) {
    final approx = ((date - _epoch) * 98496 / 35975351).floor() + 1;
    var year = approx - 1;
    while (newYear(year + 1) <= date) {
      year++;
    }
    final start = date < HebrewDate(year, nisan, 1).fixed ? tishrei : nisan;
    var month = start;
    while (date > HebrewDate(year, month, daysInMonth(month, year)).fixed) {
      month++;
    }
    final day = date - HebrewDate(year, month, 1).fixed + 1;
    return HebrewDate(year, month, day);
  }

  /// The Hebrew date of the civil day [d] (its daytime: the Hebrew day
  /// that began the evening before).
  factory HebrewDate.of(DateTime d) => fromFixed(fixedOf(d));

  /// The civil day of this date.
  DateTime toDateTime() => dateOfFixed(fixed);

  @override
  bool operator ==(Object other) =>
      other is HebrewDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$day/$month/$year';
}

/// Fixed day number (R.D. 1 = 1 January of year 1) of the civil day [d].
int fixedOf(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1)).inDays + 1;

DateTime dateOfFixed(int fixed) {
  final utc = DateTime.utc(1).add(Duration(days: fixed - 1));
  return DateTime(utc.year, utc.month, utc.day);
}

/// Hebrew month names, English and Hebrew; Adar is "Adar I" in a leap year.
String hebrewMonthName(int month, int year, {required bool hebrew}) {
  final leap = HebrewDate.isLeapYear(year);
  if (hebrew) {
    return switch (month) {
      HebrewDate.nisan => 'ניסן',
      HebrewDate.iyyar => 'אייר',
      HebrewDate.sivan => 'סיוון',
      HebrewDate.tammuz => 'תמוז',
      HebrewDate.av => 'אב',
      HebrewDate.elul => 'אלול',
      HebrewDate.tishrei => 'תשרי',
      HebrewDate.cheshvan => 'חשוון',
      HebrewDate.kislev => 'כסלו',
      HebrewDate.tevet => 'טבת',
      HebrewDate.shevat => 'שבט',
      HebrewDate.adar => leap ? 'אדר א׳' : 'אדר',
      _ => 'אדר ב׳',
    };
  }
  return switch (month) {
    HebrewDate.nisan => 'Nisan',
    HebrewDate.iyyar => 'Iyyar',
    HebrewDate.sivan => 'Sivan',
    HebrewDate.tammuz => 'Tammuz',
    HebrewDate.av => 'Av',
    HebrewDate.elul => 'Elul',
    HebrewDate.tishrei => 'Tishrei',
    HebrewDate.cheshvan => 'Cheshvan',
    HebrewDate.kislev => 'Kislev',
    HebrewDate.tevet => 'Tevet',
    HebrewDate.shevat => 'Shevat',
    HebrewDate.adar => leap ? 'Adar I' : 'Adar',
    _ => 'Adar II',
  };
}

/// A number in Hebrew letters, with geresh or gershayim: 3 → ג׳, 15 → ט״ו,
/// 787 → תשפ״ז. Thousands are left out, as years are usually written.
String gematria(int n) {
  n %= 1000;
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת', 'תק', 'תר', 'תש', 'תת', 'תתק'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  var letters = hundreds[n ~/ 100];
  final rest = n % 100;
  // 15 and 16 are written 9+6 and 9+7, never as names of God.
  if (rest == 15) {
    letters += 'טו';
  } else if (rest == 16) {
    letters += 'טז';
  } else {
    letters += tens[rest ~/ 10] + ones[rest % 10];
  }
  if (letters.isEmpty) return '';
  if (letters.length == 1) return '$letters׳';
  return '${letters.substring(0, letters.length - 1)}״${letters.substring(letters.length - 1)}';
}

/// "3 Kislev 5787", or "ג׳ כסלו תשפ״ז" in Hebrew. [withYear] false: "3 Kislev".
String formatHebrewDate(HebrewDate h, {required bool hebrew, bool withYear = true}) {
  final month = hebrewMonthName(h.month, h.year, hebrew: hebrew);
  if (hebrew) {
    return withYear ? '${gematria(h.day)} $month ${gematria(h.year)}' : '${gematria(h.day)} $month';
  }
  return withYear ? '${h.day} $month ${h.year}' : '${h.day} $month';
}

/// The day alone, for a small calendar cell: "3", or "ג׳" in Hebrew.
String formatHebrewDay(HebrewDate h, {required bool hebrew}) => hebrew ? gematria(h.day) : '${h.day}';
