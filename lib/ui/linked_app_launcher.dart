import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/linked_apps.dart';

const _channel = MethodChannel('zt_calendar/apps');

/// Opens ZT Notes, Tasks or Contacts, or its store page when it isn't
/// installed. Returns whether the app itself opened.
Future<bool> openLinkedApp(LinkedApp app) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _channel.invokeMethod<bool>('open', {
            'package': app.androidPackage,
          }) ??
          false;
    } on Object {
      // Fall through to the store link.
    }
  }
  await launchUrl(
    Uri.https('play.google.com', '/store/apps/details', {
      'id': app.androidPackage,
    }),
    mode: LaunchMode.externalApplication,
  );
  return false;
}

/// The phone's maps app for [location] (no particular maps provider).
Uri mapsUri(String location) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return Uri.https('maps.apple.com', '/', {'q': location});
  }
  return Uri.parse('geo:0,0?q=${Uri.encodeComponent(location)}');
}
