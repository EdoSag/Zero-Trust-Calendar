import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/model/recurrence.dart';
import 'package:zerotrust_calendar/util/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  void useHebrew() {
    ZtL10n.current = lookupZtLocalizations(const Locale('he'));
    Intl.defaultLocale = 'he';
  }

  tearDown(() {
    ZtL10n.current = lookupZtLocalizations(const Locale('en'));
    Intl.defaultLocale = 'en';
  });

  test('every English string has a Hebrew translation with the same '
      'placeholders', () {
    Map<String, dynamic> read(String lang) =>
        jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = read('en');
    final he = read('he');
    // A placeholder's brace follows a non-word character; a plural case's
    // brace follows its name (`=1{...}`).
    final placeholder = RegExp(r'(?<!\w)\{(\w+)[,}]');
    Set<String?> names(String text) =>
        placeholder.allMatches(text).map((m) => m[1]).toSet();
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      expect(he[key], isA<String>(), reason: 'app_he.arb is missing "$key"');
      expect(names(he[key] as String), names(en[key] as String),
          reason: 'placeholders differ in "$key"');
    }
  });

  test('repeat rules and reminders read in Hebrew', () {
    final monday = DateTime(2026, 11, 2, 9);
    useHebrew();
    expect(describeRule(null, monday), 'לא חוזר');
    expect(describeRule(const RecurrenceRule(frequency: Frequency.daily), monday), 'כל יום');
    expect(
        describeRule(const RecurrenceRule(frequency: Frequency.weekly, interval: 2), monday),
        'כל שבועיים ביום שני');
    expect(describeRule(const RecurrenceRule(frequency: Frequency.monthly, count: 5), monday),
        'כל חודש ב-2 בחודש, 5 פעמים');
    expect(
        describeRule(
            const RecurrenceRule(frequency: Frequency.monthly, byDay: [WeekdayNum(1, -1)]),
            monday),
        'כל חודש ביום שני האחרון');
    expect(reminderLabel(10), '10 דקות לפני');
    expect(reminderLabel(60), 'שעה לפני');
    expect(reminderLabel(2 * 24 * 60), 'יומיים לפני');
    expect(reminderLabel(0, allDay: true), 'ביום עצמו ב-9:00');
    expect(relativeDay(monday, now: monday), 'היום');
    expect(holidayRegionName('United States'), isNot('United States'));
    expect(holidayRegionName('Atlantis'), 'Atlantis');
  });

  test('English stays the default', () {
    final monday = DateTime(2026, 11, 2, 9);
    expect(describeRule(const RecurrenceRule(frequency: Frequency.weekly, interval: 2), monday),
        'Every 2 weeks on Monday');
    expect(reminderLabel(60), '1 hour before');
  });

  test('birthdays follow the language picked, before the app rebuilds', () {
    final ada = LinkedContact.fromItem('c', {
      'kind': 'contact',
      'displayName': 'Ada',
      'birthdays': ['1990-11-20'],
    })!;
    List<String> titles(Locale picked) => buildEntries(
          range: DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1)),
          events: const [],
          calendars: const [ZtCalendarInfo.personal],
          contacts: [ada],
          l10n: appL10nFor(picked),
        ).map((e) => e.title).toList();
    expect(titles(const Locale('en')), ["Ada's birthday"]);
    expect(titles(const Locale('he')).single, isNot("Ada's birthday"));
    expect(titles(const Locale('he')).single, contains('Ada'));
  });
}
