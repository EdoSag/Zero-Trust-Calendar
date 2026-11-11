import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../booking/booking_crypto.dart';
import '../booking/booking_pages.dart';
import '../data/calendar_store.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';
import '../util/time_zones.dart';
import 'time_zone_picker.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Settings › Booking pages (K15): the account's booking pages and the
/// bookings coming up on them.
class BookingPagesPage extends ConsumerWidget {
  const BookingPagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final pages = ref.watch(bookingPagesProvider);
    final bookings = ref.watch(upcomingBookingsProvider).value ?? const <Booking>[];
    final events = {
      for (final e in ref.watch(eventsProvider).value ?? const <CalendarEvent>[]) e.id: e,
    };
    final titles = {for (final p in pages.value ?? const <BookingPage>[]) p.id: p.title};
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(l.bookingPages)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.newBookingPage),
        onPressed: () => openBookingPageEditor(context),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(bookingRevisionProvider.notifier).bump(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(l.bookingPagesIntro),
            ),
            ...switch (pages) {
              AsyncError(:final error) => [
                ListTile(
                  leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  title: Text(l.bookingLoadFailed('$error')),
                ),
              ],
              AsyncData(:final value) when value.isEmpty => [
                ListTile(title: Text(l.bookingNoPages, style: small)),
              ],
              AsyncData(:final value) => [
                for (final p in value)
                  ListTile(
                    leading: Icon(
                      p.active ? Icons.event_available : Icons.pause_circle_outline,
                    ),
                    title: Text(p.title),
                    subtitle: Text(
                      '${l.findATimeLength(p.durationMin)} · '
                      '${p.active ? l.bookingActive : l.bookingPaused}',
                    ),
                    trailing: IconButton(
                      tooltip: l.bookingShare,
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => shareBookingLink(context, p),
                    ),
                    onTap: () => openBookingPageEditor(context, page: p),
                  ),
              ],
              _ => [const LinearProgressIndicator()],
            },
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l.bookingUpcoming, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (bookings.isEmpty)
              ListTile(title: Text(l.bookingNoneYet, style: small)),
            for (final b in bookings)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  events[bookingEventId(b.id)]?.title ?? titles[b.pageId] ?? '',
                ),
                subtitle: Text(
                  '${relativeDay(b.start)}, ${formatTime(context, b.start)}'
                  '${b.status == 'new' ? ' · ${l.bookingAdding}' : ''}',
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.bookingPrivacy, style: small),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> shareBookingLink(BuildContext context, BookingPage page) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: context.l10n.bookingShareText(page.link),
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

Future<void> openBookingPageEditor(BuildContext context, {BookingPage? page}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BookingPageEditor(page: page),
      ),
    );

/// Makes or changes one booking page.
class BookingPageEditor extends ConsumerStatefulWidget {
  const BookingPageEditor({super.key, this.page});

  /// The page to change, or null for a new one.
  final BookingPage? page;

  @override
  ConsumerState<BookingPageEditor> createState() => _BookingPageEditorState();
}

class _BookingPageEditorState extends ConsumerState<BookingPageEditor> {
  late final TextEditingController _title;
  late final TextEditingController _host;
  late final TextEditingController _description;
  late int _duration;
  late int _step;
  late int _buffer;
  late int _notice;
  late int _horizon;
  late String _zone;
  late Map<int, List<(int, int)>> _hours;
  late bool _active;
  String _calendarId = CalendarEvent.defaultCalendarId;
  bool _saving = false;

  bool get _isNew => widget.page == null;

