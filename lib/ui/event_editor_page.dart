import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../data/event_actions.dart';
import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../model/recurrence.dart';
import '../reminders/reminders.dart';
import '../util/format.dart';
import '../util/time_zones.dart';
import 'attachments.dart';
import 'linked_pickers.dart';
import 'navigation.dart';
import 'recurrence_picker.dart';
import 'time_zone_picker.dart';
import 'inline_button_style.dart';

/// Asks which occurrences a change to a repeating event applies to.
Future<SeriesScope?> askSeriesScope(BuildContext context, {required String action}) =>
    showDialog<SeriesScope>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text('$action repeating event'),
        children: [
          for (final (scope, label) in const [
            (SeriesScope.thisEvent, 'This event'),
            (SeriesScope.thisAndFollowing, 'This and following events'),
            (SeriesScope.allEvents, 'All events'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(scope),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(label),
              ),
            ),
        ],
      ),
    );

/// New event, or an edit of an event or of one occurrence of a series.
class EventEditorPage extends ConsumerStatefulWidget {
  const EventEditorPage({
    super.key,
    this.event,
    this.occurrenceStart,
    this.initialStart,
    this.initialAllDay = false,
    this.duplicate = false,
    this.draft,
  });

  /// Prefilled fields for a new event (quick add's "More options").
  final CalendarEvent? draft;

  /// The event (or series) to edit; null for a new one.
  final CalendarEvent? event;

  /// For a series: the occurrence being edited.
  final DateTime? occurrenceStart;
  final DateTime? initialStart;
  final bool initialAllDay;

  /// Start a new event as a copy of [event].
  final bool duplicate;

  @override
  ConsumerState<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends ConsumerState<EventEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late DateTime _start;
  late DateTime _end; // Exclusive for all-day.
  late bool _allDay;
  RecurrenceRule? _rule;
  late String _calendarId;
  int? _color;
  late List<int> _reminders;
  late List<String> _noteIds;
  late List<String> _contactIds;
  late List<String> _guestEmails;
  late List<Map<String, Object?>> _attachments;
  late final TextEditingController _conference;

  /// IANA zone the times are set in; null is the phone's zone.
  String? _tz;
  tz.Location? get _zone => _allDay ? null : zoneFor(_tz);
  bool _saving = false;
  bool _dirty = false;

