import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/calendar_store.dart';
import '../data/find_a_time.dart';
import '../data/shared_calendars.dart';
import '../model/calendar_event.dart' show ZtCalendarInfo, calendarPalette;
import '../util/format.dart';
import 'find_a_time_page.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
}

/// The name this account already uses in its shared calendars, to suggest
/// it again.
String _myKnownName(WidgetRef ref) {
  try {
    final me = ref.read(accountServiceProvider).currentUserId;
    for (final c in ref.read(sharedCalendarsProvider).value ?? const []) {
      for (final m in c.members) {
        if (m.userId == me && m.name.trim().isNotEmpty) return m.name;
      }
    }
  } on Object {
    // Signed out or offline: no suggestion.
  }
  return '';
}

/// Asks for the calendar's name, colour and how the others will see this
/// account, then makes the shared calendar. [family] suggests "Family".
Future<void> createSharedCalendar(
  BuildContext context,
  WidgetRef ref, {
  bool family = false,
}) async {
  final l = context.l10n;
  final name = TextEditingController(text: family ? l.familyCalendarName : '');
  final myName = TextEditingController(text: _myKnownName(ref));
  final form = GlobalKey<FormState>();
  var color = family ? 0xFF10B981 : 0xFF3B82F6;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: Text(family ? l.newFamilyCalendar : l.newSharedCalendar),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.sharedCalendarIntro),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  autofocus: !family,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.name),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l.requiredField : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: myName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.yourName,
                    helperText: l.yourNameHint,
                    helperMaxLines: 3,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l.requiredField : null,
                ),
                const SizedBox(height: 16),
                _Palette(
                  color: color,
                  onPick: (c) => setState(() => color = c),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.of(dialog).pop(true);
            },
            child: Text(l.create),
          ),
        ],
      ),
    ),
  );
  final calendarName = name.text.trim();
  final me = myName.text.trim();
  name.dispose();
  myName.dispose();
  if (ok != true || !context.mounted) return;
  try {
    final id = await ref
        .read(sharedCalendarActionsProvider)
        .create(name: calendarName, color: color, myName: me, family: family);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvitePage(spaceId: spaceIdOf(id)!),
      ),
    );
  } on Object {
    if (context.mounted) _snack(context, l.needsInternet);
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.color, required this.onPick});
  final int color;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in calendarPalette)
        Semantics(
          button: true,
          selected: c == color,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onPick(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
              ),
              child: c == color
                  ? Icon(Icons.check, size: 18, color: onColor(Color(c)))
                  : null,
            ),
          ),
        ),
    ],
  );
}

