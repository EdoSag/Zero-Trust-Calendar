import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/planner/planner_ai.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/ui/find_task_time_page.dart';
import 'package:zerotrust_calendar/ui/planner_ai_widgets.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';

import 'planner_ai_test.dart' show FakeAiBackend, allDayHours, change;
import 'planner_support.dart';

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// A home screen with a button that opens [page], so the page can close.
Widget host(Widget page) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
        child: const Text('open'),
      ),
    ),
  ),
);

final on = PlannerSettings(enabled: true, hours: allDayHours, tasks: PlannerTasksChoice.all);

PlannerTask task(String id, String title, {int? minutes = 60}) =>
    PlannerTask(id: id, title: title, minutes: minutes, createdAt: id);

void main() {
  testWidgets('the AI helper stays hidden until the server says it is on', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(available: false);
    final account = FakeAccount(settings: on);
    await tester.pumpWidget(
      account.app(const PlannerPage(), more: [plannerAiBackendProvider.overrideWithValue(ai)]),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Settings'), 300);
    expect(find.text('AI helper'), findsNothing);
    expect(find.byKey(const ValueKey('planner-ask')), findsNothing);
  });

  testWidgets('switching a part of the helper on says what is sent first', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend();
    final account = FakeAccount(settings: on);
    await tester.pumpWidget(
      account.app(const PlannerPage(), more: [plannerAiBackendProvider.overrideWithValue(ai)]),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final header = find.text('AI helper');
    await tester.scrollUntilVisible(header, 200);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('planner-ai-used')), 200);
    await tester.pumpAndSettle();
    // Before the settings, and above them on the screen.
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('planner-ai-used'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Settings')).dy),
    );
    expect(find.text('Used this month: 12 of 300'), findsOneWidget);
    expect(find.byKey(const ValueKey('planner-ai-hide-titles')), findsNothing);

    // Cancel: nothing is saved.
    await tester.ensureVisible(find.byKey(const ValueKey('planner-ai-requests')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-ai-requests')));
    await tester.pumpAndSettle();
    expect(find.text('Send this to the AI helper?'), findsOneWidget);
    expect(find.textContaining("Anthropic's Claude"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(account.settings.aiRequests, isFalse);

    await tester.tap(find.byKey(const ValueKey('planner-ai-requests')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-ai-consent')));
    await tester.pumpAndSettle();
    expect(account.settings.aiRequests, isTrue);
    expect(account.settings.aiGuess, isFalse);
    expect(find.byKey(const ValueKey('planner-ai-hide-titles')), findsOneWidget);
    // Nothing was sent to the helper by switching it on.
    expect(ai.sent, isEmpty);

    // "Ask the Planner" now sits under the week.
    await tester.scrollUntilVisible(find.text('Next 7 days'), -300);
    await tester.pumpAndSettle();
    final ask = find.byKey(const ValueKey('planner-ask'));
    expect(ask, findsOneWidget);
    expect(tester.getTopLeft(ask).dy, greaterThan(tester.getTopLeft(find.text('Next 7 days')).dy));
  });

  testWidgets('Ask the Planner: changes are shown with checks, applied, and undone', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(
      answer: {
        'changes': [
          change('set_length', {'taskId': 'a', 'minutes': 180}),
          change('cannot', {'reason': "I can't invite people."}),
        ],
      },
    );
    final account = FakeAccount(
      settings: on.copyWith(aiRequests: true),
      tasks: [task('a', 'Write report')],
    );
    await tester.pumpWidget(
      account.app(
        host(const PlannerAskPage()),
        more: [plannerAiBackendProvider.overrideWithValue(ai)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-ask-text')),
      'The report takes 3 hours, and invite Dana',
    );
    await tester.tap(find.byKey(const ValueKey('planner-ask-send')));
    await tester.pumpAndSettle();

    expect(ai.sent.single['text'], 'The report takes 3 hours, and invite Dana');
    expect(account.tasks.single.minutes, 60, reason: 'nothing applied yet');
    final tile = find.byKey(const ValueKey('planner-ai-change-0'));
    expect(
      find.descendant(of: tile, matching: find.textContaining('Write report: takes')),
      findsOneWidget,
    );
    final cannot = find.byKey(const ValueKey('planner-ai-cannot'));
    expect(find.text("I can't invite people."), findsOneWidget);
    final apply = find.byKey(const ValueKey('planner-ai-apply'));
    final preview = find.byKey(const ValueKey('planner-ai-preview'));
    // The sentence, what can't be done, the changes, what they do, Apply.
    final field = tester.getBottomLeft(find.byKey(const ValueKey('planner-ask-text'))).dy;
    expect(tester.getTopLeft(cannot).dy, greaterThan(field));
    expect(tester.getTopLeft(tile).dy, greaterThan(tester.getBottomLeft(cannot).dy));
    expect(tester.getTopLeft(preview).dy, greaterThan(tester.getBottomLeft(tile).dy));
    expect(tester.getTopLeft(apply).dy, greaterThan(tester.getBottomLeft(preview).dy));

    // Unticked: nothing to apply.
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: 'back where it was opened');
    expect(account.tasks.single.minutes, 180);
    expect(find.text('Changes applied'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(account.tasks.single.minutes, 60);
  });

  testWidgets('a question from the helper is shown, with nothing to apply', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(
      answer: {
        'changes': [
          change('ask', {'question': 'This week or next?'}),
        ],
      },
    );
    final account = FakeAccount(settings: on.copyWith(aiRequests: true), tasks: [task('a', 'A')]);
    await tester.pumpWidget(
      account.app(
        host(const PlannerAskPage()),
        more: [plannerAiBackendProvider.overrideWithValue(ai)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('planner-ask-text')), 'Move it');
    await tester.tap(find.byKey(const ValueKey('planner-ask-send')));
    await tester.pumpAndSettle();
    expect(find.text('This week or next?'), findsOneWidget);
    expect(find.byKey(const ValueKey('planner-ai-apply')), findsNothing);
  });

  testWidgets('the limit is explained, not shown as an error code', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(error: const PlannerAiException('limit'));
    final account = FakeAccount(settings: on.copyWith(aiRequests: true), tasks: [task('a', 'A')]);
    await tester.pumpWidget(
      account.app(
        host(const PlannerAskPage()),
        more: [plannerAiBackendProvider.overrideWithValue(ai)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('planner-ask-text')), 'Move it');
    await tester.tap(find.byKey(const ValueKey('planner-ask-send')));
    await tester.pumpAndSettle();
    expect(find.text("You've used this month's AI requests."), findsOneWidget);
  });

  testWidgets('Ask the Planner reads right to left in Hebrew', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(
      answer: {
        'changes': [
          change('set_length', {'taskId': 'a', 'minutes': 120}),
        ],
      },
    );
    final account = FakeAccount(
      settings: on.copyWith(aiRequests: true),
      tasks: [task('a', 'לכתוב דוח')],
    );
    await tester.pumpWidget(
      account.app(
        host(const PlannerAskPage()),
        locale: const Locale('he'),
        more: [plannerAiBackendProvider.overrideWithValue(ai)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('לבקש מהמתכנן'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('planner-ask-text')), 'הדוח לוקח שעתיים');
    await tester.tap(find.byKey(const ValueKey('planner-ask-send')));
    await tester.pumpAndSettle();
    expect(ai.sent.single['lang'], 'he');
    expect(find.textContaining('לכתוב דוח: לוקחת'), findsOneWidget);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // The buttons take the whole line (the app's buttons do), inside the
    // page's margins.
    for (final key in ['planner-ask-send', 'planner-ai-apply']) {
      final r = tester.getRect(find.byKey(ValueKey(key)));
      expect(r.left, inInclusiveRange(8, 24));
      expect(r.right, inInclusiveRange(width - 24, width - 8));
    }
    // The check box is at the start, the right.
    expect(tester.getCenter(find.byType(Checkbox)).dx, greaterThan(width / 2));
  });

  testWidgets('Find a time offers a length guess only when switched on', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(
      answer: {
        'guess': {'minutes': 90, 'confidence': 'medium'},
      },
    );
    final account = FakeAccount(
      settings: on.copyWith(aiGuess: true),
      tasks: [task('a', 'Prepare tax papers', minutes: null)],
    );
    await tester.pumpWidget(
      account.app(const FindTaskTimePage(), more: [plannerAiBackendProvider.overrideWithValue(ai)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('find-time-task-a')));
    await tester.pumpAndSettle();
    final length = find.byKey(const ValueKey('find-time-length'));
    final guess = find.byKey(const ValueKey('find-time-guess'));
    expect(guess, findsOneWidget);
    expect(tester.getTopLeft(guess).dy, greaterThanOrEqualTo(tester.getBottomLeft(length).dy));
    String shown() =>
        tester.widget<Text>(find.descendant(of: length, matching: find.byType(Text)).last).data!;
    final before = shown();
    await tester.tap(guess);
    await tester.pumpAndSettle();
    expect(ai.sent.single['title'], 'Prepare tax papers');
    expect(shown(), isNot(before));
    expect(find.textContaining('Guessed:'), findsOneWidget);
  });

  testWidgets('no guess button with the switch off', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend();
    final account = FakeAccount(settings: on, tasks: [task('a', 'A', minutes: null)]);
    await tester.pumpWidget(
      account.app(const FindTaskTimePage(), more: [plannerAiBackendProvider.overrideWithValue(ai)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('find-time-task-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-time-guess')), findsNothing);
  });

  testWidgets('missing lengths are guessed together and kept only when ticked', (tester) async {
    usePhoneScreen(tester);
    final ai = FakeAiBackend(
      answer: {
        'guess': {'minutes': 45, 'confidence': 'high'},
      },
    );
    final account = FakeAccount(
      settings: on.copyWith(aiGuess: true),
      tasks: [task('a', 'Call the bank', minutes: null), task('b', 'Has one', minutes: 30)],
    );
    await tester.pumpWidget(
      account.app(const PlannerPage(), more: [plannerAiBackendProvider.overrideWithValue(ai)]),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('planner-ai-guess-lengths'));
    await tester.scrollUntilVisible(entry, 300);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(ai.sent, hasLength(1), reason: 'only the task without a length');
    await tester.tap(find.byKey(const ValueKey('planner-ai-guesses-apply')));
    await tester.pumpAndSettle();
    expect(account.tasks.firstWhere((t) => t.id == 'a').minutes, 45);
    expect(account.tasks.firstWhere((t) => t.id == 'b').minutes, 30);
  });
}
