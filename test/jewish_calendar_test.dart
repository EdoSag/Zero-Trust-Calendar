import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/jewish/hebrew_date.dart';
import 'package:zerotrust_calendar/jewish/jewish_entries.dart';
import 'package:zerotrust_calendar/jewish/jewish_holidays.dart';
import 'package:zerotrust_calendar/jewish/zmanim.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/ui/home_page.dart';
import 'package:zerotrust_calendar/ui/jewish_calendar_page.dart';
import 'package:zerotrust_calendar/util/time_zones.dart';

import 'home_page_test.dart' show app, usePhoneScreen;
import 'year_view_test.dart' show prefsWith;

void main() {
  setUpAll(() => initializeDateFormatting());

  group('Hebrew dates', () {
    test('match known dates both ways', () {
      final known = {
        DateTime(2026, 4, 2): const HebrewDate(5786, HebrewDate.nisan, 15), // Pesach
        DateTime(2026, 9, 12): const HebrewDate(5787, HebrewDate.tishrei, 1), // Rosh Hashana
        DateTime(2025, 12, 15): const HebrewDate(5786, HebrewDate.kislev, 25), // Hanukkah
        DateTime(2024, 3, 24): const HebrewDate(5784, HebrewDate.adar2, 14), // Purim, leap year
        DateTime(2023, 9, 16): const HebrewDate(5784, HebrewDate.tishrei, 1),
        DateTime(2000, 1, 1): const HebrewDate(5760, HebrewDate.tevet, 23),
      };
      for (final MapEntry(key: day, value: hebrew) in known.entries) {
        expect(HebrewDate.of(day), hebrew, reason: '$day');
        expect(hebrew.toDateTime(), day, reason: '$hebrew');
      }
    });

    test('every day of 40 years round-trips and counts up', () {
      var day = DateTime(2000);
      var last = HebrewDate.of(day);
      while (day.year < 2040) {
        day = DateTime(day.year, day.month, day.day + 1);
        final h = HebrewDate.of(day);
        expect(h.toDateTime(), day);
        expect(h.day == 1 || h.day == last.day + 1, isTrue, reason: '$day');
        last = h;
      }
    });

    test('are written in Hebrew letters', () {
      expect(gematria(1), 'א׳');
      expect(gematria(15), 'ט״ו');
      expect(gematria(16), 'ט״ז');
      expect(gematria(30), 'ל׳');
      expect(gematria(5787), 'תשפ״ז');
      expect(formatHebrewDate(const HebrewDate(5787, HebrewDate.kislev, 3), hebrew: true), 'ג׳ כסלו תשפ״ז');
      expect(formatHebrewDate(const HebrewDate(5787, HebrewDate.kislev, 3), hebrew: false), '3 Kislev 5787');
      expect(hebrewMonthName(HebrewDate.adar, 5784, hebrew: false), 'Adar I');
      expect(hebrewMonthName(HebrewDate.adar, 5786, hebrew: true), 'אדר');
    });
  });

  group('holidays', () {
    DateTime? dayOf(JewishHoliday h, int year, {bool israel = true}) =>
        holidaysOfHebrewYear(year, israel: israel).where((x) => x.holiday == h).firstOrNull?.day;

    test('fall on the right days', () {
      expect(dayOf(JewishHoliday.roshHashana1, 5787), DateTime(2026, 9, 12));
      expect(dayOf(JewishHoliday.yomKippur, 5787), DateTime(2026, 9, 21));
      expect(dayOf(JewishHoliday.pesach1, 5786), DateTime(2026, 4, 2));
      expect(dayOf(JewishHoliday.purim, 5784), DateTime(2024, 3, 24));
      expect(dayOf(JewishHoliday.shavuot1, 5787), DateTime(2027, 6, 11));
    });

    test('fasts and memorial days move as the rules say', () {
      // 13 Adar II 5784 was Shabbat: the fast was on Thursday.
      expect(dayOf(JewishHoliday.taanitEsther, 5784), DateTime(2024, 3, 21));
      // 9 Av 5785 was Shabbat: kept on Sunday.
      expect(dayOf(JewishHoliday.tishaBeAv, 5785), DateTime(2025, 8, 3));
      // 5 Iyar 5785 was Friday: Yom Ha'Atzmaut on Thursday, Yom HaZikaron Wednesday.
      expect(dayOf(JewishHoliday.yomHaAtzmaut, 5785), DateTime(2025, 5, 1));
      expect(dayOf(JewishHoliday.yomHaZikaron, 5785), DateTime(2025, 4, 30));
    });

    test('Hanukkah has eight nights', () {
      final nights = holidaysOfHebrewYear(5787, israel: true)
          .where((h) => h.holiday == JewishHoliday.hanukkah)
          .toList();
      expect(nights.map((h) => h.night), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(nights.first.day, DateTime(2026, 12, 5));
    });

    test('outside Israel the festivals have a second day', () {
      final israel = holidaysOfHebrewYear(5787, israel: true).map((h) => h.holiday).toSet();
      final abroad = holidaysOfHebrewYear(5787, israel: false).map((h) => h.holiday).toSet();
      expect(israel.contains(JewishHoliday.pesach8), isFalse);
      expect(abroad.contains(JewishHoliday.pesach8), isTrue);
      expect(abroad.contains(JewishHoliday.shavuot2), isTrue);
      expect(abroad.contains(JewishHoliday.sheminiAtzeret), isTrue);
    });
  });

  group('Shabbat times', () {
    setUpAll(() => zoneFor('UTC'));
    String local(DateTime t, String zone) {
      final wall = wallClockIn(zoneFor(zone)!, t);
      return '${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
    }

    test('Jerusalem lights 40 minutes before sunset, Havdalah at nightfall', () {
      final times = shabbatTimes(DateTime(2026, 11, 26), DateTime(2026, 11, 29), zmanimCity('jerusalem')!);
      expect(times.map((z) => z.kind), [ZmanKind.candles, ZmanKind.havdalah]);
      // Published calendars: about 15:56 and 17:15.
      expect(local(times[0].at, 'Asia/Jerusalem'), anyOf('15:55', '15:56', '15:57'));
      expect(local(times[1].at, 'Asia/Jerusalem'), anyOf('17:13', '17:14', '17:15', '17:16'));
    });

    test('Los Angeles: the evening stays on its own day', () {
      final times = shabbatTimes(DateTime(2026, 11, 27), DateTime(2026, 11, 29), zmanimCity('los-angeles')!);
      expect(times, hasLength(2));
      expect(local(times[0].at, 'America/Los_Angeles'), startsWith('16:'));
    });

    test('Rosh Hashana after Shabbat abroad: candles, candles after nightfall, Havdalah', () {
      final times = shabbatTimes(DateTime(2026, 9, 10), DateTime(2026, 9, 14), zmanimCity('new-york')!);
      expect(times.map((z) => z.kind), [ZmanKind.candles, ZmanKind.candlesAfter, ZmanKind.havdalah]);
    });

    test('entries carry the city and sort into the calendar', () {
      final entries = jewishEntries(
        range: DateRange(DateTime(2026, 12, 4), DateTime(2026, 12, 6)),
        holidays: true,
        city: zmanimCity('tel-aviv'),
        israel: true,
        l10n: lookupAppL10n(const Locale('en')),
      );
      expect(entries.map((e) => e.title), containsAll(['Candle lighting', 'Hanukkah: 1 candle']));
      final candles = entries.firstWhere((e) => e.title == 'Candle lighting');
      expect(candles.kind, EntryKind.jewish);
      expect(candles.allDay, isFalse);
      expect(candles.jewish!.city!.id, 'tel-aviv');
    });

    test('Hebrew names', () {
      final entries = jewishEntries(
        range: DateRange(DateTime(2026, 12, 5), DateTime(2026, 12, 6)),
        holidays: true,
        city: null,
        israel: true,
        l10n: lookupAppL10n(const Locale('he')),
      );
      expect(entries.single.title, 'חנוכה: נר א׳');
    });
  });

  test('settings keep the Jewish calendar choices', () {
    const s = CalendarSettings(hebrewDates: true, jewishHolidays: true, shabbatCity: 'haifa');
    final back = CalendarSettings.fromPrefs(s.toPrefs());
    expect(back.hebrewDates, isTrue);
    expect(back.jewishHolidays, isTrue);
    expect(back.shabbatCity, 'haifa');
    expect(CalendarSettings.fromPrefs(const CalendarSettings().toPrefs()).shabbatCity, isNull);
  });

  testWidgets('the month view shows Hebrew days and holidays when on', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'month', 'hebrewDates': 'true', 'jewishHolidays': 'true'});
    await tester.pumpWidget(app(const HomePage(), const [], prefs: prefs));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final today = DateTime.now();
    final h = HebrewDate.of(today);
    final label = h.day == 1
        ? '${h.day} ${hebrewMonthName(h.month, h.year, hebrew: false)}'
        : '${h.day}';
    // Today's Hebrew day sits right of today's number, in the same row.
    final number = find.text('${today.day}');
    final hebrew = find.text(label);
    expect(hebrew, findsWidgets);
    expect(number, findsWidgets);
  });

  testWidgets('the Jewish calendar page turns things on and picks a city', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(app(const JewishCalendarPage(), const []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hebrew dates'));
    await tester.tap(find.text('Jewish holidays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shabbat and holiday times'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haifa'));
    await tester.pumpAndSettle();
    expect(find.text('Haifa'), findsOneWidget); // Now the row's subtitle.
    expect(find.textContaining('candles 30 minutes before sunset'), findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.every((s) => s.value), isTrue);
  });
}