/// One shared calendar: its members, invites, this member's own colour and
/// visibility, and leave or delete.
class SharedCalendarPage extends ConsumerWidget {
  const SharedCalendarPage({super.key, required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final shared = (ref.watch(sharedCalendarsProvider).value ?? const [])
        .where((c) => c.spaceId == spaceId)
        .firstOrNull;
    final mine = (ref.watch(calendarsProvider).value ?? const [])
        .where((c) => c.id == sharedCalendarId(spaceId))
        .firstOrNull;
    if (shared == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.sharedCalendarGone)),
      );
    }
    if (shared.waiting) return _WaitingPage(calendar: shared);
    final me = ref.read(accountServiceProvider).currentUserId;
    final joins = [
      for (final j
          in ref.watch(pendingJoinsProvider).value ?? const <PendingJoin>[])
        if (j.spaceId == spaceId) j,
    ];
    final name = mine?.name ?? shared.info.name;
    final color = mine?.color ?? shared.info.color;
    final members = [...shared.members]
      ..sort((a, b) {
        if (a.role != b.role) return a.role == SpaceRole.admin ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        children: [
          for (final j in joins)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text(l.joinRequest(j.name)),
                subtitle: Text(l.joinRequestHint),
                onTap: () => confirmJoin(context, ref, j, calendarName: name),
              ),
            ),
          ListTile(
            leading: Icon(
              shared.family ? Icons.family_restroom : Icons.group,
              color: Color(color),
            ),
            title: Text(name),
            subtitle: Text(
              shared.isAdmin ? l.sharedYouAreAdmin : l.sharedYouAreMember,
            ),
            trailing: shared.isAdmin ? const Icon(Icons.edit_outlined) : null,
            onTap: shared.isAdmin
                ? () => _rename(context, ref, shared, name)
                : null,
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: Color(color)),
            title: Text(l.myColour),
            subtitle: Text(l.myColourHint),
            onTap: () => _pickColour(context, ref, mine, shared),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(l.showInMyCalendar),
            value: !(mine?.hidden ?? false),
            onChanged: (show) => ref
                .read(sharedCalendarActionsProvider)
                .saveMyChoice(_choice(mine, shared).copyWith(hidden: !show)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_busy_outlined),
            title: Text(l.shareBusyTimes),
            subtitle: Text(l.shareBusyTimesHint),
            // The busy item in the space is the switch, so all of this
            // account's phones agree on it.
            value: shared.busy.any((b) => b.userId == me),
            onChanged: (on) => _setSharingBusy(context, ref, shared, on),
          ),
          ListTile(
            leading: const Icon(Icons.manage_search),
            title: Text(l.findATime),
            subtitle: Text(
              l.findATimeSharing(
                shared.busy
                    .where((b) => members.any((m) => m.userId == b.userId))
                    .length,
                members.length,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FindATimePage(spaceId: spaceId),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l.nMembers(members.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final m in members)
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  m.name.trim().isEmpty ? '?' : m.name.trim()[0].toUpperCase(),
                ),
              ),
              title: Text(m.userId == me ? l.memberYou(m.name) : m.name),
              subtitle: Text(
                m.role == SpaceRole.admin ? l.roleAdmin : l.roleMember,
              ),
              trailing: shared.isAdmin && m.userId != me
                  ? PopupMenuButton<String>(
                      tooltip: l.memberOptions,
                      onSelected: (v) => _memberAction(context, ref, m, v),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Text(
                            m.role == SpaceRole.admin
                                ? l.makeMember
                                : l.makeAdmin,
                          ),
                        ),
                        PopupMenuItem(value: 'remove', child: Text(l.remove)),
                      ],
                    )
                  : null,
            ),
          if (shared.isAdmin)
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text(l.invitePeople),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InvitePage(spaceId: spaceId),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.sharedPrivacyNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.leaveCalendar),
            onTap: () => _leave(context, ref, name),
          ),
          if (shared.isAdmin)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l.deleteForEveryone,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _delete(context, ref, name),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  ZtCalendarInfo _choice(ZtCalendarInfo? mine, SharedCalendar shared) =>
      ZtCalendarInfo(
        id: shared.id,
        name: shared.info.name,
        color: mine?.color ?? shared.info.color,
        hidden: mine?.hidden ?? false,
      );

  Future<void> _pickColour(
    BuildContext context,
    WidgetRef ref,
    ZtCalendarInfo? mine,
    SharedCalendar shared,
  ) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.l10n.myColour),
        content: _Palette(
          color: mine?.color ?? shared.info.color,
          onPick: (c) => Navigator.of(d).pop(c),
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(sharedCalendarActionsProvider)
        .saveMyChoice(_choice(mine, shared).copyWith(color: picked));
  }


  Future<void> _setSharingBusy(
    BuildContext context,
    WidgetRef ref,
    SharedCalendar shared,
    bool on,
  ) async {
    final actions = ref.read(sharedCalendarActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      if (on) {
        await actions.publishBusy(
          shared.spaceId,
          busyBlocks(
            events: [
              ...?ref.read(eventsProvider).value,
              ...ref.read(sharedEventsProvider),
            ],
            calendars:
                ref.read(calendarsProvider).value ??
                const [ZtCalendarInfo.personal],
            from: dayOf(DateTime.now()),
            exceptCalendarId: shared.id,
          ),
        );
      } else {
        await actions.withdrawBusy(shared.spaceId);
      }
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.couldNotSave('$e')),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SharedCalendar shared,
    String current,
  ) async {
    final l = context.l10n;
    final name = TextEditingController(text: shared.info.name);
    var color = shared.info.color;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text(l.editCalendar),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.name),
                ),
                const SizedBox(height: 12),
                Text(l.sharedRenameHint),
                const SizedBox(height: 12),
                _Palette(
                  color: color,
                  onPick: (c) => setState(() => color = c),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    final text = name.text.trim();
    name.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(sharedCalendarActionsProvider)
          .saveInfo(
            shared.spaceId,
            name: text.isEmpty ? current : text,
            color: color,
            family: shared.family,
          );
    } on Object {
      if (context.mounted) _snack(context, l.needsInternet);
    }
  }

  Future<void> _memberAction(
    BuildContext context,
    WidgetRef ref,
    SpaceMember m,
    String action,
  ) async {
    final l = context.l10n;
    final spaces = ref.read(ztSpacesProvider.notifier);
    try {
      if (action == 'role') {
        await spaces.setRole(
          spaceId,
          m.userId,
          m.role == SpaceRole.admin ? SpaceRole.member : SpaceRole.admin,
        );
      } else if (action == 'remove') {
        final ok = await _confirm(
          context,
          l.removeMemberTitle(m.name),
          l.removeMemberBody,
          l.remove,
        );
        if (ok) await spaces.remove(spaceId, m.userId);
      }
      ref.read(sharedRevisionProvider.notifier).bump();
    } on Object {
      if (context.mounted) _snack(context, l.needsInternet);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, String name) async {
    final l = context.l10n;
    if (!await _confirm(
      context,
      l.leaveCalendarTitle(name),
      l.leaveCalendarBody,
      l.leaveCalendar,
    )) {
      return;
    }
    try {
      await ref.read(sharedCalendarActionsProvider).leave(spaceId);
      if (context.mounted) Navigator.of(context).pop();
    } on Object {
      if (context.mounted) _snack(context, l.needsInternet);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final l = context.l10n;
    if (!await _confirm(
      context,
      l.deleteForEveryoneTitle(name),
      l.deleteForEveryoneBody,
      l.delete,
    )) {
      return;
    }
    try {
      await ref.read(sharedCalendarActionsProvider).delete(spaceId);
      if (context.mounted) Navigator.of(context).pop();
    } on Object {
      if (context.mounted) _snack(context, l.needsInternet);
    }
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// A calendar this account asked to join: the code to compare with the
/// admin, until they let it in.
class _WaitingPage extends ConsumerWidget {
  const _WaitingPage({required this.calendar});
  final SharedCalendar calendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.waitingToJoin)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.hourglass_top, size: 48),
          const SizedBox(height: 16),
          Text(l.waitingToJoinBody, textAlign: TextAlign.center),
          if (calendar.joinCode case final code?) ...[
            const SizedBox(height: 16),
            Text(
              code,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(letterSpacing: 3),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              try {
                await ref
                    .read(sharedCalendarActionsProvider)
                    .leave(calendar.spaceId);
                if (context.mounted) Navigator.of(context).pop();
              } on Object {
                if (context.mounted) _snack(context, l.needsInternet);
              }
            },
            child: Text(l.cancelJoin),
          ),
        ],
      ),
    );
  }
}

