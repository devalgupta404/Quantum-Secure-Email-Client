import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/sent_screen.dart';
import 'screens/compose_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/decrypt_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'utils/slide_route.dart';

class Routes {
  static const String splash = '/';
  static const String home = '/home';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String inbox = '/inbox';
  static const String sent = '/sent';
  static const String compose = '/compose';
  static const String settings = '/settings';
  static const String decrypt = '/decrypt';
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
      initialRoute: Routes.splash,
      routes: <String, WidgetBuilder>{
        Routes.splash: (_) => const SplashScreen(),
        Routes.home: (_) => const AuthWrapper(),
        Routes.login: (_) => const LoginScreen(),
        Routes.signup: (_) => const SignupScreen(),
        Routes.inbox: (_) => const InboxScreen(),
        Routes.sent: (_) => const SentScreen(),
        Routes.compose: (_) => const ComposeScreen(),
        Routes.settings: (_) => const SettingsScreen(),
        Routes.decrypt: (_) => const DecryptScreen(),
      },
      onGenerateRoute: (settings) {
        // Custom route transitions for specific screens
        switch (settings.name) {
          case Routes.inbox:
            return SlideRoute(
              page: const InboxScreen(),
              routeName: Routes.inbox,
            );
          case Routes.sent:
            return SlideRoute(
              page: const SentScreen(),
              routeName: Routes.sent,
            );
          case Routes.compose:
            return SlideUpRoute(
              page: const ComposeScreen(),
              routeName: Routes.compose,
            );
          default:
            return null; // Use default route
        }
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        switch (authProvider.status) {
          case AuthStatus.initial:
          case AuthStatus.loading:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.authenticated:
            return const InboxScreen();
          case AuthStatus.unauthenticated:
          case AuthStatus.error:
            return const LoginScreen();
        }
      },
    );
  }
}

