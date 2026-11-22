import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_config.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/platform/channels.dart';
import 'package:zerotrust_calendar/ui/pick_for_keyboard_page.dart';

void main() {
  final now = DateTime(2026, 11, 22, 9, 30);
  final events = [
    CalendarEvent(
      id: 'dentist',
      title: 'Dentist',
      start: DateTime(2026, 11, 24, 10),
      end: DateTime(2026, 11, 24, 11),
      location: '5 Herzl St',
      conferenceUrl: 'https://meet.example/abc',
    ),
    CalendarEvent(
      id: 'trip',
      title: 'Trip',
      start: DateTime(2026, 11, 26),
      end: DateTime(2026, 11, 29),
      allDay: true,
    ),
    CalendarEvent(
      id: 'standup',
      title: 'Standup',
      start: DateTime(2026, 11, 2, 8),
      end: DateTime(2026, 11, 2, 8, 15),
      rrule: 'FREQ=WEEKLY',
    ),
    CalendarEvent(
      id: 'old',
      title: 'Old party',
      start: DateTime(2026, 10, 1, 20),
      end: DateTime(2026, 10, 1, 23),
    ),
    CalendarEvent(
      id: 'far',
      title: 'Far away',
      start: DateTime(2027, 3, 1, 12),
      end: DateTime(2027, 3, 1, 13),
    ),
  ];

  test('offers the next 30 days, soonest first, each repeat on its own', () {
    final found = pickOccurrences(events, now, '');
    expect(found.map((o) => o.event.id), [
      'standup', // Nov 23
      'dentist',
      'trip',
      'standup', // Nov 30
      'standup', // Dec 7
      'standup', // Dec 14
      'standup', // Dec 21
    ]);
    expect(found.first.start, DateTime(2026, 11, 23, 8));
  });

  test('a search finds past and far events too, upcoming first', () {
    expect(pickOccurrences(events, now, 'PARTY').single.event.id, 'old');
    expect(pickOccurrences(events, now, 'far').single.event.id, 'far');
    expect(pickOccurrences(events, now, 'herzl').single.event.id, 'dentist');
    expect(pickOccurrences(events, now, 'a').map((o) => o.event.id), [
      'standup',
      'far',
      'old',
    ]);
    expect(pickOccurrences(events, now, 'zzz'), isEmpty);
  });

  Future<String? Function()> open(WidgetTester tester) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [allEventsProvider.overrideWithValue(AsyncData(events))],
        child: MaterialApp(
          theme: ZtTheme.light(accent: ZtTheme.accentFor(calendarAppConfig)),
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => PickForKeyboardPage(now: now)),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => picked;
  }

  testWidgets('Today types the date', (tester) async {
    final picked = await open(tester);
    expect(find.text('Insert into ZT Keyboard'), findsOneWidget);
    // Dates first, then the events, all below the search field and on screen.
    final height = tester.getSize(find.byType(MaterialApp)).height;
    final search = tester.getBottomLeft(find.byType(TextField)).dy;
    final today = tester.getTopLeft(find.text('Today')).dy;
    final tomorrow = tester.getTopLeft(find.text('Tomorrow')).dy;
    final other = tester.getTopLeft(find.text('Another date')).dy;
    final dentist = tester.getTopLeft(find.text('Dentist')).dy;
    expect(today, greaterThan(search));
    expect(tomorrow, greaterThan(today));
    expect(other, greaterThan(tomorrow));
    expect(dentist, greaterThan(other));
    expect(dentist, lessThan(height));
    expect(find.text('Old party'), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(picked(), 'Sunday, November 22, 2026');
  });

  testWidgets('an event offers its title, time, date, place and link', (tester) async {
    final picked = await open(tester);
    await tester.tap(find.text('Dentist'));
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(MaterialApp)).height;
    for (final label in ['Title', 'Date and time', 'Date', 'Place', 'Video call link']) {
      expect(find.text(label), findsOneWidget);
      expect(tester.getBottomLeft(find.text(label)).dy, lessThan(height));
    }
    expect(find.text('5 Herzl St'), findsOneWidget);
    expect(find.text('https://meet.example/abc'), findsOneWidget);
    await tester.tap(find.text('Date and time'));
    await tester.pumpAndSettle();
    expect(picked(), startsWith('Tuesday, November 24, 2026, 10:00'));
    expect(picked(), contains('11:00'));
  });

  testWidgets('an all-day trip types its days; a search reaches past events', (tester) async {
    final picked = await open(tester);
    await tester.enterText(find.byType(TextField), 'party');
    await tester.pumpAndSettle();
    expect(find.text('Old party'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    await tester.enterText(find.byType(TextField), 'trip');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date and time'));
    await tester.pumpAndSettle();
    expect(picked(), 'Thursday, November 26, 2026 to Saturday, November 28, 2026');
  });

  testWidgets('the picked text goes back over the text_pick channel', (tester) async {
    const channel = MethodChannel('zt_calendar/text_pick');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isPick' ? true : null;
    });
    expect(await KeyboardPick.requested(), isTrue);
    await KeyboardPick.finish('hello');
    expect(calls.map((c) => c.method), ['isPick', 'finish']);
    expect(calls.last.arguments, {'text': 'hello'});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