/// People who answered this account's invites, across its calendars.
final pendingJoinsProvider = FutureProvider<List<PendingJoin>>((ref) async {
  ref.watch(sharedRevisionProvider);
  final spaces = ref.watch(ztSpacesProvider);
  final controller = ref.read(ztSpacesProvider.notifier);
  final out = <PendingJoin>[];
  for (final e in spaces.entries) {
    if (e.info.myRole != SpaceRole.admin || e.space == null) continue;
    try {
      out.addAll(await controller.pendingJoins(e.info.id));
    } on Object {
      // Offline: shown on the next try.
    }
  }
  return out;
});

/// The admin compares the code on the other person's phone, then lets them
/// in.
Future<void> confirmJoin(
  BuildContext context,
  WidgetRef ref,
  PendingJoin j, {
  required String calendarName,
}) async {
  final l = context.l10n;
  final spaces = ref.read(ztSpacesProvider.notifier);
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.confirmJoinTitle(j.name, calendarName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.confirmJoinBody),
          const SizedBox(height: 16),
          Text(
            j.verificationCode,
            style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 2,
            ),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 8),
          Text(j.role == SpaceRole.admin ? l.roleAdmin : l.roleMember),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'reject'),
          child: Text(l.codesDiffer),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.later)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'ok'),
          child: Text(l.codesMatch),
        ),
      ],
    ),
  );
  try {
    if (choice == 'ok') {
      await spaces.confirm(j);
      if (context.mounted) _snack(context, l.joinedCalendar(j.name));
    } else if (choice == 'reject') {
      await spaces.revokeInvite(j.inviteId);
    } else {
      return;
    }
  } on Object {
    if (context.mounted) _snack(context, l.needsInternet);
  }
  ref.read(sharedRevisionProvider.notifier).bump();
}

/// Invites someone to a shared calendar: a link to send, or a QR code to
/// scan in person. Then shows who answered, to confirm with the code.
class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  SpaceRole _role = SpaceRole.member;
  SpaceInviteLink? _link;
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(ztSpacesProvider.notifier)
          .invite(widget.spaceId, role: _role);
      if (mounted) setState(() => _link = link);
    } on Object {
      if (mounted) _snack(context, context.l10n.needsInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final name =
        (ref.watch(calendarsProvider).value ?? const [])
            .where((c) => c.id == sharedCalendarId(widget.spaceId))
            .firstOrNull
            ?.name ??
        '';
    final joins = [
      for (final j
          in ref.watch(pendingJoinsProvider).value ?? const <PendingJoin>[])
        if (j.spaceId == widget.spaceId) j,
    ];
    final link = _link;
    return Scaffold(
      appBar: AppBar(title: Text(l.inviteTo(name))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final j in joins)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text(l.joinRequest(j.name)),
                subtitle: Text(l.joinRequestHint),
                onTap: () => confirmJoin(context, ref, j, calendarName: name),
              ),
            ),
          if (link == null) ...[
            Text(l.inviteIntro),
            const SizedBox(height: 16),
            SegmentedButton<SpaceRole>(
              segments: [
                ButtonSegment(
                  value: SpaceRole.member,
                  label: Text(l.roleMember),
                ),
                ButtonSegment(value: SpaceRole.admin, label: Text(l.roleAdmin)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _role == SpaceRole.admin ? l.roleAdminHint : l.roleMemberHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.qr_code),
              label: Text(l.createInvite),
            ),
          ] else ...[
            Text(l.inviteReady, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: link.qrData,
                  size: 240,
                  semanticsLabel: l.inviteQr,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: link.toString()),
                      );
                      if (context.mounted) _snack(context, l.linkCopied);
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(l.copyLink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: l.inviteMessage(name, link.toString())),
                    ),
                    icon: const Icon(Icons.share),
                    label: Text(l.shareLink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l.inviteNextSteps,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => ref.invalidate(pendingJoinsProvider),
              icon: const Icon(Icons.refresh),
              label: Text(l.checkForAnswers),
            ),
          ],
        ],
      ),
    );
  }
}

