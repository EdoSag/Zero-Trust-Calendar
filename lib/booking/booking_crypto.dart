import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Sealing a visitor's details for a booking page (K15).
///
/// The booking page in the browser seals the visitor's name, email and note
/// to the page's public key, so the server that holds the booking can't read
/// them; only the owner's phone, which keeps the private key in the
/// encrypted vault, opens them. Same scheme as the website's /book/ page
/// (WebCrypto): ECDH on P-256 with a fresh key per booking, HKDF-SHA256
/// (32 zero bytes of salt, info "zt-booking-v1") to an AES-256-GCM key, and
/// the page id and start time as associated data, so a sealed text can't be
/// moved to another booking.
///
/// Sealed text: `{"v":1,"epk":<65-byte point>,"iv":<12 bytes>,"ct":<ciphertext+tag>}`,
/// all standard base64.
const bookingSealInfo = 'zt-booking-v1';

final _domain = ECDomainParameters('secp256r1');

/// A booking page's key pair: [privateKey] (32 bytes) stays in the vault,
/// [publicKey] (65-byte uncompressed point, base64) goes to the server.
class BookingKeyPair {
  const BookingKeyPair(this.privateKey, this.publicKey);
  final Uint8List privateKey;
  final String publicKey;

  static BookingKeyPair generate([Random? random]) {
    final r = random ?? Random.secure();
    while (true) {
      final d = Uint8List.fromList(
        List<int>.generate(32, (_) => r.nextInt(256)),
      );
      final k = _bigInt(d);
      if (k == BigInt.zero || k >= _domain.n) continue;
      return BookingKeyPair(d, publicKeyOf(d));
    }
  }

  static String publicKeyOf(Uint8List privateKey) =>
      base64.encode((_domain.G * _bigInt(privateKey))!.getEncoded(false));
}

/// The associated data binding a sealed text to its booking.
Uint8List bookingAad(String pageId, DateTime start) => Uint8List.fromList(
  utf8.encode(
    '$bookingSealInfo|$pageId|${start.toUtc().millisecondsSinceEpoch}',
  ),
);

/// Opens [sealed] with the page's [privateKey]. Throws when it was sealed
/// to another key, changed, or moved to another booking.
Map<String, Object?> openBooking({
  required Uint8List privateKey,
  required String sealed,
  required String pageId,
  required DateTime start,
}) {
  final env = jsonDecode(sealed) as Map<String, Object?>;
  if (env['v'] != 1) throw const FormatException('Unknown sealed version');
  final epk = base64.decode(env['epk']! as String);
  final iv = base64.decode(env['iv']! as String);
  final ct = base64.decode(env['ct']! as String);
  if (iv.length != 12 || ct.length < 16) {
    throw const FormatException('Bad sealed text');
  }
  final key = _derive(_shared(privateKey, epk));
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, bookingAad(pageId, start)),
    );
  final plain = cipher.process(ct);
  return Map<String, Object?>.from(jsonDecode(utf8.decode(plain)) as Map);
}

/// Seals [data] to [publicKey] the way the website does (used in tests and
/// to check a page's key).
String sealBooking({
  required String publicKey,
  required Map<String, Object?> data,
  required String pageId,
  required DateTime start,
  Random? random,
}) {
  final eph = BookingKeyPair.generate(random);
  final r = random ?? Random.secure();
  final iv = Uint8List.fromList(List<int>.generate(12, (_) => r.nextInt(256)));
  final key = _derive(_shared(eph.privateKey, base64.decode(publicKey)));
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, bookingAad(pageId, start)),
    );
  final ct = cipher.process(Uint8List.fromList(utf8.encode(jsonEncode(data))));
  return jsonEncode({
    'v': 1,
    'epk': eph.publicKey,
    'iv': base64.encode(iv),
    'ct': base64.encode(ct),
  });
}

Uint8List _shared(Uint8List privateKey, List<int> point) {
  if (point.length != 65 || point[0] != 4) {
    throw const FormatException('Bad public key');
  }
  final q = _domain.curve.decodePoint(point);
  if (q == null || q.isInfinity) throw const FormatException('Bad public key');
  final s = (q * _bigInt(privateKey))!;
  if (s.isInfinity) throw const FormatException('Bad public key');
  return _bytes32(s.x!.toBigInteger()!);
}

Uint8List _derive(Uint8List shared) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(
        shared,
        32,
        Uint8List(32),
        Uint8List.fromList(utf8.encode(bookingSealInfo)),
      ),
    );
  final out = Uint8List(32);
  hkdf.deriveKey(null, 0, out, 0);
  return out;
}

BigInt _bigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List _bytes32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}
