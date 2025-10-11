import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/email_service.dart';
import '../providers/auth_provider.dart';
import '../app.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final EmailService _emailService = EmailService();
  List<Email> _emails = [];
  bool _isLoading = false;
  Email? _selectedEmail;
  final bool _useMockInbox = false; // use real inbox data
  String? _attachmentStatus;
  bool _askedForPqcKey = false;

  @override
  void initState() {
    super.initState();
    _loadEmails();
  }


  Future<void> _loadEmails() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) {
      if (_useMockInbox && mounted) {
        _seedMockEmails();
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final emails = await _emailService.getInbox(authProvider.user!.email);
      // ignore: avoid_print
      print('[inbox] loaded emails count=${emails.length}');
      
      // Log each email's raw data before decryption
      for (int i = 0; i < emails.length; i++) {
        final email = emails[i];
        print('[inbox] Email $i raw data: ID=${email.id}, Subject="${email.subject}", Body="${email.body}", Method=${email.encryptionMethod}');
        print('[inbox] Email $i Subject length: ${email.subject.length}, Body length: ${email.body.length}');
      }
      
      // Decrypt emails directly in frontend
      for (var email in emails) {
        // If we encounter a PQC email and no private key set yet, generate one automatically
        if ((email.encryptionMethod == 'PQC_2_LAYER' || email.encryptionMethod == 'PQC_3_LAYER') &&
            EmailService.pqcPrivateKey == null && !_askedForPqcKey) {
          _askedForPqcKey = true;
          print('[inbox] Generating PQC key pair for decryption');
          await EmailService.initializePqcKeys();
        }
        
        // Debug: Check if we have PQC keys for decryption
        if (email.encryptionMethod == 'PQC_2_LAYER' || email.encryptionMethod == 'PQC_3_LAYER') {
          print('[inbox][PQC] Available private key: ${EmailService.pqcPrivateKey?.substring(0, 50)}...');
          print('[inbox][PQC] Private key length: ${EmailService.pqcPrivateKey?.length}');
        }
        if (email.encryptionMethod == 'AES') {
          try {
            // ignore: avoid_print
            print('[inbox][AES] decrypt id=${email.id} subj.len=${email.subject.length} body.len=${email.body.length}');
            final subjectEnvelope = jsonDecode(email.subject);
            final bodyEnvelope = jsonDecode(email.body);
            
            // AES decryption via backend proxy (GET)
            final subUri = Uri.parse('http://localhost:5001/api/aes/decrypt?envelope=${Uri.encodeComponent(jsonEncode(subjectEnvelope))}');
            final bodyUri = Uri.parse('http://localhost:5001/api/aes/decrypt?envelope=${Uri.encodeComponent(jsonEncode(bodyEnvelope))}');

            final subjectResponse = await http.get(subUri);
            final bodyResponse = await http.get(bodyUri);
            
            // ignore: avoid_print
            print('[inbox][AES] decrypt subject status=${subjectResponse.statusCode} body.len=${subjectResponse.body.length}');
            if (subjectResponse.statusCode == 200) {
              final subjectResult = jsonDecode(subjectResponse.body);
              email.subject = subjectResult['plaintext'] ?? 'Decryption Failed';
            }
            
            // ignore: avoid_print
            print('[inbox][AES] decrypt body status=${bodyResponse.statusCode} body.len=${bodyResponse.body.length}');
            if (bodyResponse.statusCode == 200) {
              final bodyResult = jsonDecode(bodyResponse.body);
              email.body = bodyResult['plaintext'] ?? 'Decryption Failed';
            }
          } catch (e) {
            print('AES decryption failed: $e');
            email.subject = 'AES Decryption Failed';
            email.body = 'Failed to decrypt AES-encrypted email';
          }
        } else if (email.encryptionMethod == 'OTP') {
          try {
            final subjectEnvelope = jsonDecode(email.subject);
            final bodyEnvelope = jsonDecode(email.body);
            
            // OTP decryption via otp_api_test.py
            final subjectResponse = await http.post(
              Uri.parse('http://127.0.0.1:8081/decrypt'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(subjectEnvelope),
            );
            
            final bodyResponse = await http.post(
              Uri.parse('http://127.0.0.1:8081/decrypt'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(bodyEnvelope),
            );
            
            if (subjectResponse.statusCode == 200) {
              final subjectResult = jsonDecode(subjectResponse.body);
              email.subject = subjectResult['plaintext'] ?? 'Decryption Failed';
            }
            
            if (bodyResponse.statusCode == 200) {
              final bodyResult = jsonDecode(bodyResponse.body);
              email.body = bodyResult['plaintext'] ?? 'Decryption Failed';
            }
          } catch (e) {
            print('OTP decryption failed: $e');
            email.subject = 'OTP Decryption Failed';
            email.body = 'Failed to decrypt OTP-encrypted email';
          }
        }
        // PQC 2-layer: subject/body contain JSON with encryptedBody+pqcCiphertext
        else if (email.encryptionMethod == 'PQC_2_LAYER') {
          try {
            print('[inbox][PQC_2_LAYER] Attempting decryption for email ${email.id}');
            print('[inbox][PQC_2_LAYER] Subject length: ${email.subject.length}, Body length: ${email.body.length}');
            
            Map<String, dynamic> subEnv;
            Map<String, dynamic> bodyEnv;
            
            print('[inbox][PQC_2_LAYER] Raw subject content: "${email.subject}"');
            print('[inbox][PQC_2_LAYER] Raw body content: "${email.body}"');
            
            try {
              subEnv = jsonDecode(email.subject) as Map<String, dynamic>;
              print('[inbox][PQC_2_LAYER] Successfully parsed subject JSON');
            } catch (e) {
              print('[inbox][PQC_2_LAYER] Failed to parse subject JSON: $e');
              print('[inbox][PQC_2_LAYER] Subject content: ${email.subject.substring(0, math.min(100, email.subject.length))}...');
              continue;
            }
            
            try {
              bodyEnv = jsonDecode(email.body) as Map<String, dynamic>;
              print('[inbox][PQC_2_LAYER] Successfully parsed body JSON');
            } catch (e) {
              print('[inbox][PQC_2_LAYER] Failed to parse body JSON: $e');
              print('[inbox][PQC_2_LAYER] Body content: ${email.body.substring(0, math.min(100, email.body.length))}...');
              continue;
            }
            print('[inbox][PQC_2_LAYER] Subject envelope keys: ${subEnv.keys.toList()}');
            print('[inbox][PQC_2_LAYER] Body envelope keys: ${bodyEnv.keys.toList()}');
            
            // Check if this is actually PQC data or OTP data mislabeled
            if (subEnv.containsKey('encryptedBody') && subEnv.containsKey('pqcCiphertext')) {
              // This is actual PQC data
              final priv = EmailService.pqcPrivateKey;
              print('[inbox][PQC_2_LAYER] Private key available: ${priv != null && priv.isNotEmpty}');
              if (priv != null) {
                print('[inbox][PQC_2_LAYER] Using private key: ${priv.substring(0, 50)}...');
                print('[inbox][PQC_2_LAYER] Private key length: ${priv.length}');
                print('[inbox][PQC_2_LAYER] Encrypted body length: ${subEnv['encryptedBody'].toString().length}');
                print('[inbox][PQC_2_LAYER] PQC ciphertext length: ${subEnv['pqcCiphertext'].toString().length}');
                print('[inbox][PQC_2_LAYER] Key ID: ${subEnv['keyId']}');
              }
              if (priv != null && priv.isNotEmpty) {
                final subjectDecryptBody = {
                  'encryptedBody': subEnv['encryptedBody'],
                  'pqcCiphertext': subEnv['pqcCiphertext'],
                  'encryptedKeyId': subEnv['encryptedKeyId'] ?? subEnv['keyId'] ?? '',
                  'privateKey': priv,
                };
                print('[inbox][PQC_2_LAYER] Subject decrypt body: ${jsonEncode(subjectDecryptBody)}');
                try {
                  final subResp = await http.post(
                    Uri.parse('http://localhost:5001/api/pqc/decrypt'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(subjectDecryptBody),
                  );
                  final bodyDecryptBody = {
                    'encryptedBody': bodyEnv['encryptedBody'],
                    'pqcCiphertext': bodyEnv['pqcCiphertext'],
                    'encryptedKeyId': bodyEnv['encryptedKeyId'] ?? bodyEnv['keyId'] ?? '',
                    'privateKey': priv,
                  };
                  print('[inbox][PQC_2_LAYER] Body decrypt body: ${jsonEncode(bodyDecryptBody)}');
                  final bodyResp = await http.post(
                    Uri.parse('http://localhost:5001/api/pqc/decrypt'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(bodyDecryptBody),
                  );

                print('[inbox][PQC_2_LAYER] Subject decrypt status: ${subResp.statusCode}');
                print('[inbox][PQC_2_LAYER] Body decrypt status: ${bodyResp.statusCode}');
                if (subResp.statusCode == 200) {
                  final subjectResult = jsonDecode(subResp.body) as Map<String, dynamic>;
                  print('[inbox][PQC_2_LAYER] Subject decrypt response: ${subResp.body}');
                  print('[inbox][PQC_2_LAYER] Subject decrypt result keys: ${subjectResult.keys.toList()}');
                  if (subjectResult.containsKey('data')) {
                    print('[inbox][PQC_2_LAYER] Subject data keys: ${(subjectResult['data'] as Map<String, dynamic>).keys.toList()}');
                    email.subject = subjectResult['data']['plaintext'] ?? email.subject;
                    print('[inbox][PQC_2_LAYER] Subject decrypted content: "${email.subject}"');
                  } else {
                    print('[inbox][PQC_2_LAYER] Subject result: ${subjectResult}');
                    email.subject = subjectResult['plaintext'] ?? email.subject;
                    print('[inbox][PQC_2_LAYER] Subject decrypted content (direct): "${email.subject}"');
                  }
                  print('[inbox][PQC_2_LAYER] Subject decrypted successfully');
                } else {
                  print('[inbox][PQC_2_LAYER] Subject decrypt failed: ${subResp.body}');
                }
                if (bodyResp.statusCode == 200) {
                  final bodyResult = jsonDecode(bodyResp.body) as Map<String, dynamic>;
                  print('[inbox][PQC_2_LAYER] Body decrypt response: ${bodyResp.body}');
                  print('[inbox][PQC_2_LAYER] Body decrypt result keys: ${bodyResult.keys.toList()}');
                  if (bodyResult.containsKey('data')) {
                    print('[inbox][PQC_2_LAYER] Body data keys: ${(bodyResult['data'] as Map<String, dynamic>).keys.toList()}');
                    email.body = bodyResult['data']['plaintext'] ?? email.body;
                    print('[inbox][PQC_2_LAYER] Body decrypted content: "${email.body}"');
                  } else {
                    print('[inbox][PQC_2_LAYER] Body result: ${bodyResult}');
                    email.body = bodyResult['plaintext'] ?? email.body;
                    print('[inbox][PQC_2_LAYER] Body decrypted content (direct): "${email.body}"');
                  }
                  print('[inbox][PQC_2_LAYER] Body decrypted successfully');
                } else {
                  print('[inbox][PQC_2_LAYER] Body decrypt failed: ${bodyResp.body}');
                }
                } catch (e) {
                  print('[inbox][PQC_2_LAYER] HTTP request failed: $e');
                }
              }
            } else if (subEnv.containsKey('otp_key_id') && subEnv.containsKey('ciphertext_b64url')) {
              // This is PQC_2_LAYER hybrid: PQC for key exchange + OTP for message encryption
              print('[inbox][PQC_2_LAYER] Detected PQC_2_LAYER hybrid (PQC key exchange + OTP message encryption)');
              
              // For PQC_2_LAYER, we need to:
              // 1. Use PQC to decrypt the OTP key (if there's a PQC-encrypted key)
              // 2. Use the decrypted OTP key to decrypt the message
              
              // For now, let's try direct OTP decryption since the OTP key might be embedded
              // In a full implementation, we'd first decrypt the PQC-encrypted OTP key
              final subjectResponse = await http.post(
                Uri.parse('http://127.0.0.1:8081/decrypt'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(subEnv),
              );
              final bodyResponse = await http.post(
                Uri.parse('http://127.0.0.1:8081/decrypt'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(bodyEnv),
              );
              
              if (subjectResponse.statusCode == 200) {
                final subjectResult = jsonDecode(subjectResponse.body);
                email.subject = subjectResult['plaintext'] ?? 'Decryption Failed';
                print('[inbox][PQC_2_LAYER] Subject decrypted with hybrid PQC+OTP successfully');
              } else {
                print('[inbox][PQC_2_LAYER] Subject hybrid decryption failed: ${subjectResponse.body}');
              }
              if (bodyResponse.statusCode == 200) {
                final bodyResult = jsonDecode(bodyResponse.body);
                email.body = bodyResult['plaintext'] ?? 'Decryption Failed';
                print('[inbox][PQC_2_LAYER] Body decrypted with hybrid PQC+OTP successfully');
              } else {
                print('[inbox][PQC_2_LAYER] Body hybrid decryption failed: ${bodyResponse.body}');
              }
            } else {
              print('[inbox][PQC_2_LAYER] Unknown data format, cannot decrypt');
            }
          } catch (e) {
            print('PQC 2-layer decryption failed: $e');
          }
        }
        // PQC 3-layer enhanced
        else if (email.encryptionMethod == 'PQC_3_LAYER') {
          try {
            print('[inbox][PQC_3_LAYER] Attempting decryption for email ${email.id}');
            print('[inbox][PQC_3_LAYER] Subject length: ${email.subject.length}, Body length: ${email.body.length}');
            
            Map<String, dynamic> subEnv;
            Map<String, dynamic> bodyEnv;
            
            print('[inbox][PQC_3_LAYER] Raw subject content: "${email.subject}"');
            print('[inbox][PQC_3_LAYER] Raw body content: "${email.body}"');
            
            try {
              subEnv = jsonDecode(email.subject) as Map<String, dynamic>;
              print('[inbox][PQC_3_LAYER] Successfully parsed subject JSON');
            } catch (e) {
              print('[inbox][PQC_3_LAYER] Failed to parse subject JSON: $e');
              print('[inbox][PQC_3_LAYER] Subject content: ${email.subject.substring(0, math.min(100, email.subject.length))}...');
              continue;
            }
            
            try {
              bodyEnv = jsonDecode(email.body) as Map<String, dynamic>;
              print('[inbox][PQC_3_LAYER] Successfully parsed body JSON');
            } catch (e) {
              print('[inbox][PQC_3_LAYER] Failed to parse body JSON: $e');
              print('[inbox][PQC_3_LAYER] Body content: ${email.body.substring(0, math.min(100, email.body.length))}...');
              continue;
            }
            print('[inbox][PQC_3_LAYER] Subject envelope keys: ${subEnv.keys.toList()}');
            print('[inbox][PQC_3_LAYER] Body envelope keys: ${bodyEnv.keys.toList()}');
            
            // Check if this is actually PQC data or OTP data mislabeled
            if (subEnv.containsKey('encryptedBody') && subEnv.containsKey('pqcCiphertext')) {
              // This is actual PQC data
              final priv = EmailService.pqcPrivateKey;
              print('[inbox][PQC_3_LAYER] Private key available: ${priv != null && priv.isNotEmpty}');
              if (priv != null && priv.isNotEmpty) {
              try {
                final subResp = await http.post(
                  Uri.parse('http://localhost:5001/api/pqc/decrypt'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'encryptedBody': subEnv['encryptedBody'],
                    'pqcCiphertext': subEnv['pqcCiphertext'],
                    'encryptedKeyId': subEnv['encryptedKeyId'] ?? subEnv['keyId'] ?? '',
                    'privateKey': priv,
                  }),
                );
                final bodyResp = await http.post(
                  Uri.parse('http://localhost:5001/api/pqc/decrypt'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'encryptedBody': bodyEnv['encryptedBody'],
                    'pqcCiphertext': bodyEnv['pqcCiphertext'],
                    'encryptedKeyId': bodyEnv['encryptedKeyId'] ?? bodyEnv['keyId'] ?? '',
                    'privateKey': priv,
                  }),
                );

                if (subResp.statusCode == 200) {
                  email.subject = (jsonDecode(subResp.body) as Map<String, dynamic>)['data']['plaintext'] ?? email.subject;
                  print('[inbox][PQC_3_LAYER] Subject decrypted successfully');
                } else {
                  print('[inbox][PQC_3_LAYER] Subject decrypt failed: ${subResp.body}');
                }
                if (bodyResp.statusCode == 200) {
                  email.body = (jsonDecode(bodyResp.body) as Map<String, dynamic>)['data']['plaintext'] ?? email.body;
                  print('[inbox][PQC_3_LAYER] Body decrypted successfully');
                } else {
                  print('[inbox][PQC_3_LAYER] Body decrypt failed: ${bodyResp.body}');
                }
              } catch (e) {
                print('[inbox][PQC_3_LAYER] HTTP request failed: $e');
              }
              }
            } else if (subEnv.containsKey('otp_key_id') && subEnv.containsKey('ciphertext_b64url')) {
              // This is PQC_3_LAYER hybrid: PQC for key exchange + AES + OTP for message encryption
              print('[inbox][PQC_3_LAYER] Detected PQC_3_LAYER hybrid (PQC key exchange + AES + OTP message encryption)');
              
              // For PQC_3_LAYER, we need to:
              // 1. Use PQC to decrypt the AES key (if there's a PQC-encrypted AES key)
              // 2. Use AES to decrypt the OTP key
              // 3. Use the OTP key to decrypt the message
              
              // For now, let's try direct OTP decryption since the OTP key might be embedded
              // In a full implementation, we'd first decrypt the PQC-encrypted AES key, then AES-decrypt the OTP key
              final subjectResponse = await http.post(
                Uri.parse('http://127.0.0.1:8081/decrypt'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(subEnv),
              );
              final bodyResponse = await http.post(
                Uri.parse('http://127.0.0.1:8081/decrypt'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(bodyEnv),
              );
              
              if (subjectResponse.statusCode == 200) {
                final subjectResult = jsonDecode(subjectResponse.body);
                email.subject = subjectResult['plaintext'] ?? 'Decryption Failed';
                print('[inbox][PQC_3_LAYER] Subject decrypted with hybrid PQC+AES+OTP successfully');
              } else {
                print('[inbox][PQC_3_LAYER] Subject hybrid decryption failed: ${subjectResponse.body}');
              }
              if (bodyResponse.statusCode == 200) {
                final bodyResult = jsonDecode(bodyResponse.body);
                email.body = bodyResult['plaintext'] ?? 'Decryption Failed';
                print('[inbox][PQC_3_LAYER] Body decrypted with hybrid PQC+AES+OTP successfully');
              } else {
                print('[inbox][PQC_3_LAYER] Body hybrid decryption failed: ${bodyResponse.body}');
              }
            } else {
              print('[inbox][PQC_3_LAYER] Unknown data format, cannot decrypt');
            }
          } catch (e) {
            print('PQC 3-layer decryption failed: $e');
          }
        }
      }
      
      if (mounted) {
        setState(() => _emails = emails);
      }
    } catch (e) {
      print('Error loading emails: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (_useMockInbox && mounted && _emails.isEmpty) {
        _seedMockEmails();
      }
    }
  }

  void _seedMockEmails() {
    final now = DateTime.now();
    final mock = <Email>[
      Email(
        id: '1',
        senderEmail: 'alice@example.com',
        recipientEmail: 'me@example.com',
        subject: 'Welcome to QuMail! Getting started guide 📬',
        body: 'Hi there,\n\nThanks for trying QuMail. This is a sample message so you can test the UI quickly.\n\n- Compose a new email from the left.\n- Tap a message to view details.\n\nCheers,\nThe QuMail Team',
        sentAt: now.subtract(const Duration(minutes: 12)),
        isRead: false,
      ),
      Email(
        id: '2',
        senderEmail: 'billing@service.com',
        recipientEmail: 'me@example.com',
        subject: 'Invoice for October',
        body: 'Your invoice for October is ready. Amount due: \$24.99. Thanks for your business!',
        sentAt: now.subtract(const Duration(hours: 3)),
        isRead: true,
      ),
      Email(
        id: '3',
        senderEmail: 'noreply@notifications.com',
        recipientEmail: 'me@example.com',
        subject: 'Security alert: New sign-in on Windows',
        body: 'We detected a new sign-in to your account from a Windows device. If this was you, no action is needed.',
        sentAt: now.subtract(const Duration(days: 1, hours: 2)),
        isRead: false,
      ),
      Email(
        id: '4',
        senderEmail: 'teammate@company.com',
        recipientEmail: 'me@example.com',
        subject: 'Project update and attachments',
        body: 'Sharing the latest documents for review. Please check the attached files and let me know your thoughts.',
        sentAt: now.subtract(const Duration(days: 2, hours: 5)),
        isRead: true,
      ),
      Email(
        id: '5',
        senderEmail: 'events@community.org',
        recipientEmail: 'me@example.com',
        subject: 'You’re invited: Community meetup this weekend',
        body: 'Join us for our monthly community meetup. Food and drinks provided. RSVP appreciated!',
        sentAt: now.subtract(const Duration(days: 3, minutes: 30)),
        isRead: true,
      ),
    ];
    setState(() {
      _emails = mock;
      if (_selectedEmail == null && MediaQuery.of(context).size.width >= 1000) {
        _selectedEmail = mock.first;
      }
    });
  }

  Future<void> _markAsRead(Email email) async {
    if (email.isRead) return;

    try {
      final success = await _emailService.markAsRead(email.id);
      if (success) {
        setState(() {
          final index = _emails.indexWhere((e) => e.id == email.id);
          if (index != -1) {
            _emails[index] = Email(
              id: email.id,
              senderEmail: email.senderEmail,
              recipientEmail: email.recipientEmail,
              subject: email.subject,
              body: email.body,
              sentAt: email.sentAt,
              isRead: true,
            );
          }
        });
      }
    } catch (e) {
      print('Error marking email as read: $e');
    }
  }

  void _showEmailDetails(Email email) {
    _markAsRead(email);
    final isWide = MediaQuery.of(context).size.width >= 1000;
    if (isWide) {
      setState(() => _selectedEmail = email);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(email.subject),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'From: ${email.senderEmail}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Date: ${_formatDate(email.sentAt)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Text(_isOtpEnvelope(email.body) ? 'Encrypted message (tap Retry to attempt decrypt again)' : email.body),
              const SizedBox(height: 16),
              if (email.attachments.isNotEmpty) ...[
                const Text('Attachments', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: email.attachments.map((a) {
                    final isImg = _isImage(a.contentType, a.fileName);
                    if (isImg) {
                      final bytes = _decodeBase64MaybeUrl(a.contentBase64);
                      if (bytes != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            bytes,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        );
                      }
                    }
                            return ActionChip(
                      label: Text(a.fileName),
                      avatar: const Icon(Icons.download_outlined),
                      onPressed: () async {
                                final data = _decodeBase64MaybeUrl(a.contentBase64);
                                if (data == null) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to decode attachment')));
                                  }
                                  return;
                                }
                                final ext = _inferExt(a.fileName, a.contentType);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saving ${a.fileName}...')));
                                }
                                try {
                                  if (ext.isEmpty) {
                                    await FileSaver.instance.saveFile(
                                      name: a.fileName,
                                      bytes: data,
                                      mimeType: MimeType.other,
                                    );
                                  } else {
                                    await FileSaver.instance.saveFile(
                                      name: a.fileName,
                                      bytes: data,
                                      ext: ext,
                                      mimeType: MimeType.other,
                                    );
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${a.fileName}')));
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save failed')));
                                  }
                                }
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Convert UTC date to local time for display
    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      return 'Today ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else {
      return '${localDate.day}/${localDate.month}/${localDate.year}';
    }
  }

  String _getPreview(String body) {
    if (_isOtpEnvelope(body)) return 'Encrypted message';
    return body.length > 100 ? '${body.substring(0, 100)}...' : body;
  }

  bool _isImage(String contentType, String fileName) {
    if (contentType.toLowerCase().startsWith('image/')) return true;
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  bool _isOtpEnvelope(String body) {
    // crude detection to avoid showing ciphertext JSON to users
    if (body.length < 20) return false;
    if (!body.contains('otp_key_id')) return false;
    if (!body.contains('ciphertext_b64url')) return false;
    return true;
  }

  String _inferExt(String fileName, String contentType) {
    final idx = fileName.lastIndexOf('.');
    if (idx != -1 && idx < fileName.length - 1) return fileName.substring(idx + 1);
    if (contentType.startsWith('image/')) return contentType.split('/').last;
    if (contentType == 'application/pdf') return 'pdf';
    if (contentType.startsWith('text/')) return 'txt';
    return '';
  }

  Uint8List? _decodeBase64MaybeUrl(String input) {
    try {
      // Try standard base64 first
      return Uint8List.fromList(base64Decode(input));
    } catch (_) {
      try {
        // Try base64url variant
        var s = input.replaceAll('-', '+').replaceAll('_', '/');
        switch (s.length % 4) {
          case 2:
            s += '==';
            break;
          case 3:
            s += '=';
            break;
        }
        return Uint8List.fromList(base64Decode(s));
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final blue = Colors.blue;
        final isWide = MediaQuery.of(context).size.width >= 1000;

        Widget buildTopBar() {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: blue.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Q',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'QuMail',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search, color: Colors.grey),
                        SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search mail',
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loadEmails,
                  icon: Icon(Icons.refresh, color: blue.shade700),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.pushNamed(context, Routes.settings),
                  icon: Icon(Icons.settings_outlined, color: blue.shade700),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: blue.shade600,
                    child: Text(
                      (authProvider.user?.name.isNotEmpty == true
                              ? authProvider.user!.name[0]
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget buildSidebar() {
          return Container(
            width: 240,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                right: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pushNamed(context, Routes.compose),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Compose'),
                  ),
                ),
                _SidebarItem(
                  icon: Icons.inbox_outlined,
                  label: 'Inbox',
                  active: true,
                  accent: blue,
                  onTap: () {},
                ),
                _SidebarItem(
                  icon: Icons.flag_outlined,
                  label: 'Flagged',
                  onTap: () {},
                  accent: blue,
                ),
                _SidebarItem(
                  icon: Icons.send_outlined,
                  label: 'Sent',
                  onTap: () => Navigator.pushNamed(context, Routes.sent),
                  accent: blue,
                ),
                _SidebarItem(
                  icon: Icons.drafts_outlined,
                  label: 'Draft',
                  onTap: () {},
                  accent: blue,
                ),
                _SidebarItem(
                  icon: Icons.delete_outline,
                  label: 'Trash',
                  onTap: () {},
                  accent: blue,
                ),
                const Spacer(),
              ],
            ),
          );
        }

        Widget buildEmailList() {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_emails.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Send your first email to get started!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, Routes.compose);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Compose Email'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadEmails,
            child: ListView.builder(
              itemCount: _emails.length,
              itemBuilder: (context, index) {
                final email = _emails[index];
                final isSelected = isWide && _selectedEmail?.id == email.id;
                return InkWell(
                  onTap: () => _showEmailDetails(email),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? blue.shade50 : null,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: email.isRead ? Colors.grey.shade300 : blue,
                          child: Icon(
                            Icons.person,
                            color: email.isRead ? Colors.grey.shade600 : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      email.subject,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDate(email.sentAt),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'From: ${email.senderEmail}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getPreview(email.body),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        if (!email.isRead)
                          Container(
                            margin: const EdgeInsets.only(left: 8, top: 6),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: blue, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }

        Widget buildDetail() {
          final email = _selectedEmail;
          if (email == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_email_unread_outlined, size: 72, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Select a message', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email.subject,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(radius: 14, backgroundColor: Colors.grey.shade300, child: const Icon(Icons.person, size: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From: ${email.senderEmail}', style: TextStyle(color: Colors.grey.shade700)),
                              Text(
                                _formatDate(email.sentAt),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () {}, icon: Icon(Icons.attachment_outlined, color: blue.shade700)),
                        IconButton(onPressed: () {}, icon: Icon(Icons.more_vert, color: Colors.grey.shade700)),
                      ],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_isOtpEnvelope(email.body) ? 'Encrypted message (tap Retry to attempt decrypt again)' : email.body),
                      const SizedBox(height: 16),
                      if (email.attachments.isNotEmpty) ...[
                        const Text('Attachments', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: email.attachments.map((a) {
                            final isImg = _isImage(a.contentType, a.fileName);
                            if (isImg) {
                              try {
                                final bytes = base64Decode(a.contentBase64);
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    Uint8List.fromList(bytes),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              } catch (_) {}
                            }
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.download_outlined),
                              label: Text(a.fileName),
                              onPressed: () async {
                                setState(() { _attachmentStatus = 'Decoding ${a.fileName}...'; });
                                final data = _decodeBase64MaybeUrl(a.contentBase64);
                                if (data == null) {
                                  setState(() { _attachmentStatus = 'Failed to decode ${a.fileName}'; });
                                  return;
                                }
                                final ext = _inferExt(a.fileName, a.contentType);
                                setState(() { _attachmentStatus = 'Choosing location for ${a.fileName}...'; });
                                try {
                                  final suggestedName = ext.isEmpty ? a.fileName : (a.fileName.endsWith('.$ext') ? a.fileName : '${a.fileName}.$ext');
                                  final savePath = await FilePicker.platform.saveFile(
                                    dialogTitle: 'Save attachment',
                                    fileName: suggestedName,
                                    type: FileType.any,
                                  );
                                  if (savePath == null) {
                                    setState(() { _attachmentStatus = 'Save cancelled'; });
                                    return;
                                  }
                                  setState(() { _attachmentStatus = 'Saving to $savePath'; });
                                  final file = io.File(savePath);
                                  await file.writeAsBytes(data, flush: true);
                                  setState(() { _attachmentStatus = 'Saved ${a.fileName} to $savePath'; });
                                } catch (e) {
                                  setState(() { _attachmentStatus = 'Save failed for ${a.fileName}: $e'; });
                                }
                              },
                            );
                          }).toList(),
                        ),
                        if (_attachmentStatus != null) ...[
                          const SizedBox(height: 8),
                          Text(_attachmentStatus!, style: const TextStyle(fontSize: 12)),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (!isWide) {
          // Mobile layout with AppBar (hamburger + settings) and bottom nav (Inbox, Compose)
          return Scaffold(
            appBar: AppBar(
              backgroundColor: blue.shade600,
              foregroundColor: Colors.white,
              centerTitle: false,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: const Text('Inbox'),
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.pushNamed(context, Routes.settings),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.inbox_outlined),
                      title: const Text('Inbox'),
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('Flagged'),
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.drafts_outlined),
                      title: const Text('Drafts'),
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.send_outlined),
                      title: const Text('Sent'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, Routes.sent);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Trash'),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
            body: buildEmailList(),
            bottomNavigationBar: NavigationBar(
              backgroundColor: Colors.white,
              indicatorColor: blue.shade50,
              selectedIndex: 0,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'Inbox'),
                NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: 'Compose'),
              ],
              onDestinationSelected: (i) {
                if (i == 1) {
                  Navigator.pushNamed(context, Routes.compose);
                }
              },
            ),
          );
        }

        // Desktop / wide layout with custom top bar and sidebar
        return Scaffold(
          body: Column(
            children: [
              buildTopBar(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildSidebar(),
                    Container(
                      width: 420,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: buildEmailList(),
                    ),
                    Expanded(
                      child: buildDetail(),
                    ),
                  ],
                ),
              ),
            ],
          )
        );
        }
    );

  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final MaterialColor accent;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? accent.shade50 : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
            left: BorderSide(color: active ? accent.shade600 : Colors.transparent, width: 3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? accent.shade700 : Colors.grey.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? accent.shade800 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}