/// Joins a shared calendar from an invite link (pasted, scanned, or opened
/// from a message), then shows the code to compare with the admin.
class JoinCalendarPage extends ConsumerStatefulWidget {
  const JoinCalendarPage({super.key, this.initialLink});
  final String? initialLink;

  @override
  ConsumerState<JoinCalendarPage> createState() => _JoinCalendarPageState();
}

class _JoinCalendarPageState extends ConsumerState<JoinCalendarPage> {
  late final _link = TextEditingController(text: widget.initialLink);
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _code;

  @override
  void initState() {
    super.initState();
    _name.text = _myKnownName(ref);
  }

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  String? _validLink(String? v) {
    try {
      final link = SpaceInviteLink.parse(v ?? '');
      if (link.app != 'calendar') return context.l10n.inviteOtherApp;
      return null;
    } on FormatException {
      return context.l10n.inviteInvalid;
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (text != null) setState(() => _link.text = text);
  }

  Future<void> _join() async {
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final started = await ref
          .read(ztSpacesProvider.notifier)
          .answer(SpaceInviteLink.parse(_link.text), myName: _name.text.trim());
      ref.read(sharedRevisionProvider.notifier).bump();
      if (mounted) setState(() => _code = started.verificationCode);
    } on SpaceRefused {
      if (mounted) _snack(context, l.inviteUsed);
    } on Object {
      if (mounted) _snack(context, l.needsInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: Text(l.joinSharedCalendar)),
      body: code != null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.verified_user_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  l.joinCodeTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  code,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(letterSpacing: 3),
                ),
                const SizedBox(height: 16),
                Text(l.joinCodeBody, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.done),
                ),
              ],
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l.joinIntro),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _link,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l.inviteLink,
                      suffixIcon: IconButton(
                        tooltip: l.scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scan,
                      ),
                    ),
                    validator: _validLink,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.yourName,
                      helperText: l.yourNameHint,
                      helperMaxLines: 3,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? l.requiredField : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: _busy ? null : _join,
                    child: Text(l.join),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _key = GlobalKey(debugLabel: 'qr');
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.scanQr)),
    body: QRView(
      key: _key,
      overlay: QrScannerOverlayShape(
        borderColor: Theme.of(context).colorScheme.primary,
        borderRadius: 12,
        borderLength: 32,
        borderWidth: 8,
        cutOutSize: 260,
      ),
      onQRViewCreated: (controller) {
        controller.scannedDataStream.listen((b) {
          final code = b.code;
          if (_done || code == null) return;
          try {
            SpaceInviteLink.parse(code);
          } on FormatException {
            return;
          }
          _done = true;
          controller.pauseCamera();
          if (context.mounted) Navigator.of(context).pop(code);
        });
      },
    ),
  );
}

/// The calendars page's "+" choices.
Future<void> showNewCalendarChoices(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback newCalendar,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheet) {
    final l = context.l10n;
    void go(VoidCallback action) {
      Navigator.of(sheet).pop();
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(l.newCalendar),
            subtitle: Text(l.newCalendarHint),
            onTap: () => go(newCalendar),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(l.newSharedCalendar),
            subtitle: Text(l.newSharedCalendarHint),
            onTap: () => go(() => createSharedCalendar(context, ref)),
          ),
          ListTile(
            leading: const Icon(Icons.family_restroom),
            title: Text(l.newFamilyCalendar),
            subtitle: Text(l.newFamilyCalendarHint),
            onTap: () =>
                go(() => createSharedCalendar(context, ref, family: true)),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l.joinSharedCalendar),
            subtitle: Text(l.joinSharedCalendarHint),
            onTap: () => go(
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JoinCalendarPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  },
);
