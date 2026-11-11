import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Something another app opened Calendar with: an .ics file (an invitation
/// from a mail app, a download), a webcal:// subscribe link or a shared
/// calendar invite.
@immutable
class IncomingFile {
  const IncomingFile({this.name, this.bytes, this.url, this.invite});
  final String? name;
  final Uint8List? bytes;

  /// A shared calendar invite link (https://zerotrust.bz/join#…).
  final String? invite;

  /// For a subscribe link: the https:// address of the calendar.
  final String? url;
}

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Files Android handed to Calendar. They wait in the activity until the
/// unlocked app [take]s them, so nothing is read while the vault is locked.
class IncomingFiles {
  IncomingFiles._() {
    if (_android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'filesArrived') _arrived.add(null);
      });
    }
  }

  static final instance = IncomingFiles._();
  static const _channel = MethodChannel('zt_calendar/files');
  final _arrived = StreamController<void>.broadcast();

  /// Fires when a new file arrives while the app is running.
  Stream<void> get arrived => _arrived.stream;

  Future<List<IncomingFile>> take() async {
    if (!_android) return const [];
    try {
      final list = await _channel.invokeListMethod<Object?>('takePending') ?? const [];
      return [
        for (final item in list)
          if (item is Map)
            IncomingFile(
              name: item['name'] as String?,
              bytes: item['bytes'] as Uint8List?,
              url: item['url'] as String?,
              invite: item['invite'] as String?,
            ),
      ];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// Opens the mail app with an invitation: guests, subject, text and the
/// .ics file attached. Returns false where that isn't supported.
Future<bool> sendInvitation({
  required String ics,
  required List<String> emails,
  required String subject,
  required String text,
}) async {
  if (!_android) return false;
  final dir = Directory('${(await getTemporaryDirectory()).path}/invites');
  await dir.create(recursive: true);
  final file = File('${dir.path}/invite.ics');
  await file.writeAsString(ics, flush: true);
  await const MethodChannel('zt_calendar/apps').invokeMethod<bool>('sendInvite', {
    'path': file.path,
    'emails': emails,
    'subject': subject,
    'text': text,
  });
  return true;
}

/// Android's calendar, for "Show on this phone" (see PhoneCalendar.kt).
class PhoneCalendarBridge {
  const PhoneCalendarBridge();
  static const _channel = MethodChannel('zt_calendar/phone_calendar');

  bool get supported => _android;

  Future<bool> hasPermission() async =>
      _android && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  Future<bool> requestPermission() async =>
      _android && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  /// Makes Android's ZT calendars exactly [calendars] (see
  /// [phoneCalendarPayload]); an empty list removes them all.
  Future<bool> sync(List<Map<String, Object?>> calendars) async {
    if (!_android) return false;
    return await _channel.invokeMethod<bool>('sync', {'calendars': calendars}) ?? false;
  }
}
