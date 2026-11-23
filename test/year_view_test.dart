import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/ui/home_page.dart';
import 'package:zerotrust_calendar/ui/mini_month.dart';
import 'package:zerotrust_calendar/ui/month_view.dart';
import 'package:zerotrust_calendar/ui/timeline_view.dart';
import 'package:zerotrust_calendar/ui/year_view.dart';
import 'package:zerotrust_calendar/util/format.dart';

import 'home_page_test.dart' show app, usePhoneScreen;

/// Preferences with Calendar's own settings already saved.
Future<InMemoryPreferencesStore> prefsWith(Map<String, String> values) async {
  final prefs = InMemoryPreferencesStore();
  for (final e in values.entries) {
    await prefs.write('calendar_${e.key}', e.value);
  }
  return prefs;
}

void useTabletScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(2560, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  group('week numbers', () {
    test('follow ISO 8601', () {
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1); // Thursday
      expect(isoWeekNumber(DateTime(2026, 12, 31)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 3)), 53); // Sunday
      expect(isoWeekNumber(DateTime(2027, 1, 4)), 1);
      expect(isoWeekNumber(DateTime(2026, 11, 22)), 47);
    });

    test('a row starting on Sunday or Saturday takes the week it mostly covers', () {
      // Sunday 22 Nov 2026 to Saturday 28 Nov: ISO week 48 (Mon 23 to Sun 29).
      expect(weekNumberOfRow(DateTime(2026, 11, 22)), 48);
      expect(weekNumberOfRow(DateTime(2026, 11, 23)), 48); // Monday start
      expect(weekNumberOfRow(DateTime(2026, 11, 21)), 48); // Saturday start
    });
  });

  test('the weekend is Friday and Saturday in Hebrew or Israel', () {
    expect(weekendDaysFor('he', null), {DateTime.friday, DateTime.saturday});
    expect(weekendDaysFor('en', 'IL'), {DateTime.friday, DateTime.saturday});
    expect(weekendDaysFor('en', 'US'), {DateTime.saturday, DateTime.sunday});
  });

  test('settings keep the new view and switches', () {
    const s = CalendarSettings(
      view: CalendarView.year,
      showWeekNumbers: true,
      hideWeekends: true,
    );
    final back = CalendarSettings.fromPrefs(s.toPrefs());
    expect(back.view, CalendarView.year);
    expect(back.showWeekNumbers, isTrue);
    expect(back.hideWeekends, isTrue);
    // Saved by an older version: both off.
    final old = CalendarSettings.fromPrefs({'view': 'week'});
    expect(old.showWeekNumbers, isFalse);
    expect(old.hideWeekends, isFalse);
  });

  test('busy days cover every day an entry touches, inside the range', () {
    final range = DateRange(DateTime(2026, 1, 1), DateTime(2027, 1, 1));
    final entry = CalendarEntry(
      kind: EntryKind.event,
      title: 'Trip',
      start: DateTime(2025, 12, 30),
      end: DateTime(2026, 1, 3),
      allDay: true,
      color: 0,
    );
    final point = CalendarEntry(
      kind: EntryKind.event,
      title: 'Call',
      start: DateTime(2026, 5, 4, 10),
      end: DateTime(2026, 5, 4, 10),
      allDay: false,
      color: 0,
    );
    expect(busyDays([entry, point], range), {
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 2),
      DateTime(2026, 5, 4),
    });
  });

  final now = DateTime.now();
  final events = [
    CalendarEvent(
      id: 'dentist',
      title: 'Dentist',
      start: DateTime(now.year, now.month, now.day, 9),
      end: DateTime(now.year, now.month, now.day, 10),
    ),
  ];

  testWidgets('the year view lays out twelve months, three across on a phone', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'year'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(YearView), findsOneWidget);
    expect(find.text('${now.year}'), findsOneWidget); // The title.
    expect(find.byType(MiniMonth), findsNWidgets(12));

    final jan = tester.getTopLeft(find.text('January'));
    final feb = tester.getTopLeft(find.text('February'));
    final mar = tester.getTopLeft(find.text('March'));
    final apr = tester.getTopLeft(find.text('April'));
    expect(feb.dx, greaterThan(jan.dx));
    expect(mar.dx, greaterThan(feb.dx));
    expect(feb.dy, moreOrLessEquals(jan.dy));
    expect(apr.dx, moreOrLessEquals(jan.dx));
    expect(apr.dy, greaterThan(jan.dy));

    // A month's name opens it in the month view.
    await tester.tap(find.text('February'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthView), findsOneWidget);
    expect(find.text('February'), findsOneWidget); // The title.
  });

  testWidgets('a day in the year view opens it', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'year'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs));
    await tester.pumpAndSettle();
    final today = DateTime(now.year, now.month, now.day);
    final cell = find.bySemanticsLabel(formatLongDay(today));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsOneWidget);
    expect(find.text('Dentist'), findsWidgets);
  });

  testWidgets('hide weekends leaves the weekend out of the month and week views', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'month', 'hideWeekends': 'true'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs));
    await tester.pumpAndSettle();
    String name(int weekday) => DateFormat.E().format(DateTime(2024, 1, weekday));
    // English: Saturday and Sunday go, the weekdays stay in order.
    expect(find.text(name(DateTime.saturday)), findsNothing);
    expect(find.text(name(DateTime.sunday)), findsNothing);
    final mon = tester.getCenter(find.text(name(DateTime.monday)));
    final fri = tester.getCenter(find.text(name(DateTime.friday)));
    expect(fri.dx, greaterThan(mon.dx));

    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (w) => w is CheckedPopupMenuItem<CalendarView> && w.value == CalendarView.week,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsOneWidget);
    expect(find.text(name(DateTime.saturday)), findsNothing);
    expect(find.text(name(DateTime.sunday)), findsNothing);
    expect(find.text(name(DateTime.wednesday)), findsOneWidget);
  });

  testWidgets('Hebrew hides Friday and Saturday', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'month', 'hideWeekends': 'true'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs, locale: const Locale('he')));
    await tester.pumpAndSettle();
    String name(int weekday) => DateFormat.E('he').format(DateTime(2024, 1, weekday));
    expect(find.text(name(DateTime.friday)), findsNothing);
    expect(find.text(name(DateTime.saturday)), findsNothing);
    expect(find.text(name(DateTime.sunday)), findsOneWidget);
  });

  testWidgets('English on a phone set to Israel hides Friday and Saturday', (tester) async {
    usePhoneScreen(tester);
    tester.platformDispatcher.localeTestValue = const Locale('en', 'IL');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final prefs = await prefsWith({'view': 'month', 'hideWeekends': 'true'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs));
    await tester.pumpAndSettle();
    String name(int weekday) => DateFormat.E().format(DateTime(2024, 1, weekday));
    expect(find.text(name(DateTime.friday)), findsNothing);
    expect(find.text(name(DateTime.saturday)), findsNothing);
    expect(find.text(name(DateTime.sunday)), findsOneWidget);
  });

  testWidgets('week numbers sit at the start of each month row', (tester) async {
    usePhoneScreen(tester);
    final prefs = await prefsWith({'view': 'month', 'showWeekNumbers': 'true'});
    await tester.pumpWidget(app(const HomePage(), events, prefs: prefs));
    await tester.pumpAndSettle();
    final labels = find.byType(WeekNumberLabel);
    expect(labels, findsAtLeastNWidgets(4));
    // Left of the first day column.
    final firstLabel = tester.getRect(labels.first);
    final firstDay = tester.getRect(find.text('1').first);
    expect(firstLabel.right, lessThanOrEqualTo(firstDay.left + 1));
  });

  testWidgets('a tablet keeps the calendars and a small month beside the view', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(app(const HomePage(), events));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // No drawer button: the panel is always open.
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byType(MiniMonth), findsOneWidget);
    final panel = tester.getRect(find.byType(MiniMonth));
    final month = tester.getRect(find.byType(MonthView));
    expect(panel.right, lessThanOrEqualTo(month.left));
    // The views list is in the panel too.
    expect(find.text('Year'), findsOneWidget);
    // The panel's arrows move the calendar a month on.
    final next = DateTime(now.year, now.month + 1);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(formatMonthYear(next)), findsOneWidget);
  });

  testWidgets('a phone keeps the drawer', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(app(const HomePage(), events));
    await tester.pumpAndSettle();
    expect(find.byType(MiniMonth), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Year'), findsOneWidget);
  });
}
