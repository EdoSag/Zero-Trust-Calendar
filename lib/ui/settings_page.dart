import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../ics/ics.dart';
import '../ics/import_service.dart';
import '../reminders/reminders.dart';
import '../util/format.dart';
import 'calendars_page.dart';

/// The shared Zero-Trust settings screen, with Calendar's own rows.
class CalendarSettingsPage extends ConsumerWidget {
  const CalendarSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(calendarSettingsProvider);
    final ctrl = ref.read(calendarSettingsProvider.notifier);
    final weekStart = s.weekStart;

    return ZtSettingsPage(
      showSyncStatus: true,
      onSignedOut: () async {
        await ref.read(reminderSchedulerProvider).cancelAll();
        if (context.mounted) {
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
        }
      },
      onOpenUrl: (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication),
      appSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.edit_calendar_outlined),
          title: const Text('Calendars'),
          subtitle: const Text('Add, rename, recolour or hide'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CalendarsPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.first_page),
          title: const Text('Start of the week'),
          subtitle: Text(
            weekStart == null
                ? 'Like your region (${DateFormat.EEEE().format(DateTime(2024, 1, localeWeekStart(context)))})'
                : DateFormat.EEEE().format(DateTime(2024, 1, weekStart)),
          ),
          onTap: () async {
            final picked = await showDialog<int>(
              context: context,
              builder: (d) => SimpleDialog(
                title: const Text('Start of the week'),
                children: [
                  for (final v in [0, DateTime.saturday, DateTime.sunday, DateTime.monday])
                    SimpleDialogOption(
                      onPressed: () => Navigator.of(d).pop(v),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          v == 0 ? 'Like your region' : DateFormat.EEEE().format(DateTime(2024, 1, v)),
                        ),
                      ),
                    ),
                ],
              ),
            );
            if (picked != null) {
              await ctrl.update((x) => x.copyWith(weekStart: picked == 0 ? null : picked));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.timelapse),
          title: const Text('Default event length'),
          subtitle: Text(_minutesLabel(s.defaultDuration)),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              'Default event length',
              const [15, 30, 45, 60, 90, 120],
              _minutesLabel,
            );
            if (picked != null) await ctrl.update((x) => x.copyWith(defaultDuration: picked));
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Default reminder'),
          subtitle: Text(s.defaultReminder == null ? 'None' : reminderLabel(s.defaultReminder!)),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              'Default reminder',
              const [-1, 0, 5, 10, 15, 30, 60, 24 * 60],
              (m) => m < 0 ? 'None' : reminderLabel(m),
            );
            if (picked != null) {
              await ctrl.update((x) => x.copyWith(defaultReminder: picked < 0 ? null : picked));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_none),
          title: const Text('Default all-day reminder'),
          subtitle: Text(
            s.defaultAllDayReminder == null
                ? 'None'
                : reminderLabel(s.defaultAllDayReminder!, allDay: true),
          ),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              'Default all-day reminder',
              const [-1, 0, 24 * 60, 2 * 24 * 60, 7 * 24 * 60],
              (m) => m < 0 ? 'None' : reminderLabel(m, allDay: true),
            );
            if (picked != null) {
              await ctrl.update(
                (x) => x.copyWith(defaultAllDayReminder: picked < 0 ? null : picked),
              );
            }
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.title),
          title: const Text('Event titles in reminders'),
          subtitle: const Text(
            'Off: reminders only say "Event". Titles are handed to the '
            'phone so they can show while Calendar is locked.',
          ),
          value: s.notificationTitles,
          onChanged: (v) => ctrl.update((x) => x.copyWith(notificationTitles: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.widgets_outlined),
          title: const Text('Event titles on the home-screen widget'),
          subtitle: const Text(
            'Off: the "Up next" widget shows only times. Titles shown there '
            'are stored unencrypted for the home screen.',
          ),
          value: s.widgetTitles,
          onChanged: (v) => ctrl.update((x) => x.copyWith(widgetTitles: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.task_alt),
          title: const Text('Show tasks from ZT Tasks'),
          subtitle: const Text('Tasks with a due date, read-only'),
          value: s.showTasks,
          onChanged: (v) => ctrl.update((x) => x.copyWith(showTasks: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.cake_outlined),
          title: const Text('Show birthdays from ZT Contacts'),
          value: s.showBirthdays,
          onChanged: (v) => ctrl.update((x) => x.copyWith(showBirthdays: v)),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Refresh notes, tasks and contacts'),
          subtitle: const Text(
            'Calendar keeps its own encrypted, read-only copy of them on '
            'this phone. Edit them in their apps',
          ),
          onTap: () async {
            for (final app in LinkedApp.values) {
              final mirror = ref.read(linkedMirrorProvider(app)).value;
              await mirror?.refresh();
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Up to date')),
              );
            }
          },
        ),
      ],
      backupSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Import from Google Calendar or .ics'),
          subtitle: const Text(
            'An .ics file, or the Google Takeout .zip with your calendars',
          ),
          onTap: () => importCalendarFile(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Export all events (.ics)'),
          subtitle: const Text('Unencrypted file, for other calendar apps'),
          onTap: () => _export(context, ref),
        ),
      ],
    );
  }

  static String _minutesLabel(int m) =>
      m < 60 ? '$m minutes' : m % 60 == 0 ? (m == 60 ? '1 hour' : '${m ~/ 60} hours') : '${m / 60} hours';

  Future<int?> _pickFrom(
    BuildContext context,
    String title,
    List<int> values,
    String Function(int) label,
  ) => showDialog<int>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(title),
      children: [
        for (final v in values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label(v)),
            ),
          ),
      ],
    ),
  );

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Export events?'),
        content: const Text(
          'The .ics file is not encrypted. Anyone who gets it can read your '
          'events. Share it only with apps you trust.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Export')),
        ],
      ),
    );
    if (ok != true) return;
    final events = await ref.read(calendarRepositoryProvider).allEvents();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/zt-calendar-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.ics',
    );
    await file.writeAsString(Ics.write(events));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/calendar')]),
    );
  }
}

/// Picks an .ics file or a Google Takeout .zip and imports it.
Future<void> importCalendarFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final help = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Import events'),
      content: const Text(
        'From Google Calendar: go to takeout.google.com, choose only '
        '"Calendar", download the .zip and pick it here. Every calendar in it '
        'is added, and importing the same file again skips events you '
        'already have.\n\nFrom other apps: export an .ics file and pick it.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Choose file')),
      ],
    ),
  );
  if (help != true) return;
  final files = await FilePicker.pickFiles(dialogTitle: 'Choose an .ics or .zip file');
  if (files.isEmpty) return;
  try {
    final picked = <(String, Uint8List)>[
      for (final f in files) (f.name, await f.readAsBytes()),
    ];
    final repo = ref.read(calendarRepositoryProvider);
    final plan = IcsImportPlan.build(
      files: picked,
      existing: await repo.allEvents(),
      calendars: await ref.read(calendarsProvider.future),
    );
    for (final c in plan.newCalendars) {
      await repo.saveCalendar(c);
    }
    for (final e in plan.events) {
      await repo.saveEvent(e);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${plan.events.length} '
          '${plan.events.length == 1 ? 'event' : 'events'}'
          '${plan.newCalendars.isEmpty ? '' : ' into ${plan.newCalendars.length} new ${plan.newCalendars.length == 1 ? 'calendar' : 'calendars'}'}'
          '${plan.skipped == 0 ? '' : ', skipped ${plan.skipped} already here'}.',
        ),
      ),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not import that file: $e')));
  }
}
