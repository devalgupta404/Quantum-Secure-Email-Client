import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../widgets/inbox_shell.dart';
import '../services/email_service.dart';
import '../providers/auth_provider.dart';
import '../app.dart';

class SentScreen extends StatefulWidget {
  const SentScreen({super.key});

  @override
  State<SentScreen> createState() => _SentScreenState();
}

class _SentScreenState extends State<SentScreen> {
  final EmailService _emailService = EmailService();
  List<Email> _emails = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEmails();
  }

  Future<void> _loadEmails() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) return;

    setState(() => _isLoading = true);

    try {
      final emails = await _emailService.getSentEmails(authProvider.user!.email);

      // Decrypt AES messages (by method or by envelope shape)
      for (var email in emails) {
        final looksLikeAes = () {
          try {
            final je = jsonDecode(email.body);
            return (je is Map) && (
              je.containsKey('keyId') && je.containsKey('ivHex') && je.containsKey('ciphertextHex') && je.containsKey('tagHex') ||
              je.containsKey('key_id') && je.containsKey('iv_hex') && je.containsKey('ciphertext_hex') && je.containsKey('tag_hex')
            );
          } catch (_) { return false; }
        }();

        if (email.encryptionMethod == 'AES' || looksLikeAes) {
          try {
            final subjectEnvelope = jsonDecode(email.subject);
            final bodyEnvelope = jsonDecode(email.body);

            final subUri = Uri.parse('http://localhost:5000/api/aes/decrypt?envelope=${Uri.encodeComponent(jsonEncode(subjectEnvelope))}');
            final bodyUri = Uri.parse('http://localhost:5000/api/aes/decrypt?envelope=${Uri.encodeComponent(jsonEncode(bodyEnvelope))}');

            final subjectResponse = await http.get(subUri);
            final bodyResponse = await http.get(bodyUri);

            // ignore: avoid_print
            print('[sent][AES] decrypt subject status=${subjectResponse.statusCode} body.len=${subjectResponse.body.length}');
            if (subjectResponse.statusCode == 200) {
              final subjectResult = jsonDecode(subjectResponse.body);
              email.subject = subjectResult['plaintext'] ?? email.subject;
            }

            // ignore: avoid_print
            print('[sent][AES] decrypt body status=${bodyResponse.statusCode} body.len=${bodyResponse.body.length}');
            if (bodyResponse.statusCode == 200) {
              final bodyResult = jsonDecode(bodyResponse.body);
              email.body = bodyResult['plaintext'] ?? email.body;
            }
          } catch (e) {
            // ignore: avoid_print
            print('[sent][AES] decrypt failed: $e');
            // leave encrypted text if decrypt fails
          }
        }
      }

      setState(() => _emails = emails);
    } catch (e) {
      print('Error loading sent emails: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showEmailDetails(Email email) {
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
                'To: ${email.recipientEmail}',
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
                        await FileSaver.instance.saveFile(
                          name: a.fileName,
                          bytes: data,
                          ext: _inferExt(a.fileName, a.contentType),
                          mimeType: MimeType.other,
                        );
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
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getPreview(String body) {
    if (_isOtpEnvelope(body)) return 'Encrypted message';
    return body.length > 100 ? '${body.substring(0, 100)}...' : body;
  }

  bool _isOtpEnvelope(String body) {
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
      var s = input.trim();
      final dataUrlIdx = s.indexOf('base64,');
      if (dataUrlIdx != -1) {
        s = s.substring(dataUrlIdx + 7);
      }
      return Uint8List.fromList(base64Decode(s));
    } catch (_) {
      try {
        var s = input.replaceAll('-', '+').replaceAll('_', '/').trim();
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

  bool _isImage(String contentType, String fileName) {
    if (contentType.toLowerCase().startsWith('image/')) return true;
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isWide = MediaQuery.of(context).size.width >= 1000;

        Widget sentList() {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      'Sent Emails',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _loadEmails,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _emails.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.send_outlined,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No sent emails yet',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Start sending emails to see them here!',
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
                          )
                        : RefreshIndicator(
                            onRefresh: _loadEmails,
                            child: ListView.builder(
                              itemCount: _emails.length,
                              itemBuilder: (context, index) {
                                final email = _emails[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border(
                                      bottom: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green.shade100,
                                      child: Icon(
                                        Icons.send,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      email.subject,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'To: ${email.recipientEmail}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          _getPreview(email.body),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatDate(email.sentAt),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _showEmailDetails(email),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          );
        }

        if (!isWide) {
          return MobileScaffoldShell(title: 'Sent', body: sentList());
        }

        return Scaffold(
          body: Column(
            children: [
              InboxTopBar(trailing: [
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.pushNamed(context, Routes.settings),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ]),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const InboxSidebar(active: 'sent'),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        child: sentList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