  bool get _isNew => widget.event == null || widget.duplicate;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(calendarSettingsProvider);
    final e = widget.event;
    if (e != null) {
      final occ = widget.occurrenceStart;
      final shift = occ != null && e.repeats ? occ.difference(e.start) : Duration.zero;
      _start = e.allDay && occ != null && e.repeats ? dayOf(occ) : e.start.add(shift);
      _end = e.allDay && occ != null && e.repeats
          ? addDays(dayOf(occ), (e.duration.inHours / 24).round())
          : e.end.add(shift);
      _allDay = e.allDay;
      _rule = e.recurrence;
      _calendarId = e.calendarId;
      _color = e.color;
      _reminders = [...e.reminders];
      _noteIds = [...e.noteIds];
      _contactIds = [...e.contactIds];
      _guestEmails = [...e.guestEmails];
      _attachments = [...e.attachments];
      _tz = e.timeZone;
    } else {
      final now = DateTime.now();
      final base = widget.initialStart ??
          DateTime(now.year, now.month, now.day, now.hour + 1);
      final focused = ref.read(focusedDayProvider);
      _allDay = widget.initialAllDay;
      _start = widget.initialStart == null && !sameDay(focused, now)
          ? DateTime(focused.year, focused.month, focused.day, 9)
          : base;
      if (_allDay) _start = dayOf(_start);
      _end = _allDay
          ? addDays(_start, 1)
          : _start.add(Duration(minutes: settings.defaultDuration));
      _calendarId = CalendarEvent.defaultCalendarId;
      _reminders = [
        if (_allDay && settings.defaultAllDayReminder != null) settings.defaultAllDayReminder!,
        if (!_allDay && settings.defaultReminder != null) settings.defaultReminder!,
      ];
      _noteIds = [];
      _contactIds = [];
      _guestEmails = [];
      _attachments = [];
      final d = widget.draft;
      if (d != null) {
        _start = d.start;
        _end = d.end;
        _allDay = d.allDay;
        _rule = d.recurrence;
        _calendarId = d.calendarId;
        if (d.allDay != widget.initialAllDay) {
          _reminders = [
            if (_allDay && settings.defaultAllDayReminder != null) settings.defaultAllDayReminder!,
            if (!_allDay && settings.defaultReminder != null) settings.defaultReminder!,
          ];
        }
      }
    }
    final source = e ?? widget.draft;
    _title = TextEditingController(text: source?.title ?? '');
    _location = TextEditingController(text: source?.location ?? '');
    _description = TextEditingController(text: source?.description ?? '');
    _conference = TextEditingController(text: source?.conferenceUrl ?? '');
    for (final c in [_title, _location, _description, _conference]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    _conference.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  CalendarEvent _buildEvent() {
    final base = widget.event;
    final e = CalendarEvent(
      id: _isNew ? const Uuid().v4() : base!.id,
      title: _title.text.trim(),
      start: _start,
      end: _end,
      allDay: _allDay,
      calendarId: _calendarId,
      description: _description.text.trim(),
      location: _location.text.trim(),
      color: _color,
      rrule: _rule?.toString(),
      exceptions: _isNew ? const {} : base!.exceptions,
      seriesId: _isNew ? null : base!.seriesId,
      originalStart: _isNew ? null : base!.originalStart,
      reminders: (_reminders.toSet().toList()..sort()),
      noteIds: _noteIds,
      contactIds: _contactIds,
      taskIds: base?.taskIds ?? const [],
      icalUid: _isNew ? null : base!.icalUid,
      timeZone: _allDay ? null : _tz,
      conferenceUrl: _conference.text.trim().isEmpty ? null : _conference.text.trim(),
      attachments: _attachments,
      guestEmails: _guestEmails,
      guestStatus: base?.guestStatus ?? const {},
      inviteSequence: _isNew ? 0 : base!.inviteSequence,
      createdAt: _isNew ? null : base!.createdAt,
      extra: _isNew ? const {} : base!.extra,
    );
    return e;
  }

  Future<void> _save() async {
    if (_saving) return;
    final edited = _buildEvent();
    final repo = ref.read(calendarRepositoryProvider);
    final original = widget.event;
    final occurrence = widget.occurrenceStart;
    setState(() => _saving = true);
    try {
      if (!_isNew && original!.repeats && occurrence != null) {
        final scope = await askSeriesScope(context, action: 'Save');
        if (scope == null) {
          setState(() => _saving = false);
          return;
        }
        await repo.apply(
          SeriesEdits.edit(
            series: original,
            occurrence: occurrence,
            edited: edited,
            scope: scope,
            exceptions: await repo.exceptionsOf(original.id),
          ),
        );
      } else {
        await repo.saveEvent(edited);
      }
      if (edited.reminders.isNotEmpty) {
        // Asked once, when the first reminder is set.
        await ref.read(reminderSchedulerProvider).requestPermission();
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ItemFromNewerVersion {
      _snack('This event was changed by a newer ZT Calendar. Update the app to edit it.');
      setState(() => _saving = false);
    } on Object catch (e) {
      _snack('Could not save: $e');
      setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  /// [t] on the clock of the event's zone (the phone's when it has none).
  DateTime _shown(DateTime t) {
    final z = _zone;
    return z == null ? t : wallClockIn(z, t);
  }

  DateTime _fromShown(DateTime wall) {
    final z = _zone;
    return z == null ? wall : instantFromWall(z, wall);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final s0 = _shown(_start);
    final e0 = _shown(_end);
    final current = isStart ? s0 : (_allDay ? addDays(e0, -1) : e0);
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d == null) return;
    _set(() {
      var s = s0;
      var e = e0;
      if (isStart) {
        final length = e.difference(s);
        s = DateTime(d.year, d.month, d.day, s.hour, s.minute);
        e = _allDay
            ? addDays(s, (length.inHours / 24).round().clamp(1, 100000))
            : s.add(length);
      } else {
        e = _allDay
            ? addDays(d, 1)
            : DateTime(d.year, d.month, d.day, e.hour, e.minute);
        if (!e.isAfter(s)) {
          e = _allDay ? addDays(s, 1) : s.add(const Duration(hours: 1));
        }
      }
      _start = _allDay ? s : _fromShown(s);
      _end = _allDay ? e : _fromShown(e);
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final s0 = _shown(_start);
    final e0 = _shown(_end);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? s0 : e0),
    );
    if (t == null) return;
    _set(() {
      var s = s0;
      var e = e0;
      if (isStart) {
        final length = e.difference(s);
        s = DateTime(s.year, s.month, s.day, t.hour, t.minute);
        e = s.add(length);
      } else {
        e = DateTime(e.year, e.month, e.day, t.hour, t.minute);
        if (!e.isAfter(s)) {
          // Ending "earlier" means the next day, as across midnight.
          e = e.add(const Duration(days: 1));
          if (!e.isAfter(s)) e = s.add(const Duration(hours: 1));
        }
      }
      _start = _fromShown(s);
      _end = _fromShown(e);
    });
  }

  /// Keeps the times on the clock: 9:00 stays 9:00 in the new zone, as in
  /// Google Calendar.
  Future<void> _pickZone() async {
    final picked = await pickTimeZone(context, current: _tz, at: _start);
    if (picked == null) return;
    final next = picked.isEmpty ? null : picked;
    _set(() {
      final s = _shown(_start);
      final e = _shown(_end);
      _tz = next;
      _start = _fromShown(s);
      _end = _fromShown(e);
    });
  }

  Future<void> _addAttachment() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Attach a file');
    if (files.isEmpty || !mounted) return;
    try {
      final attachments = await ref.read(ztAttachmentsProvider.future);
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final ref0 = await attachments.put(bytes, mimeType: mimeTypeFor(f.name), name: f.name);
        _set(() => _attachments = [..._attachments, ref0.toJson()]);
      }
    } on AttachmentTooLarge {
      _snack('Files can be up to 20 MB.');
    } on Object catch (e) {
      _snack('Could not attach the file: $e');
    }
  }

  Future<void> _addGuestEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add guest by email'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'name@example.com'),
          onSubmitted: (v) => Navigator.of(d).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    final v = email?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      if (v.isNotEmpty) _snack('That doesn\'t look like an email address.');
      return;
    }
    if (!_guestEmails.contains(v)) _set(() => _guestEmails = [..._guestEmails, v]);
  }

