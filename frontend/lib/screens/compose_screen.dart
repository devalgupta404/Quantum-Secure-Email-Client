import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final EmailService _emailService = EmailService();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isValidatingRecipient = false;
  String? _recipientValidationMessage;

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<bool> _validateRecipient() async {
    final address = _toController.text.trim();
    if (address.isEmpty) {
      setState(() {
        _recipientValidationMessage = 'Please enter recipient email';
      });
      return false;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user?.email == address) {
      setState(() {
        _recipientValidationMessage = 'You cannot send emails to yourself';
      });
      return false;
    }

    setState(() {
      _isValidatingRecipient = true;
      _recipientValidationMessage = null;
    });

    try {
      final exists = await _emailService.validateUser(address);
      if (exists) {
        setState(() {
          _recipientValidationMessage = null;
        });
        return true;
      }
      setState(() {
        _recipientValidationMessage = 'User not found. They need to sign up first.';
      });
      return false;
    } catch (e) {
      setState(() {
        _recipientValidationMessage = 'Error validating user: ${e.toString()}';
      });
      return false;
    } finally {
      setState(() => _isValidatingRecipient = false);
    }
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate recipient on send
    final recipientOk = await _validateRecipient();
    if (!recipientOk) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) {
      _showMessage('Please login first', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await _emailService.sendEmail(
        senderEmail: authProvider.user!.email,
        recipientEmail: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
      );

      if (success) {
        _showMessage('📧 Email sent successfully!', isError: false);
        _clearForm();
        // Navigate to Sent screen after successful send
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(Routes.sent, (route) => false);
          }
        });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _clearForm() {
    _toController.clear();
    _subjectController.clear();
    _bodyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isWide = MediaQuery.of(context).size.width >= 1000;

        Widget formContent() {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // From field (read-only, shows current user)
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
                  
                  // To field with validation (validation occurs on send)
                  TextFormField(
                    controller: _toController,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading && !_isValidatingRecipient,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter recipient email';
                      }
                      if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(value.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  if (_recipientValidationMessage != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _recipientValidationMessage!,
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
          
                  const SizedBox(height: 16),
                  
                  // Subject field
                  TextFormField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: Icon(Icons.subject),
                    ),
                    enabled: !_isLoading,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a subject';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Message body
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, left: 4, right: 8),
                            child: Icon(Icons.message_outlined, color: Colors.grey.shade700),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _bodyController,
                              decoration: const InputDecoration(
                                labelText: 'Message',
                                border: InputBorder.none,
                                alignLabelWithHint: true,
                              ),
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              enabled: !_isLoading,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a message';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  
                  // Send button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendEmail,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isLoading ? 'Sending...' : 'Send Email'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
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
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        child: formContent(),
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