  @override
  void initState() {
    super.initState();
    final p = widget.page;
    _title = TextEditingController(text: p?.title ?? '');
    _host = TextEditingController(text: p?.hostName ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _duration = p?.durationMin ?? 30;
    _step = p?.stepMin ?? 30;
    _buffer = p?.bufferMin ?? 0;
    _notice = p?.noticeMin ?? 240;
    _horizon = p?.horizonDays ?? 30;
    _zone = p?.timeZone ?? 'UTC';
    _active = p?.active ?? true;
    _hours = {
      for (final MapEntry(:key, :value)
          in (p?.hours ??
                  BookingPage.defaultHours(
                    sundayFirst: currentL10n.localeName.startsWith('he'),
                  ))
              .entries)
        key: [...value],
    };
    if (p == null) {
      FlutterTimezone.getLocalTimezone().then((z) {
        if (mounted && zoneFor(z.identifier) != null) setState(() => _zone = z.identifier);
      }).ignore();
    } else {
      _loadCalendar(p.id);
    }
  }

  Future<void> _loadCalendar(String pageId) async {
    try {
      final store = await ref.read(ztLocalStoreProvider.future);
      final key = await bookingKeysCollection.get(store, BookingPageKey.itemIdFor(pageId));
      if (key != null && mounted) setState(() => _calendarId = key.calendarId);
    } on Object {
      // Locked or closed meanwhile: the default calendar stays shown.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _host.dispose();
    _description.dispose();
    super.dispose();
  }

  String _noticeLabel(int minutes) {
    final l = context.l10n;
    if (minutes == 0) return l.bookingNone;
    if (minutes < 1440) return l.bookingNoticeHours(minutes ~/ 60);
    return l.bookingNoticeDays(minutes ~/ 1440);
  }

  String _clock(int minutes) => formatTime(
    context,
    DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60),
  );

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
    if (_title.text.trim().isEmpty) return say(l.bookingNeedsTitle);
    if (_hours.values.every((r) => r.isEmpty)) return say(l.bookingNeedsHours);
    setState(() => _saving = true);
    try {
      final store = await ref.read(ztLocalStoreProvider.future);
      final sync = ref.read(ztSyncControllerProvider.notifier);
      var page = widget.page;
      if (page == null) {
        // The private key is saved (and synced) before the page exists on
        // the server, so no booking can arrive that no phone can open.
        final keys = BookingKeyPair.generate();
        page = BookingPage(
          id: BookingPage.newId(),
          title: '',
          durationMin: _duration,
          timeZone: _zone,
          hours: const {},
          publicKey: keys.publicKey,
        );
        await bookingKeysCollection.save(
          sync,
          store,
          BookingPageKey(pageId: page.id, privateKey: keys.privateKey, calendarId: _calendarId),
        );
      } else {
        final key = await bookingKeysCollection.get(store, BookingPageKey.itemIdFor(page.id));
        if (key != null && key.calendarId != _calendarId) {
          await bookingKeysCollection.save(sync, store, key.copyWith(calendarId: _calendarId));
        }
      }
      await ref.read(bookingBackendProvider).savePage(
        page.copyWith(
          title: _title.text.trim(),
          hostName: _host.text.trim(),
          description: _description.text.trim(),
          durationMin: _duration,
          stepMin: _step,
          bufferMin: _buffer,
          noticeMin: _notice,
          horizonDays: _horizon,
          timeZone: _zone,
          hours: {
            for (final MapEntry(:key, :value) in _hours.entries)
              if (value.isNotEmpty) key: value,
          },
          active: _active,
        ),
      );
      ref.read(bookingRevisionProvider.notifier).bump();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      say(l.couldNotSave('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final page = widget.page!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.bookingDelete),
        content: Text(l.bookingDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(bookingBackendProvider).deletePage(page.id);
      await bookingKeysCollection.delete(
        ref.read(ztSyncControllerProvider.notifier),
        BookingPageKey.itemIdFor(page.id),
      );
      ref.read(bookingRevisionProvider.notifier).bump();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.couldNotSave('$e')), duration: const Duration(seconds: 4)),
      );
    }
  }