  Future<void> _addReminder() async {
    final options = _allDay
        ? const [0, 24 * 60, 2 * 24 * 60, 7 * 24 * 60]
        : const [0, 5, 10, 15, 30, 60, 120, 24 * 60, 2 * 24 * 60, 7 * 24 * 60];
    final picked = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Add reminder'),
        children: [
          for (final m in options)
            if (!_reminders.contains(m))
              SimpleDialogOption(
                onPressed: () => Navigator.of(d).pop(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(reminderLabel(m, allDay: _allDay)),
                ),
              ),
        ],
      ),
    );
    if (picked != null) _set(() => _reminders = [..._reminders, picked]..sort());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final calendar = calendars.firstWhere(
      (c) => c.id == _calendarId,
      orElse: () => ZtCalendarInfo.personal,
    );
    final notes = ref.watch(linkedNotesProvider).value ?? const <LinkedNote>[];
    final contacts = ref.watch(linkedContactsProvider).value ?? const <LinkedContact>[];
    final shownEnd = _allDay ? addDays(_end, -1) : _end;
    final isException = widget.event?.isException ?? false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                style: inlineButtonStyle,
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: TextField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.headlineSmall,
                decoration: const InputDecoration(
                  hintText: 'Add title',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.schedule),
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) => _set(() {
                _allDay = v;
                if (v) {
                  // Every day the timed event touched, end exclusive.
                  final lastDay = dayOf(_end.subtract(const Duration(microseconds: 1)));
                  _start = dayOf(_start);
                  _end = addDays(lastDay, 1);
                  if (!_end.isAfter(_start)) _end = addDays(_start, 1);
                } else {
                  final now = DateTime.now();
                  _start = DateTime(_start.year, _start.month, _start.day, now.hour + 1);
                  _end = _start.add(
                    Duration(minutes: ref.read(calendarSettingsProvider).defaultDuration),
                  );
                }
                // Reminders mean something else for all-day events.
                final s = ref.read(calendarSettingsProvider);
                _reminders = [
                  if (v && s.defaultAllDayReminder != null) s.defaultAllDayReminder!,
                  if (!v && s.defaultReminder != null) s.defaultReminder!,
                ];
              }),
            ),
            _DateTimeRow(
              date: formatDay(_shown(_start)),
              time: _allDay ? null : formatTime(context, _shown(_start)),
              onDate: () => _pickDate(isStart: true),
              onTime: () => _pickTime(isStart: true),
            ),
            _DateTimeRow(
              date: formatDay(_allDay ? shownEnd : _shown(_end)),
              time: _allDay ? null : formatTime(context, _shown(_end)),
              onDate: () => _pickDate(isStart: false),
              onTime: () => _pickTime(isStart: false),
            ),
            if (!_allDay)
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(
                  _tz == null
                      ? 'Phone\'s time zone (${utcOffsetLabel(null, _start)})'
                      : '${zoneCity(_tz!)} (${utcOffsetLabel(_zone, _start)})',
                ),
                subtitle: _tz != null && differsFromPhone(_zone!, _start)
                    ? Text(
                        'Your time: ${formatDay(_start)}, '
                        '${formatSpan(context, _start, _end, false)}',
                      )
                    : null,
                onTap: _pickZone,
              ),
            if (!isException)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(describeRule(_rule, _start)),
                onTap: () async {
                  final picked = await pickRecurrence(context, start: _start, current: _rule);
                  if (picked != null) _set(() => _rule = picked.$1);
                },
              ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.circle, color: Color(_color ?? calendar.color)),
              title: Text(calendar.name),
              subtitle: _color == null ? null : const Text('Event colour'),
              onTap: () async {
                final picked = await pickCalendarAndColor(
                  context,
                  calendars: calendars,
                  calendarId: _calendarId,
                  color: _color,
                );
                if (picked != null) {
                  _set(() {
                    _calendarId = picked.$1;
                    _color = picked.$2;
                  });
                }
              },
            ),
            const Divider(),
            for (final m in _reminders)
              ListTile(
                leading: Icon(
                  m == _reminders.first ? Icons.notifications_outlined : null,
                ),
                title: Text(reminderLabel(m, allDay: _allDay)),
                trailing: IconButton(
                  tooltip: 'Remove reminder',
                  icon: const Icon(Icons.close),
                  onPressed: () => _set(() => _reminders = [..._reminders]..remove(m)),
                ),
              ),
            ListTile(
              leading: Icon(_reminders.isEmpty ? Icons.notifications_outlined : null),
              title: Text(
                'Add reminder',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              onTap: _addReminder,
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _location,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  icon: Icon(Icons.place_outlined),
                  hintText: 'Add location',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _conference,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  icon: Icon(Icons.videocam_outlined),
                  hintText: 'Add video call link',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(
                _contactIds.isEmpty ? 'Add guests from ZT Contacts' : 'Guests',
                style: _contactIds.isEmpty
                    ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                    : null,
              ),
              onTap: () async {
                final picked = await pickContacts(context, selected: _contactIds.toSet());
                if (picked != null) _set(() => _contactIds = picked.toList());
              },
            ),
            for (final email in _guestEmails)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 8),
                title: Text(email),
                trailing: IconButton(
                  tooltip: 'Remove guest',
                  icon: const Icon(Icons.close),
                  onPressed: () => _set(() => _guestEmails = [..._guestEmails]..remove(email)),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 8),
              title: Text(
                'Add guest by email',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              onTap: _addGuestEmail,
            ),
            for (final id in _contactIds)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 8),
                title: Text(
                  contacts.where((c) => c.id == id).firstOrNull?.name ?? 'Contact',
                ),
                trailing: IconButton(
                  tooltip: 'Remove guest',
                  icon: const Icon(Icons.close),
                  onPressed: () => _set(() => _contactIds = [..._contactIds]..remove(id)),
                ),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(
                _noteIds.isEmpty ? 'Link a note from ZT Notes' : 'Notes',
                style: _noteIds.isEmpty
                    ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                    : null,
              ),
              onTap: () async {
                final picked = await pickNote(
                  context,
                  ref,
                  eventTitle: _title.text.trim(),
                  eventStart: _start,
                  exclude: _noteIds.toSet(),
                );
                if (picked != null) _set(() => _noteIds = [..._noteIds, picked]);
              },
            ),
            for (final id in _noteIds)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 8),
                title: Text(
                  notes.where((n) => n.id == id).firstOrNull?.displayTitle ?? 'Note',
                ),
                trailing: IconButton(
                  tooltip: 'Unlink note',
                  icon: const Icon(Icons.close),
                  onPressed: () => _set(() => _noteIds = [..._noteIds]..remove(id)),
                ),
              ),
            const Divider(),
            for (final a in _attachments)
              AttachmentTile(
                attachment: a,
                onRemove: () => _set(() => _attachments = [..._attachments]..remove(a)),
              ),
            ListTile(
              leading: Icon(_attachments.isEmpty ? Icons.attach_file : null),
              title: Text(
                'Add attachment',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              subtitle: _attachments.isEmpty
                  ? const Text('Encrypted on this phone before upload')
                  : null,
              onTap: _addAttachment,
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _description,
                minLines: 2,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  icon: Icon(Icons.notes),
                  hintText: 'Add description',
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.date,
    required this.time,
    required this.onDate,
    required this.onTime,
  });

  final String date;
  final String? time;
  final VoidCallback onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onDate, child: Text(date)),
            ),
          ),
          if (time != null) TextButton(onPressed: onTime, child: Text(time!)),
        ],
      ),
    );
  }
}
