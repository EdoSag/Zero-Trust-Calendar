import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/booking/booking_pages.dart';
import 'package:zerotrust_calendar/ui/booking_pages_page.dart';

import 'home_page_test.dart' show app, expectTappableOnScreen, usePhoneScreen;

final _page = BookingPage(
  id: 'bAAAAAAAAAAAAAAAAAAAAAA',
  title: 'Intro call',
  durationMin: 30,
  timeZone: 'Asia/Jerusalem',
  hours: BookingPage.defaultHours(),
  publicKey: 'x',
);

Widget bookingApp(Widget home, {Locale? locale}) => app(
  home,
  const [],
  locale: locale,
  overrides: [
    bookingPagesProvider.overrideWith((ref) async => [_page]),
    upcomingBookingsProvider.overrideWith((ref) async => [
      Booking(
        id: 'b1',
        pageId: _page.id,
        start: DateTime.now().add(const Duration(days: 1)),
        end: DateTime.now().add(const Duration(days: 1, minutes: 30)),
        status: 'new',
      ),
    ]),
  ],
);

void main() {
  for (final locale in const [Locale('en'), Locale('he')]) {
    final he = locale.languageCode == 'he';

    testWidgets('booking pages list shows the page and the booking ($locale)', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(bookingApp(const BookingPagesPage(), locale: locale));
      await tester.pumpAndSettle();
      expect(find.text('Intro call'), findsWidgets);
      final fab = find.byType(FloatingActionButton);
      expect(find.descendant(of: fab, matching: find.text(he ? 'דף חדש לקביעת פגישות' : 'New booking page')), findsOneWidget);
      final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(screen.contains(tester.getRect(fab).center), isTrue);
      expect(fab.hitTestable(), findsOneWidget);
      expect(find.text(he ? 'פגישות קרובות' : 'Upcoming bookings'), findsOneWidget);
    });

    testWidgets('booking page editor: fields and hours fit the screen ($locale)', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(bookingApp(BookingPageEditor(page: _page), locale: locale));
      await tester.pumpAndSettle();
      expectTappableOnScreen(tester, he ? 'שמירה' : 'Save');
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      expect(
        tester.getRect(fields.at(1)).top,
        greaterThanOrEqualTo(tester.getRect(fields.at(0)).bottom),
      );
      // The weekday rows: the day name and its hours don't overlap.
      await tester.scrollUntilVisible(
        find.text(he ? 'שעות זמינות' : 'Available hours'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final day = find.byType(CheckboxListTile).first;
      final chip = find.byType(InputChip).first;
      final a = tester.getRect(day);
      final b = tester.getRect(chip);
      expect(a.overlaps(b), isFalse);
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio));
    });
  }
}
