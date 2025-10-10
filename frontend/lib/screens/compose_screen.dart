import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../app.dart';
import '../widgets/inbox_shell.dart';
import '../services/email_service.dart';
import '../providers/auth_provider.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _recipientPublicKeyController = TextEditingController();
  final EmailService _emailService = EmailService();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isValidatingRecipient = false;
  String? _recipientValidationMessage;
  final List<SendAttachment> _attachments = [];
  String _selectedEncryptionMethod = 'OTP';

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _recipientPublicKeyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null) return;
    setState(() {
      _attachments.clear();
      for (final f in result.files) {
        if (f.bytes == null) continue;
        final b64 = base64Encode(f.bytes!);
        _attachments.add(SendAttachment(fileName: f.name, contentType: 'application/octet-stream', contentBase64: b64));
      }
    });
  }

  Future<bool> _validateRecipient() async {
    final address = _toController.text.trim();
    if (address.isEmpty) {
      setState(() { _recipientValidationMessage = 'Please enter recipient email'; });
      return false;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user?.email == address) {
      setState(() { _recipientValidationMessage = 'You cannot send emails to yourself'; });
      return false;
    }

    setState(() { _isValidatingRecipient = true; _recipientValidationMessage = null; });

    try {
      final exists = await _emailService.validateUser(address);
      if (exists) { setState(() { _recipientValidationMessage = null; }); return true; }
      setState(() { _recipientValidationMessage = 'User not found. They need to sign up first.'; });
      return false;
    } catch (e) {
      setState(() { _recipientValidationMessage = 'Error validating user: ${e.toString()}'; });
      return false;
    } finally {
      setState(() => _isValidatingRecipient = false);
    }
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final recipientOk = await _validateRecipient();
    if (!recipientOk) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) { _showMessage('Please login first', isError: true); return; }

    setState(() => _isLoading = true);

    try {
      final success = await _emailService.sendEmail(
        senderEmail: authProvider.user!.email,
        recipientEmail: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
        attachments: _attachments,
        encryptionMethod: _selectedEncryptionMethod,
        recipientPublicKey: _selectedEncryptionMethod.startsWith('PQC') ? _recipientPublicKeyController.text.trim() : null,
      );

      if (success) {
        _showMessage('📧 Email sent successfully!', isError: false);
        _clearForm();
        Future.delayed(const Duration(seconds: 1), () { if (mounted) { Navigator.of(context).pushNamedAndRemoveUntil(Routes.sent, (route) => false); } });
      } else {
        _showMessage('Failed to send email', isError: true);
      }
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    final snackBar = SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green);
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _clearForm() {
    _toController.clear();
    _subjectController.clear();
    _bodyController.clear();
    _recipientPublicKeyController.clear();
    setState(() { 
      _attachments.clear(); 
      _selectedEncryptionMethod = 'OTP';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        Widget formContent() {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'From',
                      prefixIcon: const Icon(Icons.person),
                      hintText: authProvider.user?.email ?? 'Not logged in',
                    ),
                    enabled: false,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _toController,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading && !_isValidatingRecipient,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter recipient email';
                      if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(value.trim())) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  if (_recipientValidationMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_recipientValidationMessage!, style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _subjectController,
                    decoration: const InputDecoration(labelText: 'Subject', prefixIcon: Icon(Icons.subject_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bodyController,
                    decoration: const InputDecoration(labelText: 'Body', alignLabelWithHint: true),
                    maxLines: 8,
                  ),
                  const SizedBox(height: 16),
                  
                  // Encryption Method Selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Encryption Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedEncryptionMethod,
                            decoration: const InputDecoration(
                              labelText: 'Select Encryption Method',
                              prefixIcon: Icon(Icons.security),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'OTP', child: Text('OTP (One-Time Pad)')),
                              DropdownMenuItem(value: 'AES', child: Text('AES-256-GCM')),
                              DropdownMenuItem(value: 'PQC_2_LAYER', child: Text('PQC 2-Layer (Kyber-512 + OTP)')),
                              DropdownMenuItem(value: 'PQC_3_LAYER', child: Text('PQC 3-Layer (Kyber-1024 + AES-256 + OTP)')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedEncryptionMethod = value!;
                              });
                            },
                          ),
                          if (_selectedEncryptionMethod.startsWith('PQC')) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _recipientPublicKeyController,
                              decoration: const InputDecoration(
                                labelText: 'Recipient Public Key',
                                prefixIcon: Icon(Icons.key),
                                hintText: 'Enter recipient\'s PQC public key (Base64)',
                              ),
                              maxLines: 3,
                              validator: (value) {
                                if (_selectedEncryptionMethod.startsWith('PQC') && (value == null || value.trim().isEmpty)) {
                                  return 'Public key is required for PQC encryption';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickAttachments,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add Attachments'),
                      ),
                      ..._attachments.map((a) => Chip(label: Text(a.fileName))).toList(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendEmail,
                    icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                    label: Text(_isLoading ? 'Sending...' : 'Send Email'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ],
              ),
            ),
          );
        }

        if (!isWide) {
          return MobileScaffoldShell(title: 'Compose', body: formContent());
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
                    const InboxSidebar(active: 'compose'),
                    Expanded(child: Container(color: Colors.white, child: formContent())),
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