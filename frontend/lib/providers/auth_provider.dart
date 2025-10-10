import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  AuthStatus _status = AuthStatus.initial;
  User? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    _setStatus(AuthStatus.loading);
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn) {
        final user = await _authService.getCurrentUser();
        if (user != null) {
          _user = user;
          _setStatus(AuthStatus.authenticated);
          
          // Initialize PQC keys for authenticated user
          try {
            final ok = await EmailService.initializePqcKeys();
            if (ok && EmailService.pqcPublicKey != null && _user != null) {
              // Register public key with backend so others can fetch it
              await EmailService.registerMyPqcPublicKey(_user!.email, EmailService.pqcPublicKey!);
            }
          } catch (e) {
            // PQC key initialization failure shouldn't prevent login
            debugPrint('Failed to initialize PQC keys: $e');
          }
        } else {
          _setStatus(AuthStatus.unauthenticated);
        }
      } else {
        _setStatus(AuthStatus.unauthenticated);
      }
    } catch (e) {
      _setStatus(AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password) async {
    _setStatus(AuthStatus.loading);
    _clearError();
    try {
      final authResponse = await _authService.login(email, password);
      _user = authResponse.user;
      _setStatus(AuthStatus.authenticated);
      
      // Initialize PQC keys after successful login
      try {
        final ok = await EmailService.initializePqcKeys();
        if (ok && EmailService.pqcPublicKey != null && _user != null) {
          await EmailService.registerMyPqcPublicKey(_user!.email, EmailService.pqcPublicKey!);
        }
      } catch (e) {
        // PQC key initialization failure shouldn't prevent login
        debugPrint('Failed to initialize PQC keys after login: $e');
      }
      
      return true;
    } catch (e) {
      _setError(e.toString());
      _setStatus(AuthStatus.error);
      return false;
    }
  }

  Future<bool> register(String email, String password, String name, {String? username, required String externalEmail, required String emailProvider, required String appPassword}) async {
    _setStatus(AuthStatus.loading);
    _clearError();
    try {
      final authResponse = await _authService.register(email, password, name,
          username: username, externalEmail: externalEmail, emailProvider: emailProvider, appPassword: appPassword);
      _user = authResponse.user;
      _setStatus(AuthStatus.authenticated);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setStatus(AuthStatus.error);
      return false;
    }
  }

  Future<void> logout() async {
    _setStatus(AuthStatus.loading);
    try {
      await _authService.logout();
      _user = null;
      _clearError();
      _setStatus(AuthStatus.unauthenticated);
    } catch (e) {
      _setError(e.toString());
      _setStatus(AuthStatus.error);
    }
  }

  Future<void> clearAllData() async {
    _setStatus(AuthStatus.loading);
    try {
      await _authService.clearAllData();
      _user = null;
      _clearError();
      _setStatus(AuthStatus.unauthenticated);
    } catch (e) {
      _setError(e.toString());
      _setStatus(AuthStatus.error);
    }
  }

  void clearError() {
    _clearError();
    if (_status == AuthStatus.error) _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
