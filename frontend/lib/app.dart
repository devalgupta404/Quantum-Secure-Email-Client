import 'package:flutter/material.dart';
import 'screens/inbox_screen.dart';
import 'screens/compose_screen.dart';
import 'screens/settings_screen.dart';

class Routes {
  static const String inbox = '/';
  static const String compose = '/compose';
  static const String settings = '/settings';
}

class QuMailApp extends StatelessWidget {
  const QuMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuMail',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      initialRoute: Routes.inbox,
      routes: <String, WidgetBuilder>{
        Routes.inbox: (_) => const InboxScreen(),
        Routes.compose: (_) => const ComposeScreen(),
        Routes.settings: (_) => const SettingsScreen(),
      },
    );
  }
}

