import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import '../data/linked_apps.dart';
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
                const SizedBox(height: 4),
                Text(
                  'From ZT Tasks. Edit or complete it there.',
                  style: Theme.of(sheet).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
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
