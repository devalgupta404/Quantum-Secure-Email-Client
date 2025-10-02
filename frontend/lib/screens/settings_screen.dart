import 'package:flutter/material.dart';
import '../widgets/app_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settings',
      currentIndex: 2,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Email Account Setup'),
              subtitle: const Text('Gmail/Yahoo configuration (stub)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('Show Security Status Indicator'),
            subtitle: const Text('Visual security level display (stub)'),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('One-Time Pad QuMail (frontend only)'),
          ),
        ],
      ),
    );
  }
}

