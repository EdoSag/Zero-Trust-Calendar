import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../reminders/reminders.dart';
import '../util/format.dart';
import '../util/quick_add.dart';
import 'event_editor_page.dart';
import 'inline_button_style.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Type an event ("Lunch with Dana Fri 1pm") or a ZT Tasks task ("Pay rent
/// on the 1st"); see what it means before adding it.
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

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  QuickAdd _parse() {
    final settings = ref.read(calendarSettingsProvider);
    final locale = Localizations.localeOf(context);
    return parseQuickAdd(
      _text.text,
      now: DateTime.now(),
      defaultMinutes: settings.defaultDuration,
      // Only the US (and a few others) write month first.
      dayFirst: !{'US', 'PH', 'FM', 'MH', 'PW'}.contains(locale.countryCode),
    );
  }

  CalendarEvent _event(QuickAdd q) {
    final settings = ref.read(calendarSettingsProvider);
    final reminder = q.allDay ? settings.defaultAllDayReminder : settings.defaultReminder;
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
            onChanged: (_) => setState(() {}),
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
                ].join('\n'),
              ),
            ),
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
