import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zt_scheduler/zt_scheduler.dart';

import '../data/calendar_store.dart';
import '../data/subscriptions.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../planner/planner_ai.dart';
import '../planner/planner_controller.dart';
import '../planner/planner_model.dart';
import '../util/format.dart';
import 'planner_habit_page.dart';
import 'planner_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// The AI helper's screens: its switches on the Planner page, "Ask the
/// Planner" with the suggested changes and their preview, and the length
/// guesses. All hidden unless the server says the helper is available.

/// The message for a failed request.
String plannerAiErrorText(AppL10n l, Object error) => switch (error) {
  PlannerAiException(code: 'off' || 'no_plan' || 'unauthorized') => l.plannerAiErrorOff,
  PlannerAiException(code: 'limit' || 'budget') => l.plannerAiErrorLimit,
  PlannerAiException(code: 'refused') => l.plannerAiErrorRefused,
  PlannerAiException(code: 'network') => l.plannerAiErrorNetwork,
  _ => l.plannerAiErrorOther,
};

/// Asks before a switch that sends data is turned on.
Future<bool> _consent(BuildContext context, String body) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(l.plannerAiConsentTitle),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(l.cancel)),
        TextButton(
          key: const ValueKey('planner-ai-consent'),
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(l.plannerAiSwitchOn),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The helper's switches and this month's use, on the Planner page.
class PlannerAiSection extends ConsumerWidget {
  const PlannerAiSection({super.key, required this.settings});
  final PlannerSettings settings;

  Future<void> _save(BuildContext context, WidgetRef ref, PlannerSettings next) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      // The switches don't change where anything goes: saved as they are,
      // without planning the week afresh.
      await ref.read(plannerWriterProvider).saveSettings(next);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(plannerAiStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final missing = [
      for (final t in ref.watch(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
        if (t.plannedUnder(settings.tasks) && t.minutes == null && t.title.trim().isNotEmpty) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            l.plannerAi,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l.plannerAiIntro,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('planner-ai-guess'),
          title: Text(l.plannerAiGuess),
          subtitle: Text(l.plannerAiGuessHint),
          value: settings.aiGuess,
          onChanged: (on) async {
            if (on && !await _consent(context, l.plannerAiConsentGuess)) return;
            if (context.mounted) await _save(context, ref, settings.copyWith(aiGuess: on));
          },
        ),
        if (settings.aiGuess && missing.isNotEmpty)
          ListTile(
            key: const ValueKey('planner-ai-guess-lengths'),
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(l.plannerAiGuessLengths),
            subtitle: Text(l.plannerAiGuessLengthsHint(missing.length)),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  PlannerAiGuessesDialog(tasks: missing.take(10).toList(), language: l.localeName),
            ),
          ),
        SwitchListTile(
          key: const ValueKey('planner-ai-requests'),
          title: Text(l.plannerAiRequests),
          subtitle: Text(l.plannerAiRequestsHint),
          value: settings.aiRequests,
          onChanged: (on) async {
            if (on && !await _consent(context, l.plannerAiConsentRequests)) return;
            if (context.mounted) await _save(context, ref, settings.copyWith(aiRequests: on));
          },
        ),
        if (settings.aiRequests)
          SwitchListTile(
            key: const ValueKey('planner-ai-hide-titles'),
            title: Text(l.plannerAiHideTitles),
            subtitle: Text(l.plannerAiHideTitlesHint),
            value: settings.aiHideTitles,
            onChanged: (on) => _save(context, ref, settings.copyWith(aiHideTitles: on)),
          ),
        if (status.limit > 0)
          Padding(
            key: const ValueKey('planner-ai-used'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              l.plannerAiUsed(status.used, status.limit),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// "Ask the Planner", near the top of the Planner page, when that switch
/// is on and the helper is available.
class PlannerAskButton extends ConsumerWidget {
  const PlannerAskButton({super.key, required this.settings});
  final PlannerSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!settings.aiRequests || ref.watch(plannerAiStatusProvider).value == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: FilledButton.tonalIcon(
        key: const ValueKey('planner-ask'),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PlannerAskPage())),
        icon: const Icon(Icons.auto_awesome),
        label: Text(context.l10n.plannerAiRequests),
      ),
    );
  }
}

/// One sentence in, the suggested changes out, each with a check box and
/// what they do to the plan. Nothing changes until Apply; then Undo.
class PlannerAskPage extends ConsumerStatefulWidget {
  const PlannerAskPage({super.key, this.now});

  /// The time to plan from; the clock when null (tests set it).
  final DateTime? now;

  @override
  ConsumerState<PlannerAskPage> createState() => _PlannerAskPageState();
}

class _PlannerAskPageState extends ConsumerState<PlannerAskPage> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  List<AiChange>? _changes;
  final _chosen = <int>{};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  DateTime get _now => widget.now ?? DateTime.now();

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    final l = context.l10n;
    final settings = ref.read(plannerSettingsProvider).value;
    final tasks = ref.read(plannerTasksProvider).value?.tasks;
    final events = ref.read(allEventsProvider).value;
    final calendars = ref.read(calendarsProvider).value ?? const <ZtCalendarInfo>[];
    if (settings == null || tasks == null || events == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _changes = null;
    });
    try {
      final request = buildAiRequest(
        text: text,
        now: _now,
        language: l.localeName,
        settings: settings,
        tasks: tasks,
        events: events,
        calendars: calendars,
        hideTitles: settings.aiHideTitles,
      );
      final changes = await askPlanner(
        ref.read(plannerAiBackendProvider),
        request,
        taskIds: {for (final t in request.body['tasks'] as List) (t as Map)['id'] as String},
        blockIds: {for (final b in request.body['blocks'] as List) (b as Map)['id'] as String},
      );
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _chosen
          ..clear()
          ..addAll([
            for (final (i, c) in changes.indexed)
              if (c.applies) i,
          ]);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = plannerAiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
      // The count went up.
      ref.invalidate(plannerAiStatusProvider);
    }
  }

  Future<void> _apply() async {
    final changes = _changes;
    if (changes == null) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final picked = [
      for (final (i, c) in changes.indexed)
        if (_chosen.contains(i)) c,
    ];
    setState(() => _busy = true);
    try {
      final undo = await ref
          .read(plannerAiApplierProvider)
          .apply(picked, busyTitle: l.plannerAiBusyTitle, now: _now);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.plannerAiApplied),
            duration: const Duration(seconds: 8),
            persist: false,
            action: SnackBarAction(
              label: l.undo,
              onPressed: () async {
                try {
                  await undo();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l.plannerAiUndone),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } on Object catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
                }
              },
            ),
          ),
        );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotSave('$e'))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final changes = _changes;
    final said = [
      for (final c in changes ?? const <AiChange>[])
        if (!c.applies) c,
    ];
    final settings = ref.watch(plannerSettingsProvider).value ?? const PlannerSettings();
    // Kept loaded: a request is built from them.
    final ready =
        ref.watch(plannerTasksProvider).hasValue &&
        ref.watch(allEventsProvider).hasValue &&
        ref.watch(calendarsProvider).hasValue;
    final picked = [
      for (final (i, c) in (changes ?? const <AiChange>[]).indexed)
        if (_chosen.contains(i)) c,
    ];
    // Recomputed on each tick: the plan with only the ticked changes.
    final preview = picked.isEmpty
        ? null
        : previewAiChanges(
            ref.read(plannerControllerProvider.notifier),
            settings,
            picked,
            now: _now,
          );
    return Scaffold(
      appBar: AppBar(title: Text(l.plannerAiRequests)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const ValueKey('planner-ask-text'),
              controller: _text,
              enabled: !_busy,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: l.plannerAiAskHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: const ValueKey('planner-ask-send'),
                onPressed: _busy || !ready ? null : _send,
                icon: const Icon(Icons.send),
                label: Text(l.plannerAiSend),
              ),
            ),
          ),
          if (_busy && changes == null)
            ListTile(
              leading: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(l.plannerAiThinking),
            ),
          if (_error != null)
            ListTile(
              key: const ValueKey('planner-ai-error'),
              leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: Text(_error!),
            ),
          if (changes != null && changes.isEmpty)
            ListTile(
              key: const ValueKey('planner-ai-nothing'),
              leading: const Icon(Icons.info_outline),
              title: Text(l.plannerAiNoChanges),
            ),
          for (final c in said)
            ListTile(
              key: ValueKey('planner-ai-${c.type.wire}'),
              leading: Icon(c.type == AiChangeType.ask ? Icons.help_outline : Icons.block),
              title: Text(c.type == AiChangeType.ask ? l.plannerAiQuestion : l.plannerAiCannot),
              subtitle: Text(c.text ?? ''),
            ),
          if (changes != null && changes.any((c) => c.applies)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                l.plannerAiChanges,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            for (final (i, c) in changes.indexed)
              if (c.applies)
                CheckboxListTile(
                  key: ValueKey('planner-ai-change-$i'),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _chosen.contains(i),
                  onChanged: _busy
                      ? null
                      : (on) => setState(() => on == true ? _chosen.add(i) : _chosen.remove(i)),
                  title: Text(describeAiChange(context, ref, c, now: _now)),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                preview == null
                    ? l.plannerAiCheckHint
                    : preview.same
                    ? l.plannerAiPreviewSame
                    : l.plannerAiPreview(preview.moved, preview.added, preview.removed),
                key: const ValueKey('planner-ai-preview'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l.plannerAiCheckHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  key: const ValueKey('planner-ai-apply'),
                  onPressed: _busy || picked.isEmpty ? null : _apply,
                  child: Text(l.plannerAiApply),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One change in words, with the titles and times as they are on this
/// phone.
String describeAiChange(BuildContext context, WidgetRef ref, AiChange c, {DateTime? now}) {
  final l = context.l10n;
  final tasks = ref.read(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[];
  final blocks = ref.read(plannerBlocksProvider);
  String task() {
    final t = tasks.where((t) => t.id == c.taskId).firstOrNull;
    return t == null || t.title.isEmpty ? l.noTitle : t.title;
  }

  CalendarEvent? block() => blocks.where((b) => b.id == c.blockId).firstOrNull;
  String blockTitle() {
    final b = block();
    return b == null || b.title.isEmpty ? l.noTitle : b.title;
  }

  String when(DateTime s, DateTime e) =>
      '${relativeDay(s, now: now)}, ${formatSpan(context, s, e, false)}';
  String blockWhen() {
    final b = block();
    return b == null ? '' : when(b.start, b.end);
  }

  String weekday(int d) => DateFormat.EEEE(l.localeName).format(DateTime(2026, 11, 15 + d));
  String hoursName(String? id) =>
      id == personalHoursId ? l.plannerPersonalHours : l.plannerWorkHours;

  return switch (c.type) {
    AiChangeType.setLength => l.plannerAiSetLength(task(), formatPlanMinutes(l, c.minutes!)),
    AiChangeType.setPriority => l.plannerAiSetPriority(task(), switch (c.priority) {
      PlanPriority.high || PlanPriority.critical => l.plannerAiPriorityHigh,
      PlanPriority.low => l.plannerAiPriorityLow,
      _ => l.plannerAiPriorityMedium,
    }),
    AiChangeType.setDue => l.plannerAiSetDue(task(), relativeDay(c.date!, now: now)),
    AiChangeType.notBefore => l.plannerAiNotBefore(task(), relativeDay(c.date!, now: now)),
    AiChangeType.lock => l.plannerAiLock(blockTitle(), blockWhen()),
    AiChangeType.unlock => l.plannerAiUnlock(blockTitle(), blockWhen()),
    AiChangeType.markDone => l.plannerAiMarkDone(blockTitle(), blockWhen()),
    AiChangeType.blockOut => l.plannerAiBlockOut(
      when(c.start!, c.end!),
      c.title ?? l.plannerAiBusyTitle,
    ),
    AiChangeType.setHours =>
      c.from == 0 && c.to == 0
          ? l.plannerAiNoHours(hoursName(c.hours), weekday(c.weekday!))
          : l.plannerAiSetHours(
              hoursName(c.hours),
              weekday(c.weekday!),
              formatMinuteOfDay(context, c.from!),
              formatMinuteOfDay(context, c.to == 0 ? 0 : c.to!),
            ),
    AiChangeType.addHabit => l.plannerAiAddHabit(
      c.title!,
      describeHabit(
        context,
        PlannerHabit(
          id: '',
          title: c.title!,
          minutes: c.minutes!,
          days: c.days!,
          ideal: c.from!,
          earliest: 0,
          latest: 24 * 60,
        ),
      ),
    ),
    AiChangeType.ask || AiChangeType.cannot => c.text ?? '',
  };
}

/// Guesses the length of up to ten planned tasks that have none, one after
/// the other, then lets the person pick which to keep.
class PlannerAiGuessesDialog extends ConsumerStatefulWidget {
  const PlannerAiGuessesDialog({super.key, required this.tasks, required this.language});
  final List<PlannerTask> tasks;

  /// The app's language (`en` or `he`), for the helper.
  final String language;

  @override
  ConsumerState<PlannerAiGuessesDialog> createState() => _PlannerAiGuessesDialogState();
}

class _PlannerAiGuessesDialogState extends ConsumerState<PlannerAiGuessesDialog> {
  final _guesses = <String, int>{};
  final _chosen = <String>{};
  String? _error;
  bool _done = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final backend = ref.read(plannerAiBackendProvider);
    final settings = ref.read(plannerSettingsProvider).value ?? const PlannerSettings();
    for (final t in widget.tasks) {
      try {
        final g = await guessTaskLength(
          backend,
          title: t.title,
          language: widget.language,
          usualMinutes: settings.defaultMinutes,
        );
        if (!mounted) return;
        setState(() {
          _guesses[t.id] = g.minutes;
          _chosen.add(t.id);
        });
      } on Object catch (e) {
        if (!mounted) return;
        setState(() => _error = plannerAiErrorText(context.l10n, e));
        // The limit or a missing connection stops the rest too.
        if (e is PlannerAiException && e.code != 'no_answer' && e.code != 'refused') break;
      }
    }
    ref.invalidate(plannerAiStatusProvider);
    if (mounted) setState(() => _done = true);
  }

  Future<void> _save() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final write = ref.read(plannerTaskWriterProvider);
    try {
      for (final id in _chosen) {
        await write(id, {'planMinutes': _guesses[id]});
      }
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotUpdateTask('$e'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.plannerAiGuessesTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in widget.tasks)
              if (_guesses[t.id] case final minutes?)
                CheckboxListTile(
                  key: ValueKey('planner-ai-guess-${t.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: _chosen.contains(t.id),
                  onChanged: (on) =>
                      setState(() => on == true ? _chosen.add(t.id) : _chosen.remove(t.id)),
                  title: Text(t.title),
                  subtitle: Text(formatPlanMinutes(l, minutes)),
                ),
            if (!_done)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        TextButton(
          key: const ValueKey('planner-ai-guesses-apply'),
          onPressed: !_done || _saving || _chosen.isEmpty ? null : _save,
          child: Text(l.plannerAiApply),
        ),
      ],
    );
  }
}
