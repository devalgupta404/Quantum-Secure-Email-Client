import 'dart:convert';
import 'dart:typed_data';

/// Base64 utility functions for consistent encoding/decoding across all encryption layers
///
/// These utilities ensure that base64 operations are performed correctly and consistently
/// throughout the application, preventing double-encoding issues in PQC triple-layer encryption.
class Base64Utils {
  /// Encodes bytes to standard base64 string
  ///
  /// Use this for initial encoding of file data or any binary data
  static String encode(Uint8List bytes) {
    return base64Encode(bytes);
  }

  /// Encodes UTF-8 string to base64
  ///
  /// Use this when you need to encode text content
  static String encodeString(String text) {
    return base64Encode(utf8.encode(text));
  }

  /// Decodes standard base64 string to bytes
  ///
  /// Use this for decoding file data or any binary data
  /// Throws FormatException if the input is not valid base64
  static Uint8List decode(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (e) {
      throw FormatException('Invalid base64 string: $e');
    }
  }

  /// Decodes base64 string to UTF-8 string
  ///
  /// Use this when you need to decode text content
  /// Throws FormatException if the input is not valid base64
  static String decodeToString(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      return utf8.decode(bytes);
    } catch (e) {
      throw FormatException('Invalid base64 string or UTF-8 encoding: $e');
    }
  }

  /// Validates if a string is valid base64
  ///
  /// Returns true if the string is valid base64, false otherwise
  static bool isValidBase64(String value) {
    if (value.isEmpty) return false;

    try {
      base64Decode(value);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Converts base64url to standard base64
  ///
  /// Base64url uses - and _ instead of + and /
  /// This is often used in URLs and tokens
  static String base64UrlToBase64(String base64Url) {
    // First restore any stripped padding
    String base64 = base64Url.replaceAll('-', '+').replaceAll('_', '/');

    // Add padding if needed (base64url strips padding)
    while (base64.length % 4 != 0) {
      base64 += '=';
    }

    return base64;
  }

  /// Converts standard base64 to base64url
  ///
  /// Removes padding and replaces + and / with - and _
  static String base64ToBase64Url(String base64) {
    return base64
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  /// Safely decodes base64, handling both standard and base64url formats
  ///
  /// This is useful when you're not sure which format the input is in
  static Uint8List safelyDecode(String base64String) {
    try {
      // Try standard base64 first
      return base64Decode(base64String);
    } catch (e) {
      try {
        // Try base64url format
        final standardBase64 = base64UrlToBase64(base64String);
        return base64Decode(standardBase64);
      } catch (e2) {
        throw FormatException('Invalid base64 string (tried both standard and base64url): $e, $e2');
      }
    }
  }

  /// Debug helper: Returns info about a base64 string
  ///
  /// Useful for troubleshooting encoding issues
  static Map<String, dynamic> getDebugInfo(String base64String) {
    return {
      'length': base64String.length,
      'isValid': isValidBase64(base64String),
      'hasStandardChars': base64String.contains('+') || base64String.contains('/'),
      'hasUrlChars': base64String.contains('-') || base64String.contains('_'),
      'hasPadding': base64String.contains('='),
      'preview': base64String.length > 100
          ? '${base64String.substring(0, 50)}...${base64String.substring(base64String.length - 50)}'
          : base64String,
    };
  }
}
