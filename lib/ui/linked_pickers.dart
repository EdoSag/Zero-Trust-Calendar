import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../util/format.dart';
import 'linked_app_launcher.dart';

/// Calendar and optional event colour. Returns (calendar id, colour or null
/// for the calendar's).
Future<(String, int?)?> pickCalendarAndColor(
  BuildContext context, {
  required List<ZtCalendarInfo> calendars,
  required String calendarId,
  required int? color,
}) => showModalBottomSheet<(String, int?)>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) {
    var cal = calendarId;
    int? col = color;
    return StatefulBuilder(
      builder: (sheet, setState) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Calendar'),
              ),
              for (final c in calendars)
                ListTile(
                  leading: Icon(Icons.circle, color: Color(c.color)),
                  title: Text(c.name),
                  trailing: c.id == cal ? const Icon(Icons.check) : null,
                  onTap: () => setState(() => cal = c.id),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text('Event colour'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('Calendar colour'),
                      selected: col == null,
                      onSelected: (_) => setState(() => col = null),
                    ),
                    for (final c in calendarPalette)
                      _ColorDot(
                        color: c,
                        selected: col == c,
                        onTap: () => setState(() => col = c),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheet).pop((cal, col)),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Colour',
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
        child: selected ? Icon(Icons.check, color: onColor(Color(color)), size: 20) : null,
      ),
    ),
  );
}

/// Picks guests among ZT Contacts contacts.
Future<Set<String>?> pickContacts(
  BuildContext context, {
  required Set<String> selected,
}) => Navigator.of(context).push<Set<String>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ContactPickerPage(selected: selected),
  ),
);

class _ContactPickerPage extends ConsumerStatefulWidget {
  const _ContactPickerPage({required this.selected});
  final Set<String> selected;

  @override
  ConsumerState<_ContactPickerPage> createState() => _ContactPickerPageState();
}

class _ContactPickerPageState extends ConsumerState<_ContactPickerPage> {
  late Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(linkedContactsProvider);
    final all = async.value ?? const <LinkedContact>[];
    final q = _query.toLowerCase();
    final shown = [
      for (final c in all)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.emails.any((e) => e.toLowerCase().contains(q)))
          c,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guests'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search ZT Contacts',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? _EmptyLinked(
                    loading: async.isLoading,
                    app: LinkedApp.contacts,
                    text: 'Contacts you keep in ZT Contacts show here.',
                  )
                : ListView(
                    children: [
                      for (final c in shown)
                        CheckboxListTile(
                          value: _selected.contains(c.id),
                          title: Text(c.name),
                          subtitle: c.emails.isEmpty ? null : Text(c.emails.first),
                          onChanged: (on) => setState(() {
                            _selected = {..._selected};
                            on == true ? _selected.add(c.id) : _selected.remove(c.id);
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

class _EmptyLinked extends StatelessWidget {
  const _EmptyLinked({required this.loading, required this.app, required this.text});
  final bool loading;
  final LinkedApp app;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => openLinkedApp(app),
              icon: const Icon(Icons.open_in_new),
              label: Text('Open ZT ${app.name[0].toUpperCase()}${app.name.substring(1)}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks a ZT Notes note to link, or creates a new one for the event.
/// Returns the note id.
Future<String?> pickNote(
  BuildContext context,
  WidgetRef ref, {
  required String eventTitle,
  required DateTime eventStart,
  Set<String> exclude = const {},
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _NotePickerPage(
      eventTitle: eventTitle,
      eventStart: eventStart,
      exclude: exclude,
    ),
  ),
);

class _NotePickerPage extends ConsumerStatefulWidget {
  const _NotePickerPage({
    required this.eventTitle,
    required this.eventStart,
    required this.exclude,
  });
  final String eventTitle;
  final DateTime eventStart;
  final Set<String> exclude;

  @override
  ConsumerState<_NotePickerPage> createState() => _NotePickerPageState();
}

class _NotePickerPageState extends ConsumerState<_NotePickerPage> {
  String _query = '';
  bool _creating = false;

  Future<void> _createNote() async {
    setState(() => _creating = true);
    try {
      final mirror = await ref.read(linkedMirrorProvider(LinkedApp.notes).future);
      final title = widget.eventTitle.isEmpty ? 'Event notes' : widget.eventTitle;
      final id = await mirror.create(
        LinkedNote.newNoteJson(
          title: title,
          body: formatLongDay(widget.eventStart),
          now: DateTime.now(),
        ),
      );
      if (mounted) Navigator.of(context).pop(id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the note: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(linkedNotesProvider);
    final all = async.value ?? const <LinkedNote>[];
    final q = _query.toLowerCase();
    final shown = [
      for (final n in all)
        if (!widget.exclude.contains(n.id) &&
            (q.isEmpty ||
                n.title.toLowerCase().contains(q) ||
                n.body.toLowerCase().contains(q)))
          n,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Link a note')),
      body: Column(
        children: [
          ListTile(
            leading: _creating
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.note_add_outlined),
            title: const Text('New note for this event'),
            subtitle: const Text('Created in ZT Notes, encrypted like your other notes'),
            onTap: _creating ? null : _createNote,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search ZT Notes',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? _EmptyLinked(
                    loading: async.isLoading,
                    app: LinkedApp.notes,
                    text: 'Your ZT Notes notes show here.',
                  )
                : ListView(
                    children: [
                      for (final n in shown)
                        ListTile(
                          leading: const Icon(Icons.sticky_note_2_outlined),
                          title: Text(n.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: n.body.trim().isEmpty
                              ? null
                              : Text(
                                  n.body.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.of(context).pop(n.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A linked note, read-only, with a way into ZT Notes.
Future<void> showNoteSheet(BuildContext context, LinkedNote note) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (sheet, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(note.displayTitle, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 12),
            SelectableText(note.body.trim().isEmpty ? 'This note is empty.' : note.body),
            const SizedBox(height: 20),
            Text(
              'Edit it in ZT Notes.',
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => openLinkedApp(LinkedApp.notes),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open ZT Notes'),
              ),
            ),
          ],
        ),
      ),
    );
