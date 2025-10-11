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
                  Text(authProvider.user?.externalEmail ?? authProvider.user?.email ?? 'No email available', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
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
          const SizedBox(height: 8),
          Card(elevation: 0, color: Colors.red[100], child: ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red[800]),
            title: Text('Delete Account', style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.w600)),
            subtitle: Text('Permanently delete your account and all data', style: TextStyle(color: Colors.red[700])),
            onTap: () => _showDeleteAccountDialog(context, authProvider),
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

  void _showDeleteAccountDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700], size: 28),
            const SizedBox(width: 8),
            const Text('Delete Account'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you absolutely sure you want to delete your account?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text('This action will permanently:'),
            const SizedBox(height: 8),
            const Text('• Delete your account and profile'),
            const Text('• Remove all your emails (sent and received)'),
            const Text('• Delete all your PQC keys'),
            const Text('• Clear all your data'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: const Text(
                'This action cannot be undone!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _showFinalDeleteConfirmation(context, authProvider),
            style: TextButton.styleFrom(foregroundColor: Colors.red[800]),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }

  void _showFinalDeleteConfirmation(BuildContext context, AuthProvider authProvider) {
    Navigator.of(context).pop(); // Close the first dialog
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[800], size: 28),
            const SizedBox(width: 8),
            const Text('Final Confirmation'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This is your last chance to cancel.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Text(
              'Type "DELETE" to confirm you want to permanently delete your account.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              // Show loading dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Deleting account...'),
                    ],
                  ),
                ),
              );
              
              final success = await authProvider.deleteAccount();
              
              if (context.mounted) {
                Navigator.of(context).pop(); // Close loading dialog
                
                if (success) {
                  // Show success message and navigate to home
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 28),
                          SizedBox(width: 8),
                          Text('Account Deleted'),
                        ],
                      ),
                      content: const Text('Your account has been permanently deleted.'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (route) => false);
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                } else {
                  // Show error message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete account: ${authProvider.errorMessage}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red[800]),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }
}

