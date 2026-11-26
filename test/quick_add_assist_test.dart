import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_config.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/l10n/generated/app_l10n_en.dart';
import 'package:zerotrust_calendar/l10n/generated/app_l10n_he.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/model/linked_items.dart';
import 'package:zerotrust_calendar/model/recurrence.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';
import 'package:zerotrust_calendar/ui/event_editor_page.dart';
import 'package:zerotrust_calendar/ui/quick_add_sheet.dart';
import 'package:zerotrust_calendar/util/quick_add.dart';
import 'package:zerotrust_calendar/util/quick_add_assist.dart';
import 'package:zt_assist/testing.dart';
import 'package:zt_assist/zt_assist.dart';

/// Keeps what the sheet saves.
class MemoryRepository extends CalendarRepository {
  MemoryRepository(super.ref);

  final saved = <CalendarEvent>[];

  @override
  Future<void> saveEvent(CalendarEvent event) async => saved.add(event);
}

final l = AppL10nEn();

void main() {
  group('putting the two readings together', () {
    // A Thursday afternoon.
    final now = DateTime(2026, 11, 26, 14, 30);

    QuickAdd merged(String text, ZtAssistQuickAdd read) =>
        mergeAssistReading(parseQuickAdd(text, now: now), read, now: now);

    test('the title is ZT Assist\'s, the day and time the app read stay', () {
      // The phone test: the model got the title and dropped the time.
      final q = merged(
        'מחר ב-9:00 רופא שיניים, להזכיר שעה לפני',
        ZtAssistQuickAdd(
          title: 'רופא שיניים',
          day: DateTime(2026, 11, 27),
          remindMinutesBefore: 60,
        ),
      );
      expect(q.title, 'רופא שיניים');
      expect(q.start, DateTime(2026, 11, 27, 9));
      expect(q.end, DateTime(2026, 11, 27, 10));
      expect(q.allDay, isFalse);
      expect(q.remindMinutesBefore, 60);
    });

    test('the app\'s own day wins over ZT Assist\'s', () {
      final q = merged(
        'Lunch with Dana on friday',
        ZtAssistQuickAdd(title: 'Lunch with Dana', day: DateTime(2026, 11, 28)),
      );
      // Friday is the 27th, whatever the model counted.
      expect(q.start, DateTime(2026, 11, 27));
      expect(q.end, DateTime(2026, 11, 28));
      expect(q.allDay, isTrue);
    });

    test('ZT Assist\'s time wins: it understands the wording', () {
      // The app reads "at 9" as 09:00 and does not see "in the evening".
      final q = merged(
        'Dinner with Dana tomorrow at 9 in the evening',
        ZtAssistQuickAdd(
          title: 'Dinner with Dana',
          day: DateTime(2026, 11, 27),
          hour: 21,
          minute: 0,
        ),
      );
      expect(q.title, 'Dinner with Dana');
      expect(q.start, DateTime(2026, 11, 27, 21));
      expect(q.end, DateTime(2026, 11, 27, 22));
    });

    test('a day, a time, a length and a place the app could not read', () {
      final q = merged(
        'פגישה עם רואה החשבון בחמישה בדצמבר בארבע וחצי במשרד שלו, שעה וחצי',
        ZtAssistQuickAdd(
          title: 'פגישה עם רואה החשבון',
          day: DateTime(2026, 12, 5),
          hour: 16,
          minute: 30,
          lengthMinutes: 90,
          place: 'משרד שלו',
        ),
      );
      expect(q.title, 'פגישה עם רואה החשבון');
      expect(q.start, DateTime(2026, 12, 5, 16, 30));
      expect(q.end, DateTime(2026, 12, 5, 18));
      expect(q.location, 'משרד שלו');
      expect(q.hasDate, isTrue);
      expect(q.hasLength, isTrue);
    });

    test('only a time: today, or tomorrow when it has passed', () {
      const text = 'Call with the team';
      final later = merged(text, const ZtAssistQuickAdd(title: text, hour: 18, minute: 0));
      expect(later.start, DateTime(2026, 11, 26, 18));
      final passed = merged(text, const ZtAssistQuickAdd(title: text, hour: 8, minute: 0));
      expect(passed.start, DateTime(2026, 11, 27, 8));
    });

    test('the length the text gave is kept when ZT Assist moves the time', () {
      final q = merged(
        'Workshop tomorrow 9-11:30',
        ZtAssistQuickAdd(title: 'Workshop', day: DateTime(2026, 11, 27), hour: 9, minute: 0),
      );
      expect(q.start, DateTime(2026, 11, 27, 9));
      expect(q.end, DateTime(2026, 11, 27, 11, 30));
    });

    test('the default length when nobody says how long', () {
      final q = mergeAssistReading(
        parseQuickAdd('Standup tomorrow', now: now, defaultMinutes: 30),
        const ZtAssistQuickAdd(title: 'Standup', hour: 10, minute: 0),
        now: now,
        defaultMinutes: 30,
      );
      expect(q.start, DateTime(2026, 11, 27, 10));
      expect(q.end, DateTime(2026, 11, 27, 10, 30));
      expect(q.hasLength, isFalse);
    });

    test('nothing about the day or the time leaves an all-day event today', () {
      final q = merged('Buy flowers', const ZtAssistQuickAdd(title: 'Flowers'));
      expect(q.title, 'Flowers');
      expect(q.start, DateTime(2026, 11, 26));
      expect(q.allDay, isTrue);
      expect(q.hasDate, isFalse);
    });

    test('a repeat and the app\'s own place stay', () {
      final q = merged(
        'Yoga every monday 7pm at Studio One',
        const ZtAssistQuickAdd(title: 'Yoga'),
      );
      expect(q.title, 'Yoga');
      expect(q.rule?.frequency, Frequency.weekly);
      expect(q.location, 'Studio One');
      expect(q.start, DateTime(2026, 11, 30, 19));
    });

    test('the app\'s reading says whether a length was given', () {
      expect(parseQuickAdd('Call 1-2pm', now: now).hasLength, isTrue);
      expect(parseQuickAdd('Call 1pm for 30 min', now: now).hasLength, isTrue);
      expect(parseQuickAdd('Call 1pm', now: now).hasLength, isFalse);
      expect(parseQuickAdd('Call tomorrow', now: now).hasLength, isFalse);
    });
  });

  group('the quick add sheet', () {
    late ZtAssist before;
    late MemoryRepository repository;

    setUp(() => before = ZtAssist.instance);
    tearDown(() => ZtAssist.instance = before);

    Future<void> openSheet(WidgetTester tester, {Locale? locale}) async {
      // A 1080x2400 phone, like the devices the app ships to.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ztAppConfigProvider.overrideWithValue(calendarAppConfig),
            ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
            reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
            calendarRepositoryProvider.overrideWith((ref) => repository = MemoryRepository(ref)),
            // What the editor behind "More options" reads.
            eventsProvider.overrideWith((ref) => Stream.value(const <CalendarEvent>[])),
            calendarsProvider.overrideWith((ref) => Stream.value(const [ZtCalendarInfo.personal])),
            linkedNotesProvider.overrideWith((ref) => Stream.value(const <LinkedNote>[])),
            linkedTasksProvider.overrideWith((ref) => Stream.value(const <LinkedTask>[])),
            linkedContactsProvider.overrideWith((ref) => Stream.value(const <LinkedContact>[])),
            feedsProvider.overrideWith((ref) => Stream.value(const <CalendarFeed>[])),
            plannerSettingsProvider.overrideWith((ref) => Stream.value(const PlannerSettings())),
          ],
          child: MaterialApp(
            // The suite's real theme, as inside the app.
            theme: ZtTheme.light(accent: ZtTheme.accentFor(calendarAppConfig)),
            locale: locale,
            supportedLocales: ZtLanguages.supported,
            localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
            home: Scaffold(
              body: Builder(
                builder: (context) =>
                    TextButton(onPressed: () => showQuickAdd(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final button = find.byKey(const ValueKey('quick-add-assist'));
    final read = find.byKey(const ValueKey('quick-add-assist-read'));
    final screenWidth = 1080 / 2.625;

    testWidgets('without ZT Assist on the phone there is no button', (tester) async {
      ZtAssist.instance = FakeZtAssist(state: ZtAssistAvailability.notInstalled);
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9');
      await tester.pump();
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the button shows once something is typed, above Add', (tester) async {
      ZtAssist.instance = FakeZtAssist();
      await openSheet(tester);
      expect(button, findsNothing);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9');
      await tester.pump();
      expect(find.text(l.quickAddAssist), findsOneWidget);
      final field = tester.getRect(find.byType(TextField));
      final add = tester.getRect(find.widgetWithText(FilledButton, l.add));
      final assist = tester.getRect(button);
      expect(assist.top, greaterThan(field.bottom));
      expect(assist.bottom, lessThanOrEqualTo(add.top));
      // Inside the sheet, at its start, and not stretched across it.
      expect(assist.left, greaterThanOrEqualTo(field.left));
      expect(assist.right, lessThanOrEqualTo(field.right));
      expect(assist.width, lessThan(field.width));
      // Add is still there, on screen.
      expect(add.width, greaterThan(0));
      expect(add.right, lessThanOrEqualTo(screenWidth));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ZT Assist reads the line, and what it read is added', (tester) async {
      final assist = FakeZtAssist(
        answer: (_) => [
          '{"title":"Dinner with Dana","date":null,"time":"21:00",',
          '"minutes":120,"remind":60,"place":"Cafe Nehama"}',
        ],
      );
      ZtAssist.instance = assist;
      await openSheet(tester);
      const text =
          'Dinner with Dana tomorrow at 9 in the evening in Cafe Nehama, two hours, '
          'tell me an hour before';
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(assist.requests.single.task, ZtAssistTask.quickAdd);
      expect(assist.requests.single.text, text);
      expect(find.text('Dinner with Dana'), findsOneWidget);
      expect(find.text(l.quickAddAssistRead), findsOneWidget);
      expect(button, findsNothing);
      // The place and the reminder are in the summary, above the note that
      // it is ZT Assist's reading.
      final summary = find.textContaining('Cafe Nehama\n${l.reminderIs('1 hour before')}');
      expect(summary, findsOneWidget);
      expect(tester.getTopLeft(read).dy, greaterThan(tester.getTopLeft(summary).dy));
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, l.add));
      await tester.pumpAndSettle();
      final event = repository.saved.single;
      final now = DateTime.now();
      // The day is the app's own "tomorrow"; the rest is ZT Assist's.
      final start = DateTime(now.year, now.month, now.day + 1, 21);
      expect(event.title, 'Dinner with Dana');
      expect(event.start, start);
      expect(event.end, start.add(const Duration(hours: 2)));
      expect(event.allDay, isFalse);
      expect(event.location, 'Cafe Nehama');
      expect(event.reminders, [60]);
    });

    testWidgets('"More options" opens the editor with what ZT Assist read', (tester) async {
      ZtAssist.instance = FakeZtAssist(
        answer: (_) => ['{"title":"Dinner with Dana","time":"21:00"}'],
      );
      await openSheet(tester);
      await tester.enterText(
        find.byType(TextField),
        'Dinner with Dana tomorrow at 9 in the evening',
      );
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.moreOptions));
      await tester.pumpAndSettle();

      final editor = tester.widget<EventEditorPage>(find.byType(EventEditorPage));
      expect(editor.draft!.title, 'Dinner with Dana');
      expect(editor.draft!.start.hour, 21);
    });

    testWidgets('typing again drops what ZT Assist read', (tester) async {
      ZtAssist.instance = FakeZtAssist(answer: (_) => ['{"title":"Dinner","time":"21:00"}']);
      await openSheet(tester);
      await tester.enterText(
        find.byType(TextField),
        'Dinner with Dana tomorrow at 9 in the evening',
      );
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(read, findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Dinner with Dana tomorrow at 9 in the evening!',
      );
      await tester.pump();
      expect(read, findsNothing);
      expect(find.text('Dinner'), findsNothing);
      expect(button, findsOneWidget);
    });

    testWidgets('while it reads there is a Stop, and Stop stops the model', (tester) async {
      final gate = Completer<void>();
      final assist = FakeZtAssist(
        answer: (_) => ['{"title":"Dentist"}'],
        beforePiece: () => gate.future,
      );
      ZtAssist.instance = assist;
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9');
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      expect(find.text(l.quickAddAssistReading), findsOneWidget);
      final stop = find.byKey(const ValueKey('quick-add-assist-stop'));
      final stopAt = tester.getRect(stop);
      expect(stopAt.width, greaterThan(0));
      expect(stopAt.right, lessThanOrEqualTo(screenWidth));
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(stop);
      await tester.pump();
      expect(assist.cancelled, 1);
      expect(button, findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(read, findsNothing);
    });

    testWidgets('typing while it reads stops the model', (tester) async {
      final gate = Completer<void>();
      final assist = FakeZtAssist(
        answer: (_) => ['{"title":"Dentist"}'],
        beforePiece: () => gate.future,
      );
      ZtAssist.instance = assist;
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9');
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 10');
      await tester.pump();
      expect(assist.cancelled, 1);
      expect(button, findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(read, findsNothing);
    });

    testWidgets('an answer that cannot be used is said, and the usual reading stays', (
      tester,
    ) async {
      ZtAssist.instance = FakeZtAssist(answer: (_) => ['I am not sure what you mean.']);
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9am');
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text(l.quickAddAssistNotUnderstood), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(read, findsNothing);
      // It can be asked again; the words sit under the button.
      expect(button, findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('quick-add-assist-problem'))).dy,
        greaterThan(tester.getTopLeft(button).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('each failure is said in words', (tester) async {
      final assist = FakeZtAssist(answer: (_) => const []);
      ZtAssist.instance = assist;
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 9');
      await tester.pump();
      for (final (error, words) in [
        (ZtAssistError.noModel, l.assistNoModel),
        (ZtAssistError.needsUpdate, l.assistNeedsUpdate),
        (ZtAssistError.loadFailed, l.assistLoadFailed),
        (ZtAssistError.stopped, l.assistStopped),
        (ZtAssistError.failed, l.assistFailed),
        (ZtAssistError.notInstalled, l.assistNotInstalled),
      ]) {
        assist.error = error;
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text(words), findsOneWidget, reason: '$error');
        expect(tester.takeException(), isNull, reason: '$error');
      }
    });

    testWidgets('in Hebrew the button and the note fit', (tester) async {
      final he = AppL10nHe();
      ZtAssist.instance = FakeZtAssist(
        answer: (_) => ['{"title":"רופא שיניים","date":null,"time":null,"remind":60}'],
      );
      await openSheet(tester, locale: ZtLanguages.hebrew);
      await tester.enterText(find.byType(TextField), 'מחר ב-9:00 רופא שיניים, להזכיר שעה לפני');
      await tester.pump();
      expect(find.text(he.quickAddAssist), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('רופא שיניים'), findsOneWidget);
      expect(find.text(he.quickAddAssistRead), findsOneWidget);
      expect(find.textContaining(he.reminderIs(he.reminderHoursBefore(1))), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
