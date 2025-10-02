import 'package:flutter/material.dart';
import '../widgets/app_scaffold.dart';

class ComposeScreen extends StatelessWidget {
  const ComposeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController toController = TextEditingController();
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController bodyController = TextEditingController();

    return AppScaffold(
      title: 'Compose',
      currentIndex: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: toController,
              decoration: const InputDecoration(
                labelText: 'To',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.subject),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Security Level'),
                    value: 'otp',
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'otp', child: Text('🔒 Quantum Secure (OTP)')),
                      DropdownMenuItem(value: 'qaes', child: Text('🔐 Quantum-AES (Coming Soon)'), enabled: false),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: bodyController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Send (stub)')),
                  );
                },
                icon: const Icon(Icons.send),
                label: const Text('Send Quantum Secure'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

