import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/sent_pqc_email.dart';

class EmailService {
  static const String _baseUrl = 'http://localhost:5001/api';
  // PQC key pairs with persistence
  static String? _pqcPrivateKey;
  static String? _pqcPublicKey;

  // Database instance
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
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

  // Load PQC PUBLIC KEY from backend user account
  // NOTE: Private keys are NEVER stored on backend, only on device
  static Future<bool> _loadPqcKeysFromBackend() async {
    try {
      final token = await _getToken();
      if (token == null) {
        print('[EmailService] No auth token found for loading PQC public key');
        return false;
      }

      print('[EmailService] Loading PQC public key from backend...');
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

          if (publicKey != null) {
            _pqcPublicKey = publicKey;
            // Try to load private key from local storage only
            final localKeys = await _loadPqcKeys();
            if (!localKeys) {
              print('[EmailService] Public key loaded from backend, but no private key in local storage - need to regenerate keypair');
              return false;
            }
            print('[EmailService] Successfully loaded public key from backend and private key from local storage');
            return true;
          } else {
            print('[EmailService] Public key is null in backend response');
          }
        } else {
          print('[EmailService] Backend returned success=false or no data');
        }
      } else {
        print('[EmailService] Backend returned error: ${response.body}');
      }
      return false;
    } catch (e) {
      print('[EmailService] Error loading PQC public key from backend: $e');
      return false;
    }
  }

  // Save PQC PUBLIC KEY ONLY to backend user account
  // SECURITY: Private keys must NEVER be sent to backend - they stay on device only
  static Future<bool> _savePqcKeysToBackend() async {
    try {
      if (_pqcPublicKey == null) {
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
          // REMOVED: 'privateKey' - private keys never leave the device!
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[EmailService] Error saving PQC public key to backend: $e');
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

  /// Validate recipient and get their PQC public key for new PQC architecture
  Future<Map<String, dynamic>?> validateRecipient(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/validate-recipient'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'recipientEmail': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['exists'] == true) {
          return {
            'exists': true,
            'publicKey': data['publicKey'] as String,
            'name': data['name'] as String?,
          };
        }
      }
      return {'exists': false};
    } catch (e) {
      print('[EmailService] Error validating recipient: $e');
      return null;
    }
  }

  /// Encrypt data with PQC on frontend (new architecture)
  Future<String?> encryptWithPqcFrontend(String plaintext, String recipientPublicKey) async {
    try {
      print('[EmailService] Encrypting with PQC on frontend...');
      final response = await http.post(
        Uri.parse('http://localhost:5001/api/pqc/encrypt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'plaintext': plaintext,
          'recipientPublicKey': recipientPublicKey,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final encryptedData = data['data'] as Map<String, dynamic>;
        return jsonEncode(encryptedData);
      }
      print('[EmailService] PQC encryption failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      print('[EmailService] Exception in PQC encryption: $e');
      return null;
    }
  }

  /// Decrypt PQC data with private key on frontend (new architecture)
  Future<String?> decryptWithPqcFrontend(String pqcEncryptedData) async {
    try {
      if (_pqcPrivateKey == null) {
        print('[EmailService] No private key available for decryption');
        return null;
      }

      print('[EmailService] Decrypting PQC data on frontend...');

      // Parse the PQC envelope to extract encryptedBody and pqcCiphertext
      final envelope = jsonDecode(pqcEncryptedData) as Map<String, dynamic>;
      final encryptedBody = envelope['encryptedBody'] as String?;
      final pqcCiphertext = envelope['pqcCiphertext'] as String?;
      final encryptedKeyId = envelope['encryptedKeyId'] as String? ?? envelope['keyId'] as String? ?? '';

      if (encryptedBody == null || pqcCiphertext == null) {
        print('[EmailService] Invalid PQC envelope: missing encryptedBody or pqcCiphertext');
        return null;
      }

      final response = await http.post(
        Uri.parse('http://localhost:5001/api/pqc/decrypt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'encryptedBody': encryptedBody,
          'pqcCiphertext': pqcCiphertext,
          'encryptedKeyId': encryptedKeyId,
          'privateKey': _pqcPrivateKey,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']['plaintext'] as String;
      }
      print('[EmailService] PQC decryption failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      print('[EmailService] Exception in PQC decryption: $e');
      return null;
    }
  }

  /// Save sent PQC email to local SQLite database
  Future<void> saveSentPqcEmail(String emailId, String subject, String body, String recipientEmail, String senderEmail, DateTime sentAt, {List<SendAttachment>? attachments}) async {
    try {
      print('[EmailService] ===== SAVING PQC EMAIL TO LOCAL DATABASE =====');
      print('[EmailService] Email ID: $emailId');
      print('[EmailService] Subject: $subject');
      print('[EmailService] Body length: ${body.length}');
      print('[EmailService] Attachments parameter: ${attachments?.length ?? 0} attachments');

      if (attachments != null && attachments.isNotEmpty) {
        for (int i = 0; i < attachments.length; i++) {
          print('[EmailService] Input attachment $i: ${attachments[i].fileName}, size: ${attachments[i].contentBase64.length} bytes');
        }
      }

      // Convert SendAttachment to PqcAttachment
      final pqcAttachments = attachments?.map((a) {
        print('[EmailService] Converting attachment: ${a.fileName}');
        return PqcAttachment(
          fileName: a.fileName,
          contentType: a.contentType,
          contentBase64: a.contentBase64,
        );
      }).toList();

      print('[EmailService] Converted ${pqcAttachments?.length ?? 0} attachments to PqcAttachment');

      final email = SentPqcEmail(
        id: emailId,
        subject: subject,
        body: body,
        recipientEmail: recipientEmail,
        senderEmail: senderEmail,
        sentAt: sentAt,
        attachments: pqcAttachments,
      );

      print('[EmailService] Created SentPqcEmail object with ${email.attachments.length} attachments');
      await _dbHelper.insertSentPqcEmail(email);
      print('[EmailService] ✅ Successfully saved PQC email to local database: $emailId (with ${pqcAttachments?.length ?? 0} attachments)');
    } catch (e, stackTrace) {
      print('[EmailService] ❌ Error saving sent PQC email to database: $e');
      print('[EmailService] Stack trace: $stackTrace');
    }
  }

  /// Get sent PQC email from local SQLite database
  Future<SentPqcEmail?> getSentPqcEmail(String emailId) async {
    try {
      return await _dbHelper.getSentPqcEmail(emailId);
    } catch (e) {
      print('[EmailService] Error getting sent PQC email from database: $e');
      return null;
    }
  }

  /// Get all sent PQC emails for a user from local database
  Future<List<SentPqcEmail>> getAllSentPqcEmails(String senderEmail) async {
    try {
      return await _dbHelper.getSentPqcEmails(senderEmail);
    } catch (e) {
      print('[EmailService] Error getting all sent PQC emails from database: $e');
      return [];
    }
  }

  /// Delete sent PQC email from local database
  Future<bool> deleteSentPqcEmail(String emailId) async {
    try {
      final result = await _dbHelper.deleteSentPqcEmail(emailId);
      return result > 0;
    } catch (e) {
      print('[EmailService] Error deleting sent PQC email from database: $e');
      return false;
    }
  }


  /// Send email with NEW PQC_2_LAYER architecture (PQC encryption on frontend FIRST)
  /// Flow: Frontend PQC encrypt (Kyber512) → Backend OTP → Database
  Future<bool> sendPqc2EncryptedEmail({
    required String senderEmail,
    required String recipientEmail,
    required String subject,
    required String body,
    List<SendAttachment>? attachments,
  }) async {
    try {
      print('[EmailService] Starting NEW PQC_2_LAYER send flow...');

      // Step 1: Validate recipient and get public key
      final recipientData = await validateRecipient(recipientEmail);
      if (recipientData == null || recipientData['exists'] != true) {
        print('[EmailService] Recipient not found or validation failed');
        return false;
      }

      final recipientPublicKey = recipientData['publicKey'] as String;
      print('[EmailService] Recipient validated, public key: ${recipientPublicKey.substring(0, 50)}...');

      // Step 2: Encrypt subject and body with PQC on frontend
      // Use placeholder for empty subject/body to avoid backend validation errors
      final subjectToEncrypt = subject.trim().isEmpty ? "(No Subject)" : subject;
      final bodyToEncrypt = body.trim().isEmpty ? " " : body;
      print('[EmailService] Subject to encrypt: "$subjectToEncrypt"');
      print('[EmailService] Body to encrypt: "${bodyToEncrypt.substring(0, bodyToEncrypt.length > 50 ? 50 : bodyToEncrypt.length)}..."');

      final pqcEncryptedSubject = await encryptWithPqcFrontend(subjectToEncrypt, recipientPublicKey);
      final pqcEncryptedBody = await encryptWithPqcFrontend(bodyToEncrypt, recipientPublicKey);

      if (pqcEncryptedSubject == null || pqcEncryptedBody == null) {
        print('[EmailService] PQC encryption failed');
        return false;
      }

      print('[EmailService] PQC encryption successful');

      // Step 3: Send PQC-encrypted data to backend (PQC_2_LAYER endpoint)
      final requestBody = {
        'senderEmail': senderEmail,
        'recipientEmail': recipientEmail,
        'pqcEncryptedSubject': pqcEncryptedSubject,
        'pqcEncryptedBody': pqcEncryptedBody,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/email/send-pqc2-encrypted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('[EmailService] Backend response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailId = data['emailId'] as String;
          print('[EmailService] PQC_2_LAYER email sent successfully, ID: $emailId');

          // Step 4: Save plaintext to local database for sent folder (including attachments)
          await saveSentPqcEmail(emailId, subject, body, recipientEmail, senderEmail, DateTime.now(), attachments: attachments);

          return true;
        }
      }

      print('[EmailService] Backend returned error: ${response.body}');
      return false;
    } catch (e) {
      print('[EmailService] Exception in sendPqc2EncryptedEmail: $e');
      return false;
    }
  }

  /// Send email with NEW PQC_3_LAYER architecture (PQC encryption on frontend FIRST)
  /// Flow: Frontend PQC encrypt (Kyber1024) → Backend AES → Backend OTP → Database
  Future<bool> sendPqc3EncryptedEmail({
    required String senderEmail,
    required String recipientEmail,
    required String subject,
    required String body,
    List<SendAttachment>? attachments,
  }) async {
    try {
      print('[EmailService] Starting NEW PQC_3_LAYER send flow...');

      // Step 1: Validate recipient and get public key
      final recipientData = await validateRecipient(recipientEmail);
      if (recipientData == null || recipientData['exists'] != true) {
        print('[EmailService] Recipient not found or validation failed');
        return false;
      }

      final recipientPublicKey = recipientData['publicKey'] as String;
      print('[EmailService] Recipient validated, public key: ${recipientPublicKey.substring(0, 50)}...');

      // Step 2: Encrypt subject and body with PQC on frontend
      final pqcEncryptedSubject = await encryptWithPqcFrontend(subject, recipientPublicKey);
      final pqcEncryptedBody = await encryptWithPqcFrontend(body, recipientPublicKey);

      if (pqcEncryptedSubject == null || pqcEncryptedBody == null) {
        print('[EmailService] PQC encryption failed');
        return false;
      }

      print('[EmailService] PQC encryption successful');

      // Step 3: Send PQC-encrypted data to backend (PQC_3_LAYER endpoint)
      final requestBody = {
        'senderEmail': senderEmail,
        'recipientEmail': recipientEmail,
        'pqcEncryptedSubject': pqcEncryptedSubject,
        'pqcEncryptedBody': pqcEncryptedBody,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/email/send-pqc-encrypted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('[EmailService] Backend response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailId = data['emailId'] as String;
          print('[EmailService] PQC_3_LAYER email sent successfully, ID: $emailId');

          // Step 4: Save plaintext to local database for sent folder (including attachments)
          await saveSentPqcEmail(emailId, subject, body, recipientEmail, senderEmail, DateTime.now(), attachments: attachments);

          return true;
        }
      }

      print('[EmailService] Backend returned error: ${response.body}');
      return false;
    } catch (e) {
      print('[EmailService] Exception in sendPqc3EncryptedEmail: $e');
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

  /// Get email with NEW PQC_2_LAYER architecture (decrypts PQC on frontend)
  /// Flow: Fetch from backend → Decrypt OTP (backend) → Decrypt PQC (frontend)
  Future<Email?> getPqc2Email(String emailId) async {
    try {
      print('[EmailService] Fetching PQC_2_LAYER email: $emailId');
      final response = await http.get(
        Uri.parse('$_baseUrl/email/decrypt-to-pqc2/$emailId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailData = data['email'] as Map<String, dynamic>;

          // Backend has already decrypted OTP layer
          final pqcEncryptedSubject = emailData['pqcEncryptedSubject'] as String;
          final pqcEncryptedBody = emailData['pqcEncryptedBody'] as String;

          // Decrypt PQC layer on frontend
          final decryptedSubject = await decryptWithPqcFrontend(pqcEncryptedSubject);
          final decryptedBody = await decryptWithPqcFrontend(pqcEncryptedBody);

          if (decryptedSubject == null || decryptedBody == null) {
            print('[EmailService] Failed to decrypt PQC_2_LAYER data on frontend');
            return null;
          }

          // Decrypt attachments (if present)
          final List<EmailAttachment> decryptedAttachments = [];
          final pqcAttachmentsJson = emailData['pqcAttachmentsJson'] as String?;
          if (pqcAttachmentsJson != null && pqcAttachmentsJson.isNotEmpty) {
            try {
              print('[EmailService] Found pqcAttachmentsJson, decrypting attachments...');
              final attachmentsList = jsonDecode(pqcAttachmentsJson) as List;
              print('[EmailService] Found ${attachmentsList.length} encrypted attachments');

              for (int i = 0; i < attachmentsList.length; i++) {
                final attachmentData = attachmentsList[i] as Map<String, dynamic>;
                final fileName = attachmentData['fileName'] as String;
                final contentType = attachmentData['contentType'] as String? ?? 'application/octet-stream';
                final pqcEnvelope = attachmentData['pqcEnvelope'] as String;

                print('[EmailService] Decrypting attachment $i: $fileName');
                final decryptedBase64 = await decryptWithPqcFrontend(pqcEnvelope);

                if (decryptedBase64 != null) {
                  decryptedAttachments.add(EmailAttachment(
                    fileName: fileName,
                    contentType: contentType,
                    contentBase64: decryptedBase64,
                  ));
                  print('[EmailService] ✅ Successfully decrypted attachment: $fileName');
                } else {
                  print('[EmailService] ❌ Failed to decrypt attachment: $fileName');
                }
              }
            } catch (e) {
              print('[EmailService] Error decrypting attachments: $e');
            }
          }

          // Create Email object with decrypted data
          return Email(
            id: emailData['id'] as String,
            senderEmail: emailData['senderEmail'] as String,
            recipientEmail: emailData['recipientEmail'] as String,
            subject: decryptedSubject,
            body: decryptedBody,
            attachments: decryptedAttachments,
            sentAt: DateTime.parse(emailData['sentAt'] as String),
            isRead: emailData['isRead'] as bool,
            encryptionMethod: emailData['encryptionMethod'] as String,
          );
        }
      }

      print('[EmailService] Failed to fetch PQC_2_LAYER email: ${response.statusCode}');
      return null;
    } catch (e) {
      print('[EmailService] Exception in getPqc2Email: $e');
      return null;
    }
  }

  /// Get email with NEW PQC_3_LAYER architecture (decrypts PQC on frontend)
  /// Flow: Fetch from backend → Decrypt OTP (backend) → Decrypt AES (backend) → Decrypt PQC (frontend)
  Future<Email?> getPqc3Email(String emailId) async {
    try {
      print('[EmailService] Fetching PQC_3_LAYER email: $emailId');
      final response = await http.get(
        Uri.parse('$_baseUrl/email/decrypt-to-pqc/$emailId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailData = data['email'] as Map<String, dynamic>;

          // Backend has already decrypted OTP and AES layers
          final pqcEncryptedSubject = emailData['pqcEncryptedSubject'] as String;
          final pqcEncryptedBody = emailData['pqcEncryptedBody'] as String;

          // Decrypt PQC layer on frontend
          final decryptedSubject = await decryptWithPqcFrontend(pqcEncryptedSubject);
          final decryptedBody = await decryptWithPqcFrontend(pqcEncryptedBody);

          if (decryptedSubject == null || decryptedBody == null) {
            print('[EmailService] Failed to decrypt PQC_3_LAYER data on frontend');
            return null;
          }

          // Decrypt attachments (if present)
          final List<EmailAttachment> decryptedAttachments = [];
          final pqcAttachmentsJson = emailData['pqcAttachmentsJson'] as String?;
          if (pqcAttachmentsJson != null && pqcAttachmentsJson.isNotEmpty) {
            try {
              print('[EmailService] Found pqcAttachmentsJson, decrypting attachments...');
              final attachmentsList = jsonDecode(pqcAttachmentsJson) as List;
              print('[EmailService] Found ${attachmentsList.length} encrypted attachments');

              for (int i = 0; i < attachmentsList.length; i++) {
                final attachmentData = attachmentsList[i] as Map<String, dynamic>;
                final fileName = attachmentData['fileName'] as String;
                final contentType = attachmentData['contentType'] as String? ?? 'application/octet-stream';
                final pqcEnvelope = attachmentData['pqcEnvelope'] as String;

                print('[EmailService] Decrypting attachment $i: $fileName');
                final decryptedBase64 = await decryptWithPqcFrontend(pqcEnvelope);

                if (decryptedBase64 != null) {
                  decryptedAttachments.add(EmailAttachment(
                    fileName: fileName,
                    contentType: contentType,
                    contentBase64: decryptedBase64,
                  ));
                  print('[EmailService] ✅ Successfully decrypted attachment: $fileName');
                } else {
                  print('[EmailService] ❌ Failed to decrypt attachment: $fileName');
                }
              }
            } catch (e) {
              print('[EmailService] Error decrypting attachments: $e');
            }
          }

          // Create Email object with decrypted data
          return Email(
            id: emailData['id'] as String,
            senderEmail: emailData['senderEmail'] as String,
            recipientEmail: emailData['recipientEmail'] as String,
            subject: decryptedSubject,
            body: decryptedBody,
            attachments: decryptedAttachments,
            sentAt: DateTime.parse(emailData['sentAt'] as String),
            isRead: emailData['isRead'] as bool,
            encryptionMethod: emailData['encryptionMethod'] as String,
          );
        }
      }

      print('[EmailService] Failed to fetch PQC_3_LAYER email: ${response.statusCode}');
      return null;
    } catch (e) {
      print('[EmailService] Exception in getPqc3Email: $e');
      return null;
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

          final emails = <Email>[];
          for (int i = 0; i < emailsJson.length; i++) {
            final emailJson = emailsJson[i];
            print('[EmailService] Email $i: ID=${emailJson['id']}, Method=${emailJson['encryptionMethod']}');

            // For NEW PQC methods, use new decryption flow
            if (emailJson['encryptionMethod'] == 'PQC_2_LAYER') {
              print('[EmailService] Detected PQC_2_LAYER email, using new decryption flow');
              final pqcEmail = await getPqc2Email(emailJson['id'] as String);
              if (pqcEmail != null) {
                emails.add(pqcEmail);
              } else {
                // Fallback: add email with encrypted data
                emails.add(Email.fromJson(emailJson));
              }
            } else if (emailJson['encryptionMethod'] == 'PQC_3_LAYER') {
              print('[EmailService] Detected PQC_3_LAYER email, using new decryption flow');
              final pqcEmail = await getPqc3Email(emailJson['id'] as String);
              if (pqcEmail != null) {
                emails.add(pqcEmail);
              } else {
                // Fallback: add email with encrypted data
                emails.add(Email.fromJson(emailJson));
              }
            } else {
              // Old encryption methods: backend already decrypted
              emails.add(Email.fromJson(emailJson));
            }
          }

          return emails;
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
      print('[EmailService] ===== FETCHING SENT EMAILS =====');
      print('[EmailService] User email: $userEmail');

      final response = await http.get(
        Uri.parse('$_baseUrl/email/sent/$userEmail'),
        headers: {'Content-Type': 'application/json'},
      );

      print('[EmailService] Backend response status: ${response.statusCode}');
      print('[EmailService] Backend response length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailsJson = data['emails'] as List;
          print('[EmailService] Backend returned ${emailsJson.length} emails');
          final emails = <Email>[];

          for (int i = 0; i < emailsJson.length; i++) {
            final emailJson = emailsJson[i];
            print('[EmailService] ----- Processing email $i -----');
            print('[EmailService] Email ID: ${emailJson['id']}');
            print('[EmailService] Encryption method: ${emailJson['encryptionMethod']}');
            print('[EmailService] Subject preview: ${(emailJson['subject'] as String).substring(0, (emailJson['subject'] as String).length > 100 ? 100 : (emailJson['subject'] as String).length)}');
            print('[EmailService] Body preview: ${(emailJson['body'] as String).substring(0, (emailJson['body'] as String).length > 100 ? 100 : (emailJson['body'] as String).length)}');

            final email = Email.fromJson(emailJson);

            // For NEW PQC emails (both 2-layer and 3-layer), load plaintext from local database
            if (email.encryptionMethod == 'PQC_2_LAYER' || email.encryptionMethod == 'PQC_3_LAYER') {
              print('[EmailService] This is a ${email.encryptionMethod} email, loading from local database...');
              final localEmail = await getSentPqcEmail(email.id);
              if (localEmail != null) {
                print('[EmailService] ✅ Found in local database!');
                print('[EmailService] Local subject: ${localEmail.subject}');
                print('[EmailService] Local body: ${localEmail.body}');
                print('[EmailService] Local attachments: ${localEmail.attachments.length}');
                // Replace encrypted data with plaintext from local database
                email.subject = localEmail.subject;
                email.body = localEmail.body;
                // Replace with local attachments
                email.attachments.clear();
                email.attachments.addAll(localEmail.attachments.map((a) => EmailAttachment(
                  fileName: a.fileName,
                  contentType: a.contentType,
                  contentBase64: a.contentBase64,
                )));
                print('[EmailService] Loaded ${email.encryptionMethod} email from local database: ${email.id} (${localEmail.attachments.length} attachments)');
              } else {
                print('[EmailService] ❌ NOT FOUND in local database!');
                print('[EmailService] Warning: ${email.encryptionMethod} email not found in local database: ${email.id}');
                print('[EmailService] Will show encrypted data from backend');
              }
            } else {
              print('[EmailService] Non-PQC email (${email.encryptionMethod}), using backend data as-is');
            }

            emails.add(email);
            print('[EmailService] Final subject for display: ${email.subject.substring(0, email.subject.length > 50 ? 50 : email.subject.length)}');
            print('[EmailService] Final body for display: ${email.body.substring(0, email.body.length > 50 ? 50 : email.body.length)}');
          }

          print('[EmailService] ===== SENT EMAILS FETCH COMPLETE: ${emails.length} emails =====');
          return emails;
        }
      }
      return [];
    } catch (e) {
      print('[EmailService] Exception in getSentEmails: $e');
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
  List<EmailAttachment> attachments; // Non-final to allow updates from local database
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
  }) : attachments = attachments ?? <EmailAttachment>[];

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
