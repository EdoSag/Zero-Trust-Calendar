import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/booking/booking_pages.dart';
import 'package:zerotrust_calendar/data/find_a_time.dart';
import 'package:zerotrust_calendar/data/working_hours.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/planner/planner_plan.dart';
import 'package:zerotrust_calendar/ui/booking_pages_page.dart';
import 'package:zerotrust_calendar/ui/event_editor_page.dart';

import 'home_page_test.dart' show app, expectTappableOnScreen, usePhoneScreen;

void main() {
  // Monday 16 November 2026.
  final monday = DateTime(2026, 11, 16);
  DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);
  final sundayBefore = DateTime(2026, 11, 15);

  group('Find a time in working hours', () {
    test('slots fit inside the day\'s ranges, days without hours are skipped', () {
      final slots = freeSlots(
        busy: [(at(16, 10), at(16, 11))],
        from: monday,
        now: sundayBefore,
        length: const Duration(hours: 1),
        days: 3,
        hours: {
          DateTime.monday: const [(14 * 60, 16 * 60), (9 * 60, 12 * 60)],
          DateTime.wednesday: const [(9 * 60 + 15, 11 * 60)],
        },
      );
      expect(slots, [
        at(16, 9), // 9:30 and 10:00 clash with the 10:00 meeting.
        at(16, 11),
        at(16, 14),
        at(16, 14, 30),
        at(16, 15),
        // Tuesday: no hours. Wednesday: on the half-hour grid from 9:30.
        at(18, 9, 30),
        at(18, 10),
      ]);
    });

    test('without working hours the old day window applies', () {
      final slots = freeSlots(
        busy: const [],
        from: monday,
        now: sundayBefore,
        length: const Duration(hours: 1),
        days: 1,
        dayStartHour: 8,
        dayEndHour: 10,
      );
      expect(slots, [at(16, 8), at(16, 8, 30), at(16, 9)]);
    });

    test('working hours are the Planner\'s work hours, with a default', () {
      const none = PlannerSettings();
      expect(
        workingHoursOf(none, DateTime.sunday)[DateTime.sunday],
        const [(9 * 60, 17 * 60)],
      );
      expect(workingHoursOf(none, DateTime.sunday)[DateTime.friday], isNull);
      final mine = withWorkingHours(none, {
        DateTime.monday: const [(10 * 60, 14 * 60)],
      }, DateTime.monday);
      expect(workingHoursOf(mine, DateTime.monday), {
        DateTime.monday: const [(10 * 60, 14 * 60)],
      });
      // The personal hours the Planner's setup would have saved come along.
      expect(mine.hours[personalHoursId], isNotEmpty);
      // Saved personal hours stay as they were.
      final again = withWorkingHours(mine.copyWith(hours: {
        ...mine.hours,
        personalHoursId: {DateTime.sunday: const [(60, 120)]},
      }), const {}, DateTime.monday);
      expect(again.hours[personalHoursId], {DateTime.sunday: const [(60, 120)]});
      expect(workingHoursOf(again, DateTime.monday), isEmpty);
    });
  });

  group('out of office', () {
    final away = CalendarEvent(
      id: 'ooo',
      title: 'Vacation',
      start: monday,
      end: DateTime(2026, 11, 18),
      allDay: true,
      outOfOffice: true,
    );
    final holiday = CalendarEvent(
      id: 'h',
      title: 'Holiday',
      start: DateTime(2026, 11, 19),
      end: DateTime(2026, 11, 20),
      allDay: true,
    );

    test('is kept in the event and left out when off', () {
      final back = CalendarEvent.fromJson('ooo', away.toJson(), null)!;
      expect(back.outOfOffice, isTrue);
      expect(holiday.toJson().containsKey('ooo'), isFalse);
      expect(CalendarEvent.fromJson('h', holiday.toJson(), null)!.outOfOffice, isFalse);
      expect(holiday.copyWith(outOfOffice: true).outOfOffice, isTrue);
    });

    test('an all-day out-of-office event is busy; an all-day holiday is not', () {
      final blocks = busyBlocks(
        events: [away, holiday],
        calendars: const [ZtCalendarInfo.personal],
        from: monday,
      );
      expect(blocks, [(monday, DateTime(2026, 11, 18))]);
      // So booking pages and Find a time offer nothing on those days.
      final slots = freeSlots(
        busy: blocks,
        from: monday,
        now: sundayBefore,
        length: const Duration(hours: 1),
        days: 3,
      );
      expect(slots.every((s) => s.day == 18), isTrue);
      expect(slots, isNotEmpty);
    });

    test('the Planner keeps out-of-office days clear', () {
      final busy = planBusyOf(
        settings: const PlannerSettings(),
        events: [away, holiday],
        calendars: const [ZtCalendarInfo.personal],
        from: monday,
        to: DateTime(2026, 11, 23),
      );
      expect(busy, hasLength(1));
    });
  });

  for (final locale in const [Locale('en'), Locale('he')]) {
    final he = locale.languageCode == 'he';

    testWidgets('a booking page can copy my working hours ($locale)', (tester) async {
      usePhoneScreen(tester);
      final page = BookingPage(
        id: 'bAAAAAAAAAAAAAAAAAAAAAA',
        title: 'Intro call',
        durationMin: 30,
        timeZone: 'Asia/Jerusalem',
        hours: {
          for (var d = 1; d <= 7; d++) d: d == DateTime.saturday ? const [(600, 720)] : const [],
        },
        publicKey: 'x',
      );
      await tester.pumpWidget(app(
        BookingPageEditor(page: page),
        const [],
        locale: locale,
        overrides: [
          bookingPagesProvider.overrideWith((ref) async => [page]),
          upcomingBookingsProvider.overrideWith((ref) async => const []),
        ],
      ));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('booking-use-working-hours'));
      await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expectTappableOnScreen(tester, he ? 'לפי שעות העבודה שלי' : 'Use my working hours');
      // The section title and the button sit side by side without overlap.
      final title = tester.getRect(find.text(he ? 'שעות זמינות' : 'Available hours'));
      expect(title.overlaps(tester.getRect(button)), isFalse);
      expect((title.center.dy - tester.getRect(button).center.dy).abs(), lessThan(12));

      bool on() => tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .any((c) => c.value == true);
      int count() => tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((c) => c.value == true)
          .length;
      expect(on(), isTrue);
      expect(count(), 1);
      await tester.tap(button);
      await tester.pumpAndSettle();
      // The default work week: five days, 9:00 to 17:00.
      expect(count(), 5);
      expect(find.byType(InputChip), findsNWidgets(5));
    });

    testWidgets('an event can be marked out of office ($locale)', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(app(const EventEditorPage(), const [], locale: locale));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('event-out-of-office'));
      await tester.scrollUntilVisible(toggle, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(toggle.hitTestable(), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      // An empty title becomes "Out of office".
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      final label = he ? 'מחוץ למשרד' : 'Out of office';
      expect(
        find.byWidgetPredicate((w) => w is TextField && w.controller?.text == label),
        findsOneWidget,
      );
    });
  }
}
