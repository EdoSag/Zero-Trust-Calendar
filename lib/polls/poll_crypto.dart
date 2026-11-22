import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encryption for meeting polls (K-5).
///
/// A poll's link is `https://zerotrust.bz/poll/#<poll id>.<key>`: the key
/// (32 random bytes, base64url) lives only in the fragment, which browsers
/// never send to a server. The poll itself (title, times, place) and every
/// guest's vote are AES-256-GCM encrypted with it, with
/// `zt-poll-v1|<poll id>|poll` or `...|vote` as associated data, so a sealed
/// text can't be moved to another poll or swapped between the two kinds.
/// The website (poll/poll.js) does the same with WebCrypto; keep them in
/// step.
///
/// Sealed text: `{"v":1,"iv":<12 bytes>,"ct":<ciphertext+tag>}`, standard
/// base64.
const pollSealInfo = 'zt-poll-v1';

/// Where guests open a poll.
const pollSiteBase = 'https://zerotrust.bz/poll/';

Uint8List _random(int n, Random? random) {
  final r = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

String _url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A fresh poll id: "p" and 22 URL-safe characters.
String newPollId([Random? random]) => 'p${_url(_random(16, random))}';

/// A fresh poll key, as it goes in the link.
String newPollKey([Random? random]) => _url(_random(32, random));

Uint8List pollKeyBytes(String key) {
  final bytes = base64Url.decode(base64Url.normalize(key));
  if (bytes.length != 32) throw const FormatException('Bad poll key');
  return bytes;
}

/// The link guests open.
String pollLink(String pollId, String key) => '$pollSiteBase#$pollId.$key';

Uint8List _aad(String pollId, String part) =>
    Uint8List.fromList(utf8.encode('$pollSealInfo|$pollId|$part'));

/// Seals [data] for the poll [pollId]; [part] is `poll` or `vote`.
String sealForPoll({
  required String key,
  required String pollId,
  required String part,
  required Map<String, Object?> data,
  Random? random,
}) {
  final iv = _random(12, random);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(pollKeyBytes(key)), 128, iv, _aad(pollId, part)));
  final ct = cipher.process(Uint8List.fromList(utf8.encode(jsonEncode(data))));
  return jsonEncode({'v': 1, 'iv': base64.encode(iv), 'ct': base64.encode(ct)});
}

/// Opens a text [sealForPoll] (or the website) made. Throws when it was
/// sealed with another key, for another poll or part, or changed.
Map<String, Object?> openForPoll({
  required String key,
  required String pollId,
  required String part,
  required String sealed,
}) {
  final env = jsonDecode(sealed);
  if (env is! Map || env['v'] != 1) throw const FormatException('Unknown sealed version');
  final iv = base64.decode(env['iv'] as String);
  final ct = base64.decode(env['ct'] as String);
  if (iv.length != 12 || ct.length < 16) throw const FormatException('Bad sealed text');
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(pollKeyBytes(key)), 128, iv, _aad(pollId, part)));
  final plain = cipher.process(ct);
  return Map<String, Object?>.from(jsonDecode(utf8.decode(plain)) as Map);
}
