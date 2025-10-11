import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../models/user.dart';
import '../models/auth_requests.dart';

class AuthService {
  static const String _baseUrl = 'http://localhost:5001/api';
  static const String _tokenKey = 'auth_token';

  Future<AuthResponse> login(String email, String password) async {
    try {
      final request = LoginRequest(email: email, password: password);
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(json.decode(response.body));
        await _saveToken(authResponse.token);
        return authResponse;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Login failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<AuthResponse> register(String email, String password, String name, {String? username, required String externalEmail, required String emailProvider, required String appPassword}) async {
    try {
      final request = RegisterRequest(
        email: email,
        password: password,
        name: name,
        username: username,
        externalEmail: externalEmail,
        emailProvider: emailProvider,
        appPassword: appPassword,
      );
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(json.decode(response.body));
        await _saveToken(authResponse.token);
        return authResponse;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Registration failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<void> logout() async {
    await _removeToken();
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<bool> isLoggedIn() async {
    final token = await _getToken();
    if (token == null) return false;

    try {
      final jwt = JWT.decode(token);
      final exp = jwt.payload['exp'] as int?;
      if (exp != null) {
        final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        return !DateTime.now().isAfter(expiryDate);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<User?> getCurrentUser() async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        return User(
          id: userData['id'] as String,
          email: userData['email'] as String,
          name: userData['name'] as String,
          avatar: userData['avatarUrl'] as String?,
          externalEmail: userData['externalEmail'] as String?,
          emailProvider: userData['emailProvider'] as String?,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getAuthToken() async => await _getToken();

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String?> refreshToken() async {
    try {
      final currentToken = await _getToken();
      if (currentToken == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $currentToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['token'] as String;
        await _saveToken(newToken);
        return newToken;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteAccount() async {
    try {
      final currentToken = await _getToken();
      if (currentToken == null) throw Exception('No authentication token found');

      final response = await http.delete(
        Uri.parse('$_baseUrl/auth/delete-account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $currentToken',
        },
      );

      if (response.statusCode == 200) {
        // Clear all local data after successful deletion
        await clearAllData();
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Account deletion failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }
}
