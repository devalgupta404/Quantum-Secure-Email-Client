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
import '../utils/base64_utils.dart';

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

  bool _isInitialLoad = true;


  Future<void> _loadEmails() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) {
      if (_useMockInbox && mounted) {
        _seedMockEmails();
      }
      return;
    }

    try {
      // Load emails directly without showing cached emails first
      // This prevents the confusing "old emails then refresh" behavior
      final emails = await _emailService.getInbox(authProvider.user!.email);
      print('[inbox] Loaded ${emails.length} emails');
      
      if (mounted) {
        setState(() {
          _emails = emails;
          _isInitialLoad = false; // Mark initial load as complete
        });
        
        // Check for corrupted attachments after loading
        Future.delayed(const Duration(milliseconds: 500), () {
          _checkAndFixCorruptedAttachments();
        });
      }
    } catch (e) {
      print('Error loading emails: $e');
      if (mounted) {
        setState(() {
          _isInitialLoad = false; // Mark load as complete even on error
        });
      }
    }
    
    if (_useMockInbox && mounted && _emails.isEmpty) {
      _seedMockEmails();
    }
  }

  /// Force refresh - clears cache and fetches fresh data
  Future<void> _forceRefresh() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) return;

    try {
      // Clear cache and fetch fresh data
      final emails = await _emailService.refreshInbox(authProvider.user!.email);
      if (mounted) {
        setState(() {
          _emails = emails;
          _isInitialLoad = false; // Mark as no longer initial load
        });
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inbox refreshed successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error force refreshing emails: $e');
      if (mounted) {
        setState(() {
          _isInitialLoad = false; // Mark as no longer initial load even on error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing inbox: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Check if any emails have corrupted attachments and refresh if needed
  Future<void> _checkAndFixCorruptedAttachments() async {
    bool hasCorruptedAttachments = false;
    
    for (final email in _emails) {
      for (final attachment in email.attachments) {
        final decoded = _decodeBase64MaybeUrl(attachment.contentBase64);
        if (decoded == null) {
          print('[inbox] Found corrupted attachment: ${attachment.fileName} in email ${email.id}');
          hasCorruptedAttachments = true;
          break;
        }
      }
      if (hasCorruptedAttachments) break;
    }
    
    if (hasCorruptedAttachments) {
      print('[inbox] Detected corrupted attachments, clearing cache and refreshing...');
      await _forceRefresh();
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
        title: Text(_extractPlaintext(email.subject)),
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
              Text(_isOtpEnvelope(email.body) ? 'Encrypted message (tap Retry to attempt decrypt again)' : _extractPlaintext(email.body)),
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
                        return GestureDetector(
                          onTap: () async {
                            // Show downloading dialog
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text('Downloading ${a.fileName}...'),
                                  ],
                                ),
                              ),
                            );

                            try {
                              await FileSaver.instance.saveFile(
                                name: a.fileName,
                                bytes: bytes,
                                ext: _inferExt(a.fileName, a.contentType),
                                mimeType: MimeType.other,
                              );

                              if (mounted) Navigator.pop(context);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Downloaded ${a.fileName}'), backgroundColor: Colors.green)
                                );
                              }
                            } catch (e) {
                              if (mounted) Navigator.pop(context);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red)
                                );
                              }
                            }
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(
                                  bytes,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.download, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    }
                            return ActionChip(
                      label: Text(a.fileName),
                      avatar: const Icon(Icons.download_outlined),
                      onPressed: () async {
                                // Show downloading dialog
                                if (!mounted) return;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => AlertDialog(
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text('Downloading ${a.fileName}...'),
                                      ],
                                    ),
                                  ),
                                );

                                try {
                                  final data = _decodeBase64MaybeUrl(a.contentBase64);
                                  if (data == null) {
                                    if (mounted) Navigator.pop(context);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Failed to decode attachment'))
                                      );
                                    }
                                    return;
                                  }

                                  final ext = _inferExt(a.fileName, a.contentType);
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

                                  if (mounted) Navigator.pop(context);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Downloaded ${a.fileName}'), backgroundColor: Colors.green)
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) Navigator.pop(context);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red)
                                    );
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
    final cleanBody = _extractPlaintext(body);
    return cleanBody.length > 100 ? '${cleanBody.substring(0, 100)}...' : cleanBody;
  }

  String _extractPlaintext(String content) {
    try {
      // If content doesn't look like JSON, return as-is
      if (!content.trim().startsWith('{')) {
        return content;
      }

      // Try to parse as JSON
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Check for various plaintext keys
      if (json.containsKey('plaintext')) {
        return json['plaintext'] as String;
      }

      // If it's an encryption envelope (encrypted data), show a user-friendly message
      if (json.containsKey('encryptedBody') ||
          json.containsKey('pqcCiphertext') ||
          json.containsKey('ciphertext_b64url') ||
          json.containsKey('ciphertextHex')) {
        return '[Encrypted message - decryption in progress]';
      }

      // Otherwise return original content
      return content;
    } catch (e) {
      // If JSON parsing fails, return original content
      return content;
    }
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
    print('[_decodeBase64MaybeUrl] Input length: ${input.length}');
    print('[_decodeBase64MaybeUrl] Input preview: ${input.substring(0, input.length > 50 ? 50 : input.length)}');

    // Check if input is null or empty
    if (input.isEmpty) {
      print('[_decodeBase64MaybeUrl] ❌ Input is empty');
      return null;
    }

    // Use Base64Utils for consistent decoding
    print('[_decodeBase64MaybeUrl] Debug info: ${Base64Utils.getDebugInfo(input)}');

    try {
      print('[_decodeBase64MaybeUrl] Using Base64Utils.safelyDecode...');
      final result = Base64Utils.safelyDecode(input);
      print('[_decodeBase64MaybeUrl] ✅ Decode succeeded, ${result.length} bytes');
      return result;
    } catch (e) {
      print('[_decodeBase64MaybeUrl] ❌ Decode failed: $e');
      
      // Try alternative decoding methods
      try {
        print('[_decodeBase64MaybeUrl] Trying alternative base64 decode...');
        var s = input.trim();
        final dataUrlIdx = s.indexOf('base64,');
        if (dataUrlIdx != -1) {
          s = s.substring(dataUrlIdx + 7);
        }
        final result = Uint8List.fromList(base64Decode(s));
        print('[_decodeBase64MaybeUrl] ✅ Alternative decode succeeded, ${result.length} bytes');
        return result;
      } catch (e2) {
        print('[_decodeBase64MaybeUrl] ❌ Alternative decode also failed: $e2');
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
                  tooltip: 'Refresh (clears cache)',
                  onPressed: _forceRefresh,
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
          // Show loading indicator only during initial load when no emails are present
          if (_isInitialLoad && _emails.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading your emails...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
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
            onRefresh: _forceRefresh,
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
                                      _extractPlaintext(email.subject),
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
                      _extractPlaintext(email.subject),
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
                      Text(_isOtpEnvelope(email.body) ? 'Encrypted message (tap Retry to attempt decrypt again)' : _extractPlaintext(email.body)),
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
                                return GestureDetector(
                                  onTap: () async {
                                    // Show downloading dialog
                                    if (!mounted) return;
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) => AlertDialog(
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const CircularProgressIndicator(),
                                            const SizedBox(height: 16),
                                            Text('Downloading ${a.fileName}...'),
                                          ],
                                        ),
                                      ),
                                    );

                                    try {
                                      await FileSaver.instance.saveFile(
                                        name: a.fileName,
                                        bytes: Uint8List.fromList(bytes),
                                        ext: _inferExt(a.fileName, a.contentType),
                                        mimeType: MimeType.other,
                                      );

                                      if (mounted) Navigator.pop(context);
                                      setState(() { _attachmentStatus = 'Downloaded ${a.fileName}'; });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Downloaded ${a.fileName}'), backgroundColor: Colors.green)
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) Navigator.pop(context);
                                      setState(() { _attachmentStatus = 'Download failed: $e'; });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red)
                                        );
                                      }
                                    }
                                  },
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.memory(
                                          Uint8List.fromList(bytes),
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.download, color: Colors.white, size: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } catch (_) {}
                            }
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.download_outlined),
                              label: Text(a.fileName),
                              onPressed: () async {
                                print('[inbox_download] ===== DOWNLOAD CLICKED =====');
                                print('[inbox_download] File: ${a.fileName}');
                                print('[inbox_download] Content Type: ${a.contentType}');
                                print('[inbox_download] Base64 length: ${a.contentBase64.length}');
                                print('[inbox_download] Base64 preview: ${a.contentBase64.substring(0, a.contentBase64.length > 100 ? 100 : a.contentBase64.length)}');

                                // Show downloading dialog
                                if (!mounted) return;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => AlertDialog(
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text('Downloading ${a.fileName}...'),
                                      ],
                                    ),
                                  ),
                                );

                                try {
                                  print('[inbox_download] Attempting to decode base64...');
                                  final data = _decodeBase64MaybeUrl(a.contentBase64);
                                  if (data == null) {
                                    print('[inbox_download] ❌ Failed to decode base64!');
                                    if (mounted) Navigator.pop(context);
                                    setState(() { _attachmentStatus = 'Failed to decode ${a.fileName}'; });
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to decode attachment: ${a.fileName}'), backgroundColor: Colors.red)
                                      );
                                    }
                                    return;
                                  }
                                  print('[inbox_download] ✅ Successfully decoded base64, ${data.length} bytes');

                                  final ext = _inferExt(a.fileName, a.contentType);
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

                                  if (mounted) Navigator.pop(context);
                                  setState(() { _attachmentStatus = 'Downloaded ${a.fileName}'; });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Downloaded ${a.fileName}'), backgroundColor: Colors.green)
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) Navigator.pop(context);
                                  setState(() { _attachmentStatus = 'Download failed: $e'; });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red)
                                    );
                                  }
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