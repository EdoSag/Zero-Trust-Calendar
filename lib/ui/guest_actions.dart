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
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// One guest: a ZT Contacts contact, or an email address.
@immutable
class Guest {
  const Guest({required this.key, this.name, this.email, this.phone});

  /// Contact id, or the email address (also the key in `guestStatus`).
  final String key;
  final String? name;
  final String? email;
  final String? phone;

  String get label => name ?? email ?? currentL10n.guest;
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

Map<String, (String, IconData)> get rsvpLabels => {
  'accepted': (currentL10n.going, Icons.check_circle_outline),
  'tentative': (currentL10n.maybe, Icons.help_outline),
  'declined': (currentL10n.notGoing, Icons.cancel_outlined),
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
      SnackBar(content: Text(context.l10n.noPhoneNumbersOrEmail)),
    );
    return;
  }
  final minutes = await showDialog<int>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(context.l10n.runningLate),
      children: [
        for (final m in const [5, 10, 15, 30])
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(context.l10n.aboutMinutes(m)),
            ),
          ),
      ],
    ),
  );
  if (minutes == null || !context.mounted) return;
  final title = event.title.trim().isEmpty ? context.l10n.ourMeeting : '"${event.title.trim()}"';
  final text = context.l10n.runningLateText(minutes, title);
  var useSms = phones.isNotEmpty;
  if (phones.isNotEmpty && emails.isNotEmpty) {
    final pick = await showDialog<bool>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(context.l10n.sendBy),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(true),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(context.l10n.textMessage),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop(false),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(context.l10n.email),
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
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.noAppToSendIt)));
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
      SnackBar(content: Text(context.l10n.addAGuestWithAn)),
    );
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(event.inviteSequence == 0 ? context.l10n.emailInvitationX : context.l10n.emailUpdatedInvitation),
      content: Text(
        context.l10n.inviteEmailWarning(invited.map((g) => g.label).join(', ')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.continueLabel)),
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
    subject: context.l10n.inviteSubject(event.title.trim().isEmpty ? context.l10n.event : event.title.trim(), when),
    text: [
      context.l10n.inviteYoureInvited(event.title.trim()),
      context.l10n.inviteWhen(when),
      if (event.location.isNotEmpty) context.l10n.inviteWhere(event.location),
      if (event.conferenceUrl != null) context.l10n.inviteJoin(event.conferenceUrl!),
      '',
      context.l10n.openTheAttachedInviteIcs,
    ].join('\n'),
  );
  if (!sent) {
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.notSupportedOnThisDevice)));
    return;
  }
  // The next invitation for this event replaces this one in guests' calendars.
  await ref
      .read(calendarRepositoryProvider)
      .saveEvent(event.copyWith(inviteSequence: event.inviteSequence + 1));
}
