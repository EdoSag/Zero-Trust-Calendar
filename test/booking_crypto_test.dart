import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/booking/booking_crypto.dart';

void main() {
  // Sealed by the website's book/seal.js (WebCrypto) under Node.
  final fixture =
      jsonDecode(File('test/fixtures/booking_webcrypto.json').readAsStringSync())
          as Map<String, Object?>;
  final privateKey = base64.decode(fixture['privateKey']! as String);
  final start = DateTime.fromMillisecondsSinceEpoch(fixture['startMs']! as int);

  test('opens what the website sealed', () {
    expect(BookingKeyPair.publicKeyOf(privateKey), fixture['publicKey']);
    expect(
      openBooking(
        privateKey: privateKey,
        sealed: fixture['sealed']! as String,
        pageId: fixture['pageId']! as String,
        start: start,
      ),
      fixture['data'],
    );
  });

  test('a sealed text only fits its own page and start', () {
    Map<String, Object?> open(String pageId, DateTime at) => openBooking(
      privateKey: privateKey,
      sealed: fixture['sealed']! as String,
      pageId: pageId,
      start: at,
    );
    expect(() => open('page-other-000000000001', start), throwsA(anything));
    expect(
      () => open(fixture['pageId']! as String, start.add(const Duration(minutes: 30))),
      throwsA(anything),
    );
  });

  test('another key can\'t open it', () {
    final other = BookingKeyPair.generate(Random(1));
    expect(
      () => openBooking(
        privateKey: other.privateKey,
        sealed: fixture['sealed']! as String,
        pageId: fixture['pageId']! as String,
        start: start,
      ),
      throwsA(anything),
    );
  });

  test('round trip with a new key pair', () {
    final keys = BookingKeyPair.generate();
    expect(base64.decode(keys.publicKey), hasLength(65));
    final sealed = sealBooking(
      publicKey: keys.publicKey,
      data: {'name': 'Avi', 'email': 'avi@example.com'},
      pageId: 'page-abcdefghijklmnop',
      start: DateTime.utc(2026, 12, 1, 10),
    );
    expect(
      openBooking(
        privateKey: keys.privateKey,
        sealed: sealed,
        pageId: 'page-abcdefghijklmnop',
        start: DateTime.utc(2026, 12, 1, 10),
      ),
      {'name': 'Avi', 'email': 'avi@example.com'},
    );
  });
}
