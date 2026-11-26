import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zt_assist/zt_assist.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../reminders/reminders.dart';
import '../util/format.dart';
import '../util/quick_add.dart';
import '../util/quick_add_assist.dart';
import 'event_editor_page.dart';
import 'inline_button_style.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Type an event ("Lunch with Dana Fri 1pm") or a ZT Tasks task ("Pay rent
/// on the 1st"); see what it means before adding it.
///
/// With ZT Assist on the same phone, "Read with ZT Assist" has its model
/// read the line too: free wording ("half past four in the afternoon",
/// "remind me an hour before") and a cleaner title. The text goes to
/// ZT Assist on the phone and nowhere else, and what it read is shown
/// before anything is added.
Future<void> showQuickAdd(BuildContext context, {bool task = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickAddSheet(task: task),
    );

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({required this.task});
  final bool task;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _text = TextEditingController();
  late bool _task = widget.task;
  bool _saving = false;

  /// Whether ZT Assist is on this phone: its button is offered only then.
  bool _assistHere = false;

  /// The request ZT Assist is answering, if any.
  StreamSubscription<ZtAssistEvent>? _asking;

  /// What ZT Assist read, and the text it read it from. Typing anything
  /// else drops it.
  ZtAssistQuickAdd? _assistRead;
  String _assistText = '';

  /// Why ZT Assist's reading did not arrive, in words.
  String? _assistProblem;

  @override
  void initState() {
    super.initState();
    unawaited(_lookForAssist());
  }

  @override
  void dispose() {
    // Leaving stops the model.
    unawaited(_asking?.cancel());
    _text.dispose();
    super.dispose();
  }

  Future<void> _lookForAssist() async {
    bool here;
    try {
      here = await ZtAssist.instance.isInstalled();
    } on Object {
      here = false;
    }
    if (mounted && here) setState(() => _assistHere = true);
  }

  bool get _assistReadIsCurrent => _assistRead != null && _assistText == _text.text;

  QuickAdd _parse() {
    final settings = ref.read(calendarSettingsProvider);
    final locale = Localizations.localeOf(context);
    final now = DateTime.now();
    final own = parseQuickAdd(
      _text.text,
      now: now,
      defaultMinutes: settings.defaultDuration,
      // Only the US (and a few others) write month first.
      dayFirst: !{'US', 'PH', 'FM', 'MH', 'PW'}.contains(locale.countryCode),
    );
    return _assistReadIsCurrent
        ? mergeAssistReading(own, _assistRead!, now: now, defaultMinutes: settings.defaultDuration)
        : own;
  }

  void _onTextChanged() {
    if (_text.text != _assistText || _asking != null) {
      // What ZT Assist read, or is reading, is of another text now.
      unawaited(_asking?.cancel());
      _asking = null;
      _assistRead = null;
      _assistProblem = null;
    }
    setState(() {});
  }

  void _askAssist() {
    final asked = _text.text;
    final line = asked.trim();
    if (line.isEmpty || _asking != null) return;
    final answer = StringBuffer();
    setState(() {
      _assistRead = null;
      _assistProblem = null;
      _asking = ZtAssist.instance
          .ask(ZtAssistRequest(task: ZtAssistTask.quickAdd, text: line))
          .listen(
            (event) {
              if (event is ZtAssistChunk) answer.write(event.text);
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _asking = null;
                _assistProblem = _assistProblemText(error);
              });
            },
            onDone: () {
              // Already ended by an error, or by leaving.
              if (!mounted || _asking == null) return;
              final read = ZtAssistQuickAdd.fromAnswer(
                answer.toString(),
                text: line,
                now: DateTime.now(),
              );
              setState(() {
                _asking = null;
                if (read == null) {
                  _assistProblem = currentL10n.quickAddAssistNotUnderstood;
                } else {
                  _assistRead = read;
                  _assistText = asked;
                }
              });
            },
          );
    });
  }

  void _stopAssist() {
    unawaited(_asking?.cancel());
    setState(() => _asking = null);
  }

  static String _assistProblemText(Object error) {
    final l = currentL10n;
    if (error is! ZtAssistException) return l.assistFailed;
    return switch (error.error) {
      ZtAssistError.notInstalled => l.assistNotInstalled,
      ZtAssistError.noModel => l.assistNoModel,
      ZtAssistError.loadFailed => l.assistLoadFailed,
      ZtAssistError.needsUpdate => l.assistNeedsUpdate,
      ZtAssistError.stopped => l.assistStopped,
      ZtAssistError.failed => l.assistFailed,
    };
  }

  /// ZT Assist's part of the sheet: the button that asks, the wait, and
  /// the line that says the reading above is ZT Assist's.
  Widget _assistRow(ThemeData theme) {
    final small = theme.textTheme.bodySmall;
    if (_asking != null) {
      return Row(
        key: const ValueKey('quick-add-assist-reading'),
        children: [
          const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(child: Text(context.l10n.quickAddAssistReading, style: small)),
          TextButton(
            key: const ValueKey('quick-add-assist-stop'),
            onPressed: _stopAssist,
            child: Text(context.l10n.assistStop),
          ),
        ],
      );
    }
    if (_assistReadIsCurrent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          key: const ValueKey('quick-add-assist-read'),
          children: [
            Icon(Icons.auto_awesome_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(context.l10n.quickAddAssistRead, style: small)),
          ],
        ),
      );
    }
    final problem = _assistProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          key: const ValueKey('quick-add-assist'),
          onPressed: _saving ? null : _askAssist,
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(context.l10n.quickAddAssist),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              problem,
              key: const ValueKey('quick-add-assist-problem'),
              style: small?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  CalendarEvent _event(QuickAdd q) {
    final settings = ref.read(calendarSettingsProvider);
    // "Remind me an hour before" counts back from a start time; an all-day
    // event keeps the default.
    final reminder = q.allDay
        ? settings.defaultAllDayReminder
        : q.remindMinutesBefore ?? settings.defaultReminder;
    return CalendarEvent(
      id: const Uuid().v4(),
      title: q.title,
      start: q.start,
      end: q.end,
      allDay: q.allDay,
      location: q.location ?? '',
      rrule: q.rule?.toString(),
      reminders: [?reminder],
    );
  }

  Future<void> _add() async {
    final q = _parse();
    if (q.title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_task) {
        final mirror = await ref.read(linkedMirrorProvider(LinkedApp.tasks).future);
        await mirror.create(
          LinkedTask.newTaskJson(
            title: q.title,
            due: q.start,
            hasTime: q.hasTime,
            now: DateTime.now(),
          ),
        );
        messenger.showSnackBar(SnackBar(content: Text(currentL10n.taskAddedToZtTasks)));
      } else {
        final e = _event(q);
        await ref.read(calendarRepositoryProvider).saveEvent(e);
        if (e.reminders.isNotEmpty) {
          await ref.read(reminderSchedulerProvider).requestPermission();
        }
        messenger.showSnackBar(SnackBar(content: Text(currentL10n.addedTitle(e.title))));
      }
      navigator.pop();
    } on Object catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(currentL10n.couldNotAddIt('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _parse();
    final theme = Theme.of(context);
    final when = q.allDay
        ? '${formatLongDay(q.start)}${_task ? '' : ', ${context.l10n.allDayLower}'}'
        : '${formatLongDay(q.start)}, ${formatSpan(context, q.start, _task ? q.start : q.end, false)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(context.l10n.event), icon: Icon(Icons.event)),
              ButtonSegment(value: true, label: Text(context.l10n.task), icon: Icon(Icons.task_alt)),
            ],
            selected: {_task},
            onSelectionChanged: (v) => setState(() => _task = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _onTextChanged(),
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _task ? context.l10n.payRentFriday : context.l10n.lunchWithDanaFri1pm,
              helperText: _task
                  ? context.l10n.addedToZtTasksWith
                  : context.l10n.tryDentistTomorrow930,
            ),
          ),
          const SizedBox(height: 12),
          if (_text.text.trim().isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_task ? Icons.task_alt : Icons.event),
              title: Text(q.title.isEmpty ? context.l10n.addATitle : q.title),
              subtitle: Text(
                [
                  if (_task) context.l10n.dueAt(when) else when,
                  if (q.rule != null && !_task) describeRule(q.rule, q.start),
                  if (q.location != null && !_task) q.location!,
                  if (q.remindMinutesBefore != null && !q.allDay && !_task)
                    context.l10n.reminderIs(reminderLabel(q.remindMinutesBefore!)),
                ].join('\n'),
              ),
            ),
          if (_assistHere && _text.text.trim().isNotEmpty) _assistRow(theme),
          Row(
            children: [
              if (!_task)
                TextButton(
                  onPressed: () {
                    final draft = _event(q);
                    final navigator = Navigator.of(context)..pop();
                    navigator.push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => EventEditorPage(
                          draft: draft,
                          initialAllDay: draft.allDay,
                        ),
                      ),
                    );
                  },
                  child: Text(context.l10n.moreOptions),
                ),
              const Spacer(),
              FilledButton(
                style: inlineButtonStyle,
                onPressed: q.title.isEmpty || _saving ? null : _add,
                child: Text(_task ? context.l10n.addTask : context.l10n.add),
              ),
            ],
          ),
          if (_task)
            Text(
              context.l10n.savedInZtTasksEncrypted,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
