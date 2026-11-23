import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/app/calendar_config.dart';
import 'package:zerotrust_calendar/data/subscriptions.dart';
import 'package:zerotrust_calendar/data/time_links.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/ui/import_sheet.dart';
import 'package:zerotrust_calendar/ui/pick_for_keyboard_page.dart';

void main() {
  final now = DateTime(2026, 11, 22, 9, 30);
  final dentist = CalendarEvent(
    id: 'dentist',
    title: 'Dentist',
    start: DateTime(2026, 11, 24, 10),
    end: DateTime(2026, 11, 24, 11),
  );
  final standup = CalendarEvent(
    id: 'standup',
    title: 'Standup',
    start: DateTime(2026, 11, 2, 8),
    end: DateTime(2026, 11, 2, 8, 15),
    rrule: 'FREQ=WEEKLY',
  );
  final trip = CalendarEvent(
    id: 'trip',
    title: 'Trip',
    start: DateTime(2026, 11, 26),
    end: DateTime(2026, 11, 29),
    allDay: true,
  );

  test('a one-off event is linked by its id, an occurrence with its start', () {
    expect(timeItemId(dentist, dentist.start), 'dentist');
    final occurrence = DateTime(2026, 11, 23, 8);
    final id = timeItemId(standup, occurrence);
    expect(id, startsWith('standup|'));
    final back = parseTimeItemId(id);
    expect(back.eventId, 'standup');
    expect(back.occurrence, occurrence);
    expect(parseTimeItemId('dentist'), (eventId: 'dentist', occurrence: null));
  });

  test('a picked event goes to the channel with epoch milliseconds', () {
    final item = PickedItem(
      text: 'Dentist',
      id: 'dentist',
      title: 'Dentist',
      start: dentist.start,
      end: dentist.end,
    );
    expect(item.toChannel(), {
      'id': 'dentist',
      'title': 'Dentist',
      'startMs': dentist.start.millisecondsSinceEpoch,
      'endMs': dentist.end.millisecondsSinceEpoch,
    });
    // All day: no times, so ZT Time asks about a timer instead.
    expect(const PickedItem(text: 'Trip', id: 'trip', title: 'Trip').toChannel(), {
      'id': 'trip',
      'title': 'Trip',
    });
  });

  Future<Object? Function()> open(WidgetTester tester, {required bool wantItem}) async {
    Object? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [allEventsProvider.overrideWithValue(AsyncData([dentist, standup, trip]))],
        child: MaterialApp(
          theme: ZtTheme.light(accent: ZtTheme.accentFor(calendarAppConfig)),
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await Navigator.of(context).push<Object>(
                      MaterialPageRoute(
                        builder: (_) => PickForKeyboardPage(now: now, wantItem: wantItem),
                      ),
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

  testWidgets('ZT Time asking for an event gets it at the first tap', (tester) async {
    final picked = await open(tester, wantItem: true);
    await tester.tap(find.text('Dentist'));
    await tester.pumpAndSettle();
    final item = picked() as PickedItem;
    expect(item.id, 'dentist');
    expect(item.text, 'Dentist');
    expect(item.start, DateTime(2026, 11, 24, 10));
    expect(item.end, DateTime(2026, 11, 24, 11));
  });

  testWidgets('a repeating event goes with the occurrence tapped', (tester) async {
    final picked = await open(tester, wantItem: true);
    await tester.tap(find.text('Standup').first);
    await tester.pumpAndSettle();
    final item = picked() as PickedItem;
    expect(parseTimeItemId(item.id).occurrence, DateTime(2026, 11, 23, 8));
    expect(item.start, DateTime(2026, 11, 23, 8));
  });

  testWidgets('dates still answer with text only', (tester) async {
    final picked = await open(tester, wantItem: true);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(picked(), 'Sunday, November 22, 2026');
  });

  testWidgets('the keyboard still chooses what to type of an event', (tester) async {
    final picked = await open(tester, wantItem: false);
    await tester.tap(find.text('Dentist'));
    await tester.pumpAndSettle();
    expect(picked(), isNull);
    expect(find.text('Date and time'), findsOneWidget);
  });

  testWidgets('a ZT Time link to a subscribed calendar\'s event still opens it', (tester) async {
    final feed = CalendarEvent(
      id: 'feed:holidays:1',
      title: 'Holiday',
      start: DateTime(2026, 12, 25),
      end: DateTime(2026, 12, 26),
      allDay: true,
    );
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedEventsProvider.overrideWithValue([feed])],
        child: Consumer(builder: (_, ref, _) {
          widgetRef = ref;
          return const SizedBox();
        }),
      ),
    );
    expect(await linkedEventExists(widgetRef, feed.id), isTrue);
  });
}
