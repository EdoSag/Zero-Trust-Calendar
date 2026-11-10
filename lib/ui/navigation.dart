import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/entries.dart';
import '../data/event_actions.dart';
import '../data/linked_apps.dart';
import '../model/linked_items.dart';
import '../util/format.dart';
import 'event_details_page.dart';
import 'event_editor_page.dart';
import 'linked_app_launcher.dart';

/// The day the calendar is showing (the first day of the visible range).
final focusedDayProvider = NotifierProvider<FocusedDay, DateTime>(FocusedDay.new);

class FocusedDay extends Notifier<DateTime> {
  @override
  DateTime build() => dayOf(DateTime.now());

  void set(DateTime day) => state = dayOf(day);
  void today() => state = dayOf(DateTime.now());
}

/// The week start the user picked, or the locale's.
int weekStartOf(BuildContext context, CalendarSettings settings) =>
    settings.weekStart ?? localeWeekStart(context);

/// Opens what a tap on [entry] should open: the event, the task in ZT
/// Tasks, or the contact's birthday card.
Future<void> openEntry(BuildContext context, WidgetRef ref, CalendarEntry entry) async {
  switch (entry.kind) {
    case EntryKind.event:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailsPage(
            eventId: entry.event!.id,
            occurrenceStart: entry.start,
          ),
        ),
      );
    case EntryKind.task:
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.task_alt, color: Color(taskColor)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: Theme.of(sheet).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Due ${relativeDay(entry.start)}'
                  '${entry.allDay ? '' : ', ${formatTime(sheet, entry.start)}'}',
                ),
                const SizedBox(height: 8),
                if (entry.task!.repeats)
                  Text(
                    'A repeating task: tick it off in ZT Tasks, which moves it to its next date.',
                    style: Theme.of(sheet).textTheme.bodySmall,
                  )
                else
                  _TaskDoneTile(task: entry.task!),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    openLinkedApp(LinkedApp.tasks);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open ZT Tasks'),
                ),
              ],
            ),
          ),
        ),
      );
    case EntryKind.birthday:
      final contact = entry.contact!;
      final year = contact.birthdays
          .where((b) => b.$1 == entry.start.month && b.$2 == entry.start.day)
          .map((b) => b.$3)
          .firstWhere((y) => y != null, orElse: () => null);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cake_outlined, color: Color(birthdayColor)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: Theme.of(sheet).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    formatLongDay(entry.start),
                    if (year != null) 'turns ${entry.start.year - year}',
                  ].join(', '),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (contact.phones.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: contact.phones.first),
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Call'),
                      ),
                    if (contact.phones.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () => launchUrl(
                          Uri(scheme: 'sms', path: contact.phones.first),
                        ),
                        icon: const Icon(Icons.sms_outlined),
                        label: const Text('Message'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        openLinkedApp(LinkedApp.contacts);
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('ZT Contacts'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }
}

/// Ticks a ZT Tasks task off from the calendar.
class _TaskDoneTile extends ConsumerStatefulWidget {
  const _TaskDoneTile({required this.task});
  final LinkedTask task;

  @override
  ConsumerState<_TaskDoneTile> createState() => _TaskDoneTileState();
}

class _TaskDoneTileState extends ConsumerState<_TaskDoneTile> {
  late bool _done = widget.task.completed;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: _done,
    title: const Text('Done'),
    subtitle: const Text('Saved in ZT Tasks on all your devices'),
    onChanged: _busy
        ? null
        : (v) async {
            final messenger = ScaffoldMessenger.of(context);
            setState(() {
              _busy = true;
              _done = v == true;
            });
            try {
              final mirror = await ref.read(linkedMirrorProvider(LinkedApp.tasks).future);
              await mirror.setTaskCompleted(widget.task.id, v == true);
            } on Object catch (e) {
              setState(() => _done = widget.task.completed);
              messenger.showSnackBar(SnackBar(content: Text('Could not update the task: $e')));
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}

/// Saves [entry]'s event at its new [start] and [end] (a drag in the day
/// or week view). For a repeating event, asks which occurrences move.
Future<void> moveEntry(
  BuildContext context,
  WidgetRef ref,
  CalendarEntry entry,
  DateTime start,
  DateTime end,
) async {
  final event = entry.event;
  if (event == null || event.readOnly) return;
  final repo = ref.read(calendarRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (event.repeats) {
      final scope = await askSeriesScope(context, action: 'Move');
      if (scope == null) return;
      await repo.apply(
        SeriesEdits.edit(
          series: event,
          occurrence: entry.start,
          edited: event.copyWith(start: start, end: end),
          scope: scope,
          exceptions: await repo.exceptionsOf(event.id),
        ),
      );
      return;
    }
    await repo.saveEvent(event.copyWith(start: start, end: end));
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Moved to ${formatDay(start)}, ${formatTime(context, start)}'),
        // Flutter keeps a snackbar with an action open until it is tapped.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.saveEvent(event).ignore(),
        ),
      ),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not move it: $e')));
  }
}

/// Opens the editor for a new event starting at [start] (or the next full
/// hour on the focused day).
Future<void> createEvent(
  BuildContext context, {
  DateTime? start,
  bool allDay = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => EventEditorPage(initialStart: start, initialAllDay: allDay),
  ),
);
