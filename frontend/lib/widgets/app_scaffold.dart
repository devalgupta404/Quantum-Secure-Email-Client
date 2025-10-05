import 'package:flutter/material.dart';
import '../app.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.currentIndex,
  });

  final String title;
  final Widget child;
  final int currentIndex;

  void _onNavTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    switch (index) {
      case 0:
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.inbox, (r) => false);
        break;
      case 1:
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.sent, (r) => false);
        break;
      case 2:
        Navigator.of(context).pushNamed(Routes.compose);
        break;
      case 3:
        Navigator.of(context).pushNamed(Routes.settings);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => _onNavTap(context, i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'Inbox'),
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Sent'),
          NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: 'Compose'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

