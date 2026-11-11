import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../caldav/caldav_bridge.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// "Desktop calendar apps" (K16): turns the read-only CalDAV bridge on or
/// off and shows what to type into Thunderbird, Apple Calendar, GNOME
/// Evolution or DAVx5.
class DesktopBridgePage extends ConsumerStatefulWidget {
  const DesktopBridgePage({super.key});

  @override
  ConsumerState<DesktopBridgePage> createState() => _DesktopBridgePageState();
}

class _DesktopBridgePageState extends ConsumerState<DesktopBridgePage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(desktopBridgeProvider.notifier).refreshAddress();
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    await ref.read(desktopBridgeProvider.notifier).setEnabled(on);
    if (mounted) setState(() => _busy = false);
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.copied),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(desktopBridgeProvider);
    final c = s.credentials;
    final mono = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontFamily: 'monospace');
    Widget field(String label, String value, {String? semantics}) => ListTile(
      title: Text(label),
      subtitle: Text(
        value,
        style: mono,
        textDirection: TextDirection.ltr,
        semanticsLabel: semantics,
      ),
      trailing: IconButton(
        tooltip: l.copy,
        icon: const Icon(Icons.copy),
        onPressed: () => _copy(value),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.desktopApps)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.desktopAppsIntro),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.computer),
            title: Text(l.desktopAppsSwitch),
            subtitle: Text(
              s.running
                  ? l.desktopAppsRunning
                  : s.enabled
                  ? l.desktopAppsStarting
                  : l.desktopAppsOff,
            ),
            value: s.enabled,
            onChanged: _busy ? null : _toggle,
          ),
          if (s.error != null)
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l.desktopAppsFailed),
              subtitle: Text(s.error!),
            ),
          if (s.running && c != null) ...[
            const Divider(),
            if (s.url case final url?)
              field(l.desktopAppsServer, url)
            else
              ListTile(
                leading: const Icon(Icons.wifi_off),
                title: Text(l.desktopAppsNoWifi),
              ),
            field(l.desktopAppsUser, c.username),
            field(l.desktopAppsPassword, c.password),
            ListTile(
              title: Text(l.desktopAppsFingerprint),
              subtitle: Text(
                c.fingerprint,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                textDirection: TextDirection.ltr,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.desktopAppsHowTo,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(l.desktopAppsNewPassword),
              subtitle: Text(l.desktopAppsNewPasswordHint),
              onTap: () =>
                  ref.read(desktopBridgeProvider.notifier).newPassword(),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.desktopAppsPrivacy,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
