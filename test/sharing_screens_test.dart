import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/caldav/caldav_bridge.dart';
import 'package:zerotrust_calendar/data/shared_calendars.dart';
import 'package:zerotrust_calendar/ui/calendars_page.dart';
import 'package:zerotrust_calendar/ui/desktop_bridge_page.dart';
import 'package:zerotrust_calendar/ui/shared_calendar_pages.dart';

import 'home_page_test.dart' show app, expectTappableOnScreen, usePhoneScreen;

const _creds = BridgeCredentials(
  username: 'zt',
  password: 'abcd-efgh-jkmn-pqrs-tuvw',
  certPem: '',
  keyPem: '',
  fingerprint: 'AB:CD',
);

class _RunningBridge extends DesktopBridgeController {
  @override
  DesktopBridgeState build() => const DesktopBridgeState(
    enabled: true,
    running: true,
    address: '192.168.1.20',
    credentials: _creds,
  );

  @override
  Future<void> refreshAddress() async {}
}

Widget sharingApp(Widget home, {Locale? locale}) => app(
  home,
  const [],
  locale: locale,
  overrides: [
    sharedCalendarsProvider.overrideWith((ref) async => const []),
    pendingJoinsProvider.overrideWith((ref) async => const <PendingJoin>[]),
    desktopBridgeProvider.overrideWith(_RunningBridge.new),
  ],
);

void main() {
  for (final locale in const [Locale('en'), Locale('he')]) {
    testWidgets('join page: link, name and Join fit the screen ($locale)', (
      tester,
    ) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(
        sharingApp(const JoinCalendarPage(), locale: locale),
      );
      await tester.pumpAndSettle();
      expectTappableOnScreen(
        tester,
        locale.languageCode == 'he' ? 'הצטרפות' : 'Join',
      );
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      // The name field sits under the link field, not on top of it.
      expect(
        tester.getRect(fields.at(1)).top,
        greaterThanOrEqualTo(tester.getRect(fields.at(0)).bottom),
      );
      // Bad link: the error shows instead of joining.
      await tester.enterText(fields.at(0), 'https://example.com');
      await tester.enterText(fields.at(1), 'Dana');
      await tester.tap(
        find.text(locale.languageCode == 'he' ? 'הצטרפות' : 'Join'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale.languageCode == 'he'
              ? 'זה לא קישור הזמנה של Zero-Trust.'
              : "That isn't a Zero-Trust invite link.",
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('the + on Calendars offers new, shared, family and join', (
    tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(sharingApp(const CalendarsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final labels = [
      'New calendar',
      'New shared calendar',
      'New family calendar',
      'Join a shared calendar',
    ];
    double? last;
    for (final label in labels) {
      final tile = find.ancestor(
        of: find.text(label).last,
        matching: find.byType(ListTile),
      );
      expect(tile, findsOneWidget, reason: label);
      final rect = tester.getRect(tile);
      if (last != null) expect(rect.top, greaterThanOrEqualTo(last));
      last = rect.bottom;
      expect(tile.hitTestable(), findsOneWidget, reason: label);
    }
  });

  for (final locale in const [Locale('en'), Locale('he')]) {
    testWidgets('desktop bridge shows address, login and copy buttons '
        '($locale)', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(
        sharingApp(const DesktopBridgePage(), locale: locale),
      );
      await tester.pumpAndSettle();
      expect(find.text('https://192.168.1.20:8443/'), findsOneWidget);
      expect(find.text('abcd-efgh-jkmn-pqrs-tuvw'), findsOneWidget);
      final copies = find.byIcon(Icons.copy);
      expect(copies, findsNWidgets(3));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (var i = 0; i < 3; i++) {
        final r = tester.getRect(copies.at(i));
        // Copy buttons sit at the row's end: right in English, left in Hebrew.
        if (locale.languageCode == 'he') {
          expect(r.center.dx, lessThan(width / 2));
        } else {
          expect(r.center.dx, greaterThan(width / 2));
        }
      }
      // The password stays left-to-right inside Hebrew.
      final pw = tester.widget<Text>(find.text('abcd-efgh-jkmn-pqrs-tuvw'));
      expect(pw.textDirection, TextDirection.ltr);
    });
  }
}
