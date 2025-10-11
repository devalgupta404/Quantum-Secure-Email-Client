import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EmailService {
  static const String _baseUrl = 'http://localhost:5001/api';
  // PQC key pairs with persistence
  static String? _pqcPrivateKey;
  static String? _pqcPublicKey;
  
  static void setPqcPrivateKey(String key) => _pqcPrivateKey = key;
  static void setPqcPublicKey(String key) => _pqcPublicKey = key;
  static String? get pqcPrivateKey => _pqcPrivateKey;
  static String? get pqcPublicKey => _pqcPublicKey;
  
  // Get authentication token
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
  
  // Key persistence methods
  static Future<void> _savePqcKeys(String publicKey, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pqc_public_key', publicKey);
    await prefs.setString('pqc_private_key', privateKey);
    print('[EmailService] Saved PQC keys to storage');
  }
  
  static Future<bool> _loadPqcKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final publicKey = prefs.getString('pqc_public_key');
    final privateKey = prefs.getString('pqc_private_key');
    
    if (publicKey != null && privateKey != null) {
      _pqcPublicKey = publicKey;
      _pqcPrivateKey = privateKey;
      print('[EmailService] Loaded PQC keys from storage - Public: ${publicKey.substring(0, 50)}..., Private: ${privateKey.substring(0, 50)}...');
      return true;
    }
    print('[EmailService] No PQC keys found in storage');
    return false;
  }

  Future<bool> generatePqcKeyPair() async {
    try {
      print('[EmailService] Generating new PQC key pair...');
      final response = await http.post(
        Uri.parse('http://localhost:5001/api/pqc/generate-keypair'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final keyData = data['data'] as Map<String, dynamic>;
        final publicKey = keyData['publicKey'] as String;
        final privateKey = keyData['privateKey'] as String;
        
        setPqcPublicKey(publicKey);
        setPqcPrivateKey(privateKey);
        
        // Save keys persistently
        await _savePqcKeys(publicKey, privateKey);
        print('[EmailService] Generated new PQC key pair - Public: ${publicKey.substring(0, 50)}..., Private: ${privateKey.substring(0, 50)}...');
        return true;
      }
      print('[EmailService] Failed to generate PQC key pair - Status: ${response.statusCode}, Body: ${response.body}');
      return false;
    } catch (e) {
      print('[EmailService] Exception generating PQC key pair: $e');
      return false;
    }
  }
  
  // Initialize PQC keys from backend user account or generate new ones
  static Future<bool> initializePqcKeys() async {
    try {
      print('[EmailService] Initializing PQC keys...');
      
      // Try to load keys from backend first (user-specific keys)
      final keysLoaded = await _loadPqcKeysFromBackend();
      if (keysLoaded) {
        print('[EmailService] Loaded existing PQC keys from backend');
        return true;
      }
      
      // If no keys found in backend, generate new ones and save to backend
      print('[EmailService] No existing keys found, generating new PQC key pair');
      final service = EmailService();
      final success = await service.generatePqcKeyPair();
      
      if (success) {
        // Save the new keys to backend
        print('[EmailService] Saving new PQC keys to backend...');
        await _savePqcKeysToBackend();
      }
      
      return success;
    } catch (e) {
      print('[EmailService] Error initializing PQC keys: $e');
      return false;
    }
  }

  // Load PQC keys from backend user account
  static Future<bool> _loadPqcKeysFromBackend() async {
    try {
      final token = await _getToken();
      if (token == null) {
        print('[EmailService] No auth token found for loading PQC keys');
        return false;
      }
      
      print('[EmailService] Loading PQC keys from backend...');
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/pqc-keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      print('[EmailService] Backend response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[EmailService] Backend response data: $data');
        if (data['success'] == true && data['data'] != null) {
          final publicKey = data['data']['publicKey'] as String?;
          final privateKey = data['data']['privateKey'] as String?;
          
          if (publicKey != null && privateKey != null) {
            _pqcPublicKey = publicKey;
            _pqcPrivateKey = privateKey;
            // Also save to local storage for offline access
            await _savePqcKeys(publicKey, privateKey);
            print('[EmailService] Successfully loaded PQC keys from backend');
            return true;
          } else {
            print('[EmailService] PQC keys are null in backend response');
          }
        } else {
          print('[EmailService] Backend returned success=false or no data');
        }
      } else {
        print('[EmailService] Backend returned error: ${response.body}');
      }
      return false;
    } catch (e) {
      print('[EmailService] Error loading PQC keys from backend: $e');
      return false;
    }
  }

  // Save PQC keys to backend user account
  static Future<bool> _savePqcKeysToBackend() async {
    try {
      if (_pqcPublicKey == null || _pqcPrivateKey == null) {
        return false;
      }
      
      final token = await _getToken();
      if (token == null) return false;
      
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/pqc-keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'publicKey': _pqcPublicKey,
          'privateKey': _pqcPrivateKey,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('[EmailService] Error saving PQC keys to backend: $e');
      return false;
    }
  }

  // Clear stored PQC keys (for testing/debugging)
  static Future<void> clearPqcKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pqc_public_key');
    await prefs.remove('pqc_private_key');
    _pqcPublicKey = null;
    _pqcPrivateKey = null;
    print('[EmailService] Cleared all PQC keys from storage and memory');
  }


  // Register my PQC public key with backend so others can fetch it by email
  static Future<bool> registerMyPqcPublicKey(String email, String publicKey) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/email/pqc/public-key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'publicKey': publicKey}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> validateUser(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/validate-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['exists'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }


  Future<bool> sendEmail({
    required String senderEmail,
    required String recipientEmail,
    required String subject,
    required String body,
    List<SendAttachment>? attachments,
    String encryptionMethod = 'OTP',
    String? recipientPublicKey,
  }) async {
    try {
      // Diagnostics
      // ignore: avoid_print
      print('[sendEmail] method=$encryptionMethod sender=$senderEmail recipient=$recipientEmail');
      // ignore: avoid_print
      print('[sendEmail] subject(plain)="${subject}" body(plain.len)=${body.length}');

      String finalSubject = subject;
      String finalBody = body;
      
      // Encrypt based on method
      if (encryptionMethod == 'AES') {
        // AES encryption via backend proxy (GET)
        final encSubUri = Uri.parse('$_baseUrl/aes/encrypt?plaintext=${Uri.encodeComponent(subject)}');
        final encBodyUri = Uri.parse('$_baseUrl/aes/encrypt?plaintext=${Uri.encodeComponent(body)}');

        final subjectResponse = await http.get(encSubUri);
        final bodyResponse = await http.get(encBodyUri);

        // ignore: avoid_print
        print('[sendEmail][AES] encrypt subject status=${subjectResponse.statusCode} body.len=${subjectResponse.body.length}');
        // ignore: avoid_print
        print('[sendEmail][AES] encrypt body   status=${bodyResponse.statusCode} body.len=${bodyResponse.body.length}');

        if (subjectResponse.statusCode == 200 && bodyResponse.statusCode == 200) {
          finalSubject = subjectResponse.body; // already JSON envelope
          finalBody = bodyResponse.body;       // already JSON envelope
          // ignore: avoid_print
          print('[sendEmail][AES] finalSubject.preview=${finalSubject.substring(0, finalSubject.length > 120 ? 120 : finalSubject.length)}');
          // ignore: avoid_print
          print('[sendEmail][AES] finalBody.preview=${finalBody.substring(0, finalBody.length > 120 ? 120 : finalBody.length)}');
        } else {
          throw Exception('AES encryption failed');
        }
      } else       if (encryptionMethod == 'PQC_2_LAYER') {
        // Require explicit recipient public key to avoid key mismatch
        final actualRecipientPublicKey = recipientPublicKey;
        if (actualRecipientPublicKey == null || actualRecipientPublicKey.isEmpty) {
          throw Exception('Recipient public key is required for PQC');
        }
        print('[sendEmail][PQC_2_LAYER] Using recipient public key: ${actualRecipientPublicKey.substring(0, 50)}...');
        print('[sendEmail][PQC_2_LAYER] My private key: ${EmailService.pqcPrivateKey?.substring(0, 50) ?? 'null'}...');
        // Encrypt subject
        final pqcSub = await http.post(
          Uri.parse('http://localhost:5001/api/pqc/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'plaintext': subject, 'recipientPublicKey': actualRecipientPublicKey}),
        );
        // Encrypt body
        final pqcBody = await http.post(
          Uri.parse('http://localhost:5001/api/pqc/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'plaintext': body, 'recipientPublicKey': actualRecipientPublicKey}),
        );

        if (pqcSub.statusCode == 200 && pqcBody.statusCode == 200) {
          final subJson = jsonDecode(pqcSub.body)['data'] as Map<String, dynamic>;
          final bodyJson = jsonDecode(pqcBody.body)['data'] as Map<String, dynamic>;
          finalSubject = jsonEncode(subJson);
          finalBody = jsonEncode(bodyJson);
        } else {
          throw Exception('PQC encryption failed');
        }
      } else if (encryptionMethod == 'PQC_3_LAYER') {
        // Require explicit recipient public key to avoid key mismatch
        final actualRecipientPublicKey = recipientPublicKey;
        if (actualRecipientPublicKey == null || actualRecipientPublicKey.isEmpty) {
          throw Exception('Recipient public key is required for PQC');
        }
        print('[sendEmail][PQC_3_LAYER] Using recipient public key: ${actualRecipientPublicKey.substring(0, 50)}...');
        print('[sendEmail][PQC_3_LAYER] My private key: ${EmailService.pqcPrivateKey?.substring(0, 50) ?? 'null'}...');
        // Enhanced PQC (Kyber512 + AES layer true for PQC_3_LAYER)
        final encReqSubject = {
          'plaintext': subject,
          'recipientPublicKey': actualRecipientPublicKey,
          'securityLevel': 'Kyber512',
          'useAES': true,
        };
        final encReqBody = {
          'plaintext': body,
          'recipientPublicKey': actualRecipientPublicKey,
          'securityLevel': 'Kyber512',
          'useAES': true,
        };

        final pqcSub = await http.post(
          Uri.parse('http://localhost:5001/api/pqc/v2/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(encReqSubject),
        );
        final pqcBody = await http.post(
          Uri.parse('http://localhost:5001/api/pqc/v2/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(encReqBody),
        );

        if (pqcSub.statusCode == 200 && pqcBody.statusCode == 200) {
          final subJson = jsonDecode(pqcSub.body)['data'] as Map<String, dynamic>;
          final bodyJson = jsonDecode(pqcBody.body)['data'] as Map<String, dynamic>;
          finalSubject = jsonEncode(subJson);
          finalBody = jsonEncode(bodyJson);
        } else {
          throw Exception('Enhanced PQC encryption failed');
        }
      } else if (encryptionMethod == 'OTP') {
        // Let the backend handle OTP encryption
        finalSubject = subject;
        finalBody = body;
      }

      final requestBody = {
        'senderEmail': senderEmail,
        'recipientEmail': recipientEmail,
        'subject': finalSubject,
        'body': finalBody,
        'encryptionMethod': encryptionMethod,
        if (recipientPublicKey != null) 'recipientPublicKey': recipientPublicKey,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      // ignore: avoid_print
      print('[sendEmail] backend response status=${response.statusCode} body.len=${response.body.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        print('[sendEmail] Backend error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('[sendEmail] Exception: $e');
      return false;
    }
  }

  Future<List<Email>> getInbox(String userEmail) async {
    try {
      print('[EmailService] Fetching inbox for: $userEmail');
      final response = await http.get(
        Uri.parse('$_baseUrl/email/inbox/$userEmail'),
        headers: {'Content-Type': 'application/json'},
      );

      print('[EmailService] Response status: ${response.statusCode}');
      print('[EmailService] Response body length: ${response.body.length}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[EmailService] Response data keys: ${data.keys.toList()}');
        
        if (data['success'] == true) {
          final emailsJson = data['emails'] as List;
          print('[EmailService] Found ${emailsJson.length} emails');
          
          for (int i = 0; i < emailsJson.length; i++) {
            final emailJson = emailsJson[i];
            print('[EmailService] Email $i: ID=${emailJson['id']}, Subject length=${(emailJson['subject'] as String).length}, Body length=${(emailJson['body'] as String).length}');
            print('[EmailService] Email $i Subject preview: ${(emailJson['subject'] as String).substring(0, (emailJson['subject'] as String).length > 100 ? 100 : (emailJson['subject'] as String).length)}');
            print('[EmailService] Email $i Body preview: ${(emailJson['body'] as String).substring(0, (emailJson['body'] as String).length > 100 ? 100 : (emailJson['body'] as String).length)}');
          }
          
          return emailsJson.map((emailJson) => Email.fromJson(emailJson)).toList();
        } else {
          print('[EmailService] API returned success=false');
        }
      } else {
        print('[EmailService] API returned error status: ${response.statusCode}');
        print('[EmailService] Error body: ${response.body}');
      }
      return [];
    } catch (e) {
      print('[EmailService] Exception in getInbox: $e');
      return [];
    }
  }

  Future<List<Email>> getSentEmails(String userEmail) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/email/sent/$userEmail'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailsJson = data['emails'] as List;
          return emailsJson.map((emailJson) => Email.fromJson(emailJson)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> markAsRead(String emailId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/mark-read/$emailId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class Email {
  final String id;
  final String senderEmail;
  final String recipientEmail;
  String subject;
  String body;
  final List<EmailAttachment> attachments;
  final DateTime sentAt;
  final bool isRead;
  final String encryptionMethod;

  Email({
    required this.id,
    required this.senderEmail,
    required this.recipientEmail,
    required this.subject,
    required this.body,
    List<EmailAttachment>? attachments,
    required this.sentAt,
    required this.isRead,
    this.encryptionMethod = 'OTP',
  }) : attachments = attachments ?? const <EmailAttachment>[];

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    id: json['id'] as String,
    senderEmail: json['senderEmail'] as String,
    recipientEmail: json['recipientEmail'] as String,
    subject: json['subject'] as String,
    body: json['body'] as String,
    attachments: (json['attachments'] as List?)?.map((a) => EmailAttachment.fromJson(a as Map<String, dynamic>)).toList() ?? const <EmailAttachment>[],
    sentAt: DateTime.parse(json['sentAt'] as String),
    isRead: json['isRead'] as bool,
    encryptionMethod: json['encryptionMethod'] as String? ?? 'OTP',
  );
}

class EmailAttachment {
  final String fileName;
  final String contentType;
  final String contentBase64;

  EmailAttachment({required this.fileName, required this.contentType, required this.contentBase64});

  factory EmailAttachment.fromJson(Map<String, dynamic> json) => EmailAttachment(
    fileName: json['fileName'] as String,
    contentType: json['contentType'] as String,
    contentBase64: json['contentBase64'] as String,
  );
}

class SendAttachment {
  final String fileName;
  final String contentType;
  final String contentBase64;

  SendAttachment({required this.fileName, required this.contentType, required this.contentBase64});

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'contentType': contentType,
    'contentBase64': contentBase64,
  };
}
