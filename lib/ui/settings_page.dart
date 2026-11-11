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
import '../caldav/caldav_bridge.dart';
import '../data/calendar_store.dart';
import '../data/linked_apps.dart';
import '../ics/ics.dart';
import '../ics/import_service.dart';
import '../reminders/reminders.dart';
import '../util/format.dart';
import 'calendars_page.dart';
import 'desktop_bridge_page.dart';
import 'phone_calendar_page.dart';
import 'subscribe_page.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

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
          title: Text(context.l10n.calendars),
          subtitle: Text(context.l10n.addRenameRecolourOrHide),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CalendarsPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(context.l10n.holidaysAndSubscribedCalendars),
          subtitle: Text(context.l10n.publicHolidaysSchoolOrTeam),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HolidaysPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.computer),
          title: Text(context.l10n.desktopApps),
          subtitle: Text(
            ref.watch(desktopBridgeProvider).enabled
                ? context.l10n.desktopAppsSubtitleOn
                : context.l10n.desktopAppsSubtitleOff,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DesktopBridgePage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.phone_android),
          title: Text(context.l10n.showOnThisPhoneX),
          subtitle: Text(
            s.phoneCalendarIdsFor(ref.read(accountServiceProvider).currentUserId).isEmpty
                ? context.l10n.offForYourWatchCar
                : context.l10n.onForSomeCalendarsCopied,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PhoneCalendarPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.first_page),
          title: Text(context.l10n.startOfTheWeek),
          subtitle: Text(
            weekStart == null
                ? context.l10n.likeYourRegionDay(DateFormat.EEEE().format(DateTime(2024, 1, localeWeekStart(context))))
                : DateFormat.EEEE().format(DateTime(2024, 1, weekStart)),
          ),
          onTap: () async {
            final picked = await showDialog<int>(
              context: context,
              builder: (d) => SimpleDialog(
                title: Text(context.l10n.startOfTheWeek),
                children: [
                  for (final v in [0, DateTime.saturday, DateTime.sunday, DateTime.monday])
                    SimpleDialogOption(
                      onPressed: () => Navigator.of(d).pop(v),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          v == 0 ? context.l10n.likeYourRegion : DateFormat.EEEE().format(DateTime(2024, 1, v)),
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
          title: Text(context.l10n.defaultEventLength),
          subtitle: Text(_minutesLabel(s.defaultDuration)),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              context.l10n.defaultEventLength,
              const [15, 30, 45, 60, 90, 120],
              _minutesLabel,
            );
            if (picked != null) await ctrl.update((x) => x.copyWith(defaultDuration: picked));
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(context.l10n.defaultReminder),
          subtitle: Text(s.defaultReminder == null ? context.l10n.none : reminderLabel(s.defaultReminder!)),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              context.l10n.defaultReminder,
              const [-1, 0, 5, 10, 15, 30, 60, 24 * 60],
              (m) => m < 0 ? context.l10n.none : reminderLabel(m),
            );
            if (picked != null) {
              await ctrl.update((x) => x.copyWith(defaultReminder: picked < 0 ? null : picked));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_none),
          title: Text(context.l10n.defaultAllDayReminder),
          subtitle: Text(
            s.defaultAllDayReminder == null
                ? context.l10n.none
                : reminderLabel(s.defaultAllDayReminder!, allDay: true),
          ),
          onTap: () async {
            final picked = await _pickFrom(
              context,
              context.l10n.defaultAllDayReminder,
              const [-1, 0, 24 * 60, 2 * 24 * 60, 7 * 24 * 60],
              (m) => m < 0 ? context.l10n.none : reminderLabel(m, allDay: true),
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
          title: Text(context.l10n.eventTitlesInReminders),
          subtitle: Text(
            context.l10n.offRemindersOnlySayEvent,
          ),
          value: s.notificationTitles,
          onChanged: (v) => ctrl.update((x) => x.copyWith(notificationTitles: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.widgets_outlined),
          title: Text(context.l10n.showDetailsOnTheHome),
          subtitle: Text(
            context.l10n.offTheUpNextWidget,
          ),
          value: s.widgetTitles,
          onChanged: (v) => ctrl.update((x) => x.copyWith(widgetTitles: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.task_alt),
          title: Text(context.l10n.showTasksFromZtTasks),
          subtitle: Text(context.l10n.tasksWithADueDate),
          value: s.showTasks,
          onChanged: (v) => ctrl.update((x) => x.copyWith(showTasks: v)),
        ),
        if (s.showTasks)
          SwitchListTile(
            secondary: const Icon(Icons.done_all),
            title: Text(context.l10n.showCompletedTasks),
            value: s.showCompletedTasks,
            onChanged: (v) => ctrl.update((x) => x.copyWith(showCompletedTasks: v)),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.cake_outlined),
          title: Text(context.l10n.showBirthdaysFromZtContacts),
          value: s.showBirthdays,
          onChanged: (v) => ctrl.update((x) => x.copyWith(showBirthdays: v)),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(context.l10n.refreshNotesTasksAndContacts),
          subtitle: Text(
            context.l10n.calendarKeepsItsOwnEncrypted,
          ),
          onTap: () async {
            for (final app in LinkedApp.values) {
              final mirror = ref.read(linkedMirrorProvider(app)).value;
              await mirror?.refresh();
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.upToDate)),
              );
            }
          },
        ),
      ],
      backupSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: Text(context.l10n.importFromGoogleCalendarOr),
          subtitle: Text(
            context.l10n.anIcsFileOrThe,
          ),
          onTap: () => importCalendarFile(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(context.l10n.exportAllEventsIcs),
          subtitle: Text(context.l10n.unencryptedFileForOtherCalendar),
          onTap: () => _export(context, ref),
        ),
      ],
    );
  }

  static String _minutesLabel(int m) =>
      m < 60
          ? currentL10n.nMinutes(m)
          : m % 60 == 0
          ? currentL10n.nHours(m ~/ 60)
          : currentL10n.nHoursDecimal('${m / 60}');

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
        title: Text(context.l10n.exportEvents),
        content: Text(
          context.l10n.theIcsFileIsNot,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.exportLabel)),
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
      title: Text(context.l10n.importEvents),
      content: Text(
        context.l10n.fromGoogleCalendarGoTo,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.chooseFile)),
      ],
    ),
  );
  if (help != true) return;
  final files = await FilePicker.pickFiles(dialogTitle: currentL10n.chooseAnIcsOrZip);
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
    for (final e in [...plan.updatedSeries, ...plan.events]) {
      await repo.saveEvent(e);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${currentL10n.importedNEvents(plan.events.length)}'
          '${plan.newCalendars.isEmpty ? '' : currentL10n.intoNewCalendars(plan.newCalendars.length)}'
          '${plan.skipped == 0 ? '' : currentL10n.skippedAlreadyHere(plan.skipped)}.',
        ),
      ),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.couldNotImportFile('$e'))));
  }
}