  Future<void> _pickRange(int day, int index) async {
    final ranges = _hours[day]!;
    final (s, e) = ranges[index];
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s ~/ 60, minute: s % 60),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: e ~/ 60, minute: e % 60),
    );
    if (end == null) return;
    final from = start.hour * 60 + start.minute;
    var to = end.hour * 60 + end.minute;
    if (to == 0) to = 1440; // "until midnight"
    if (to <= from) return;
    setState(() => ranges[index] = (from, to));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final calendars = [
      for (final c in ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal])
        if (c.url == null) c,
    ];
    if (!calendars.any((c) => c.id == _calendarId)) {
      _calendarId = CalendarEvent.defaultCalendarId;
    }
    // Monday first, or Sunday first in Hebrew (as the week is shown there).
    final days = currentL10n.localeName.startsWith('he')
        ? const [7, 1, 2, 3, 4, 5, 6]
        : const [1, 2, 3, 4, 5, 6, 7];
    final dayName = DateFormat.EEEE(currentL10n.localeName);
    Widget choice<T>(String label, T value, List<T> options, String Function(T) text, void Function(T) set) =>
        ListTile(
          title: Text(label),
          trailing: DropdownButton<T>(
            value: options.contains(value) ? value : options.first,
            items: [
              for (final o in options) DropdownMenuItem(value: o, child: Text(text(o))),
            ],
            onChanged: (v) => v == null ? null : setState(() => set(v)),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l.newBookingPage : l.bookingPage),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: l.bookingShare,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareBookingLink(context, widget.page!),
            ),
          TextButton(onPressed: _saving ? null : _save, child: Text(l.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(labelText: l.bookingTitle, hintText: l.bookingTitleHint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _host,
              maxLength: 80,
              decoration: InputDecoration(labelText: l.bookingHostName),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _description,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: l.bookingDescription),
            ),
          ),
          if (!_isNew)
            SwitchListTile(
              title: Text(l.bookingActive),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          choice(l.bookingLength, _duration, const [15, 20, 30, 45, 60, 90, 120], l.findATimeLength, (v) => _duration = v),
          choice(l.bookingStep, _step, const [15, 30, 60], l.findATimeLength, (v) => _step = v),
          choice(l.bookingBuffer, _buffer, const [0, 5, 10, 15, 30], (v) => v == 0 ? l.bookingNone : l.findATimeLength(v), (v) => _buffer = v),
          choice(l.bookingNotice, _notice, const [0, 60, 240, 1440, 2880], _noticeLabel, (v) => _notice = v),
          choice(l.bookingHorizon, _horizon, const [7, 14, 30, 60], l.bookingHorizonDays, (v) => _horizon = v),
          ListTile(
            title: Text(l.bookingCalendar),
            trailing: DropdownButton<String>(
              value: _calendarId,
              items: [
                for (final c in calendars)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 12, color: Color(c.color)),
                        const SizedBox(width: 8),
                        Text(c.name.isEmpty ? l.personal : c.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => v == null ? null : setState(() => _calendarId = v),
            ),
          ),
          ListTile(
            title: Text(l.bookingTimeZone),
            subtitle: Text(_zone, textDirection: TextDirection.ltr),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final z = await pickTimeZone(context, current: _zone, at: DateTime.now());
              if (z == null || !mounted) return;
              if (z.isEmpty) {
                final local = await FlutterTimezone.getLocalTimezone();
                if (mounted) setState(() => _zone = local.identifier);
              } else {
                setState(() => _zone = z);
              }
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.bookingHours, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final d in days) _dayRow(d, dayName.format(DateTime(2024, 1, d))),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.bookingPrivacy, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (!_isNew)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(l.bookingDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: _delete,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// One weekday: on/off and its time ranges. (1 January 2024 was a Monday,
  /// so DateTime(2024, 1, d) is weekday d.)
  Widget _dayRow(int day, String name) {
    final l = context.l10n;
    final ranges = _hours[day] ?? const <(int, int)>[];
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: ranges.isNotEmpty,
              title: Text(name, overflow: TextOverflow.ellipsis),
              onChanged: (on) => setState(() {
                _hours[day] = on == true ? [(540, 1020)] : [];
              }),
            ),
          ),
          Expanded(
            child: ranges.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(l.bookingUnavailable, style: Theme.of(context).textTheme.bodySmall),
                  )
                : Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < ranges.length; i++)
                        InputChip(
                          label: Text(
                            '${_clock(ranges[i].$1)}–${_clock(ranges[i].$2 % 1440)}',
                            textDirection: TextDirection.ltr,
                          ),
                          onPressed: () => _pickRange(day, i),
                          onDeleted: () => setState(() => _hours[day] = [...ranges]..removeAt(i)),
                        ),
                      if (ranges.length < 4)
                        IconButton(
                          tooltip: l.bookingAddHours,
                          icon: const Icon(Icons.add),
                          onPressed: () => setState(() {
                            final last = ranges.last.$2;
                            if (last >= 1380) return;
                            _hours[day] = [...ranges, (last + 60, (last + 180).clamp(0, 1440))];
                          }),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
