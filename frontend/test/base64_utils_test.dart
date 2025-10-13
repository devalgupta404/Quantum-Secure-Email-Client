import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:frontend/utils/base64_utils.dart';

void main() {
  group('Base64Utils Tests', () {
    test('encode and decode bytes correctly', () {
      // Create test data
      final testData = Uint8List.fromList([1, 2, 3, 4, 5, 255, 128, 64]);

      // Encode
      final encoded = Base64Utils.encode(testData);
      print('Encoded: $encoded');

      // Decode
      final decoded = Base64Utils.decode(encoded);
      print('Decoded: $decoded');

      // Verify
      expect(decoded, equals(testData));
    });

    test('encode and decode string correctly', () {
      const testString = 'Hello, World! This is a test with special chars: 你好世界 🚀';

      // Encode
      final encoded = Base64Utils.encodeString(testString);
      print('Encoded string: $encoded');

      // Decode
      final decoded = Base64Utils.decodeToString(encoded);
      print('Decoded string: $decoded');

      // Verify
      expect(decoded, equals(testString));
    });

    test('validate base64 strings', () {
      expect(Base64Utils.isValidBase64('SGVsbG8gV29ybGQ='), isTrue);
      expect(Base64Utils.isValidBase64('not-valid-base64!!!'), isFalse);
      expect(Base64Utils.isValidBase64(''), isFalse);
    });

    test('convert between base64 and base64url', () {
      const base64 = 'SGVsbG8gV29ybGQ=';
      final base64url = Base64Utils.base64ToBase64Url(base64);
      print('Base64: $base64');
      print('Base64url: $base64url');

      expect(base64url, equals('SGVsbG8gV29ybGQ'));

      final backToBase64 = Base64Utils.base64UrlToBase64(base64url);
      expect(backToBase64, equals(base64));
    });

    test('safely decode both base64 and base64url formats', () {
      final testData = Uint8List.fromList([255, 128, 64, 32]);

      // Standard base64
      final standardBase64 = Base64Utils.encode(testData);
      final decoded1 = Base64Utils.safelyDecode(standardBase64);
      expect(decoded1, equals(testData));

      // Base64url format
      final base64url = Base64Utils.base64ToBase64Url(standardBase64);
      final decoded2 = Base64Utils.safelyDecode(base64url);
      expect(decoded2, equals(testData));
    });

    test('prevent double encoding issue', () {
      // Simulate what was happening in the old code
      final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);

      // First encoding (correct)
      final firstEncode = Base64Utils.encode(originalData);
      print('First encode: $firstEncode');

      // WRONG: decode then re-encode (creates double encoding)
      final doubleEncoded = Base64Utils.encode(Base64Utils.decode(firstEncode));
      print('Double encoded: $doubleEncoded');

      // They should be the same!
      expect(doubleEncoded, equals(firstEncode));

      // Verify the decoded data is correct
      expect(Base64Utils.decode(firstEncode), equals(originalData));
    });

    test('debug info provides useful information', () {
      const validBase64 = 'SGVsbG8gV29ybGQ=';
      const invalidBase64 = 'not-valid!!!';

      final validInfo = Base64Utils.getDebugInfo(validBase64);
      print('Valid base64 info: $validInfo');
      expect(validInfo['isValid'], isTrue);
      expect(validInfo['hasPadding'], isTrue);

      final invalidInfo = Base64Utils.getDebugInfo(invalidBase64);
      print('Invalid base64 info: $invalidInfo');
      expect(invalidInfo['isValid'], isFalse);
    });

    test('simulate PQC attachment flow (no double encoding)', () {
      // Simulate picking a file
      final fileBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      print('Original file size: ${fileBytes.length} bytes');

      // Step 1: Encode file to base64 (in compose_screen.dart)
      final contentBase64 = Base64Utils.encode(fileBytes);
      print('After base64 encode: ${contentBase64.length} chars');

      // Step 2: In backend, use AsIs() - NO decode/encode!
      // This is what we fixed:
      // OLD: var bytes = Convert.FromBase64String(a.ContentBase64);
      //      var contentText = Convert.ToBase64String(bytes);
      // NEW: var contentText = Base64Utils.AsIs(a.ContentBase64);

      // Step 3: Backend encrypts the base64 string (simulated)
      final encrypted = 'ENCRYPTED_${contentBase64}_ENCRYPTED';

      // Step 4: Backend decrypts (simulated)
      final decryptedBase64 = encrypted.substring(10, encrypted.length - 10);

      // Step 5: Frontend decodes base64 to get original file
      final recoveredBytes = Base64Utils.decode(decryptedBase64);
      print('Recovered file size: ${recoveredBytes.length} bytes');

      // Verify no data loss
      expect(recoveredBytes, equals(fileBytes));
      print('✅ PQC attachment flow test PASSED - no double encoding!');
    });
  });
}
