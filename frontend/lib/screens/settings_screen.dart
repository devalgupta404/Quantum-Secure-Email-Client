import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/inbox_shell.dart';
import '../providers/auth_provider.dart';
import '../app.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;

    Widget settingsList(AuthProvider authProvider) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(authProvider.user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(authProvider.user?.name ?? 'User', style: Theme.of(context).textTheme.titleLarge),
                  Text(authProvider.user?.email ?? 'user@example.com', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(elevation: 0, child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('QuMail Email System'),
          )),
          const Divider(height: 24),
          Card(elevation: 0, color: Colors.red[50], child: ListTile(
            leading: Icon(Icons.logout, color: Colors.red[700]),
            title: Text('Logout', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w500)),
            onTap: () => _showLogoutDialog(context, authProvider),
          )),
        ],
      );
    }

    if (!isWide) {
      return Consumer<AuthProvider>(
        builder: (context, authProvider, child) => MobileScaffoldShell(
          title: 'Settings',
          body: settingsList(authProvider),
        ),
      );
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) => Scaffold(
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
                  const InboxSidebar(active: 'settings'),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: settingsList(authProvider),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Logout'),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await authProvider.logout();
            if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (route) => false);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Logout'),
        ),
      ],
    ));
  }
}

