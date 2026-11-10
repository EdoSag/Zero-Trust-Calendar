import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/calendar_store.dart';
import '../ics/ics.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../platform/channels.dart';
import '../util/format.dart';

/// One guest: a ZT Contacts contact, or an email address.
@immutable
class Guest {
  const Guest({required this.key, this.name, this.email, this.phone});

  /// Contact id, or the email address (also the key in `guestStatus`).
  final String key;
  final String? name;
  final String? email;
  final String? phone;

  String get label => name ?? email ?? 'Guest';
}

List<Guest> guestsOf(CalendarEvent event, List<LinkedContact> contacts) => [
  for (final id in event.contactIds)
    if (contacts.where((c) => c.id == id).firstOrNull case final LinkedContact c)
      Guest(
        key: c.id,
        name: c.name,
        email: c.emails.firstOrNull,
        phone: c.phones.firstOrNull,
      ),
  for (final email in event.guestEmails) Guest(key: email, email: email),
];

const rsvpLabels = {
  'accepted': ('Going', Icons.check_circle_outline),
  'tentative': ('Maybe', Icons.help_outline),
  'declined': ('Not going', Icons.cancel_outlined),
};

/// "Running late": picks how late, then opens a text message (or email) to
/// the guests. Nothing is sent without the user pressing Send there.
Future<void> sendRunningLate(
  BuildContext context,
  CalendarEvent event,
  List<Guest> guests,
) async {
  final phones = [for (final g in guests) if (g.phone != null) g.phone!];
  final emails = [for (final g in guests) if (g.email != null) g.email!];
  final messenger = ScaffoldMessenger.of(context);
  if (phones.isEmpty && emails.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No phone numbers or email addresses for the guests.')),
    );
    return;
  }
  final minutes = await showDialog<int>(
    context: context,
    builder: (d) => SimpleDialog(
      title: const Text('Running late'),
      children: [
        for (final m in const [5, 10, 15, 30])
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('About $m minutes'),
            ),
          ),
      ],
    ),
  );
  if (minutes == null || !context.mounted) return;
  final title = event.title.trim().isEmpty ? 'our meeting' : '"${event.title.trim()}"';
  final text = 'Running about $minutes minutes late for $title. Sorry!';
  var useSms = phones.isNotEmpty;
  if (phones.isNotEmpty && emails.isNotEmpty) {
    final pick = await showDialog<bool>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Send by'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Text message'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Email'),
            ),
          ),
        ],
      ),
    );
    if (pick == null) return;
    useSms = pick;
  }
  final uri = useSms
      ? Uri(scheme: 'sms', path: phones.join(','), queryParameters: {'body': text})
      : Uri(
          scheme: 'mailto',
          path: emails.join(','),
          query: 'subject=${Uri.encodeComponent('Running late')}'
              '&body=${Uri.encodeComponent(text)}',
        );
  if (!await launchUrl(uri)) {
    messenger.showSnackBar(const SnackBar(content: Text('No app to send it with.')));
  }
}

/// Emails a standard invitation (.ics) to the guests who have an email
/// address, from the user's mail app. Replies are recorded by hand.
Future<void> emailInvitation(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent event,
  List<Guest> guests,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final invited = [for (final g in guests) if (g.email != null) g];
  if (invited.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Add a guest with an email address first.')),
    );
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(event.inviteSequence == 0 ? 'Email invitation?' : 'Email updated invitation?'),
      content: Text(
        'Your mail app opens with an invitation to ${invited.map((g) => g.label).join(', ')}. '
        'Email isn\'t end-to-end encrypted: the event\'s title, time, place '
        'and description go in it. Attachments and linked notes don\'t.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Continue')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final email = ref.read(accountServiceProvider).currentEmail;
  final ics = Ics.write(
    [event],
    name: event.title,
    invite: IcsInvite(
      organizerEmail: email,
      guests: [for (final g in invited) (g.name, g.email!)],
    ),
  );
  final start = formatLongDay(event.start);
  final when = event.allDay ? start : '$start, ${formatTime(context, event.start)}';
  final sent = await sendInvitation(
    ics: ics,
    emails: [for (final g in invited) g.email!],
    subject: 'Invitation: ${event.title.trim().isEmpty ? 'Event' : event.title.trim()} ($when)',
    text: [
      'You\'re invited: ${event.title.trim()}',
      'When: $when',
      if (event.location.isNotEmpty) 'Where: ${event.location}',
      if (event.conferenceUrl != null) 'Join: ${event.conferenceUrl}',
      '',
      'Open the attached invite.ics to add it to your calendar.',
    ].join('\n'),
  );
  if (!sent) {
    messenger.showSnackBar(const SnackBar(content: Text('Not supported on this device.')));
    return;
  }
  // The next invitation for this event replaces this one in guests' calendars.
  await ref
      .read(calendarRepositoryProvider)
      .saveEvent(event.copyWith(inviteSequence: event.inviteSequence + 1));
}
