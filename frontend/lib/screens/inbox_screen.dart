import 'package:flutter/material.dart';
import '../widgets/app_scaffold.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Inbox',
      currentIndex: 0,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              Icon(Icons.inbox_outlined, size: 48),
              SizedBox(height: 12),
              Text('No messages yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('Your inbox will appear here once connected to the backend.', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

