import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/ui/subscribe_page.dart';

Widget _app(Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: ZtLanguages.supported,
  localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showFeedLinkHelp(context),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  for (final locale in [const Locale('en'), ZtLanguages.hebrew]) {
    testWidgets('link help lists Google, Outlook and iCloud in order '
        '(${locale.languageCode})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(locale));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = lookupAppL10n(locale);
      final title = find.text(l10n.getALinkFromAnotherCalendar);
      final google = find.text(l10n.feedHelpGoogleTitle);
      final googleBody = find.text(l10n.feedHelpGoogle);
      final outlook = find.text(l10n.feedHelpOutlookTitle);
      final icloud = find.text(l10n.feedHelpIcloudTitle);
      final privacy = find.text(l10n.feedHelpPrivacy);
      for (final f in [title, google, googleBody, outlook, icloud]) {
        expect(f, findsOneWidget);
      }
      // Top to bottom: title, Google (heading above its steps), Outlook,
      // iCloud, then the privacy note (scrolled to on small screens).
      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(top(google), greaterThan(top(title)));
      expect(top(googleBody), greaterThan(top(google)));
      expect(top(outlook), greaterThan(top(googleBody)));
      expect(top(icloud), greaterThan(top(outlook)));

      // Headings start on the reading side: left in English, right in
      // Hebrew, lined up with their steps.
      final dialog = tester.getRect(find.byType(AlertDialog));
      final heading = tester.getRect(google);
      final body = tester.getRect(googleBody);
      if (locale.languageCode == 'he') {
        expect(heading.right, moreOrLessEquals(body.right, epsilon: 1));
        expect(dialog.right - heading.right, lessThan(dialog.width / 4));
      } else {
        expect(heading.left, moreOrLessEquals(body.left, epsilon: 1));
        expect(heading.left - dialog.left, lessThan(dialog.width / 4));
      }

      await tester.ensureVisible(privacy);
      await tester.pumpAndSettle();
      expect(top(privacy), greaterThan(top(icloud)));
      expect(tester.getRect(privacy).bottom, lessThanOrEqualTo(dialog.bottom));

      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();
      expect(title, findsNothing);
    });
  }
}
