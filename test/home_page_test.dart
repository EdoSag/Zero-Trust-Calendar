import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_config.dart';
import 'package:zerotrust_calendar/app/calendar_settings.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';
import 'package:zerotrust_calendar/ui/event_details_page.dart';
import 'package:zerotrust_calendar/ui/event_editor_page.dart';
import 'package:zerotrust_calendar/ui/home_page.dart';
import 'package:zerotrust_calendar/ui/month_view.dart';
import 'package:zerotrust_calendar/ui/quick_add_sheet.dart';
import 'package:zerotrust_calendar/ui/schedule_view.dart';
import 'package:zerotrust_calendar/ui/timeline_view.dart';

Widget app(Widget home, List<CalendarEvent> events, {PreferencesStore? prefs}) {
  return ProviderScope(
    overrides: [
      ztAppConfigProvider.overrideWithValue(calendarAppConfig),
      ztPreferencesStoreProvider.overrideWithValue(prefs ?? InMemoryPreferencesStore()),
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
      eventsProvider.overrideWith((ref) => Stream.value(events)),
      calendarsProvider.overrideWith(
        (ref) => Stream.value(const [ZtCalendarInfo.personal]),
      ),
      linkedNotesProvider.overrideWith((ref) => Stream.value(const <LinkedNote>[])),
      linkedTasksProvider.overrideWith((ref) => Stream.value(const <LinkedTask>[])),
      linkedContactsProvider.overrideWith((ref) => Stream.value(const <LinkedContact>[])),
      feedsProvider.overrideWith((ref) => Stream.value(const <CalendarFeed>[])),
    ],
    child: MaterialApp(
      // The real app theme: its full-width buttons vanish inside a Row, which
      // a plain ThemeData would hide from these tests.
      theme: ZtTheme.light(accent: ZtTheme.accentFor(calendarAppConfig)),
      localizationsDelegates: const [
        ZtL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

/// A 1080x2400 phone, like the devices the app ships to.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// The button showing [label] is laid out inside the screen and a tap on its
/// centre reaches it (a button that failed layout is not drawn at all).
void expectTappableOnScreen(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(button, findsOneWidget, reason: '"$label" button is missing');
  final rect = tester.getRect(button);
  final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.width, greaterThan(0), reason: '"$label" has no width');
  expect(rect.isFinite, isTrue, reason: '"$label" has no finite size');
  expect(screen.contains(rect.center), isTrue, reason: '"$label" is off screen at $rect');
  expect(button.hitTestable(), findsOneWidget,
      reason: '"$label" is covered or cannot be tapped');
}

void main() {
  final now = DateTime.now();
  final today9 = DateTime(now.year, now.month, now.day, 9);
  final events = [
    CalendarEvent(
      id: 'standup',
      title: 'Stand-up',
      start: today9,
      end: today9.add(const Duration(minutes: 30)),
      rrule: 'FREQ=DAILY',
      reminders: const [10],
    ),
    CalendarEvent(
      id: 'trip',
      title: 'Trip',
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day + 2),
      allDay: true,
    ),
  ];

  testWidgets('every view shows today\'s events', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HomePage(), events));
    await tester.pumpAndSettle();
    // Month is the default view.
    expect(find.text('Stand-up'), findsWidgets);

    final views = {
      CalendarView.schedule: ScheduleView,
      CalendarView.day: TimelineView,
      CalendarView.threeDay: TimelineView,
      CalendarView.week: TimelineView,
      CalendarView.month: MonthView,
    };
    for (final MapEntry(key: view, value: type) in views.entries) {
      await tester.tap(find.byTooltip('Change view'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<CalendarView> && w.value == view,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget, reason: '$view');
      expect(find.text('Stand-up'), findsWidgets, reason: '$view');
      expect(find.text('Trip'), findsWidgets, reason: '$view');
    }
  });

  testWidgets('the editor opens for a new event', (tester) async {
    await tester.pumpWidget(app(const EventEditorPage(), events));
    await tester.pumpAndSettle();
    expect(find.text('Add title'), findsOneWidget);
    expect(find.text('Does not repeat'), findsOneWidget);
    expect(find.text('10 minutes before'), findsOneWidget);
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    expect(find.text('Every day'), findsOneWidget);
    await tester.tap(find.text('Every day'));
    await tester.pumpAndSettle();
    expect(find.text('Every day'), findsOneWidget);
  });

  testWidgets('the editor Save button is on screen with the app theme', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(app(const EventEditorPage(), events));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectTappableOnScreen(tester, 'Save');
  });

  testWidgets('the quick add sheet shows its Add button', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showQuickAdd(context),
            child: const Text('open'),
          ),
        ),
      ),
      events,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectTappableOnScreen(tester, 'Add');
  });

  testWidgets('event details show the Join video call button', (tester) async {
    usePhoneScreen(tester);
    final call = CalendarEvent(
      id: 'call',
      title: 'Video call',
      start: today9,
      end: today9.add(const Duration(hours: 1)),
      conferenceUrl: 'https://meet.example.com/abc',
    );
    await tester.pumpWidget(app(const EventDetailsPage(eventId: 'call'), [...events, call]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectTappableOnScreen(tester, 'Join video call');
  });

  test('settings round-trip through preferences', () {
    const s = CalendarSettings(view: CalendarView.week, defaultReminder: null, weekStart: 1);
    final back = CalendarSettings.fromPrefs(s.toPrefs());
    expect(back.view, CalendarView.week);
    expect(back.defaultReminder, isNull);
    expect(back.weekStart, 1);
  });
}
