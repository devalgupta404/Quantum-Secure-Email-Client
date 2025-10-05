import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../models/user.dart';
import '../models/auth_requests.dart';

class AuthService {
  static const String _baseUrl = 'http://localhost:5000/api';
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

  Future<AuthResponse> register(String email, String password, String name) async {
    try {
      final request = RegisterRequest(email: email, password: password, name: name);
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
      final jwt = JWT.decode(token);
      final userId = jwt.payload['nameid'] as String?;
      final email = jwt.payload['email'] as String?;
      final name = jwt.payload['unique_name'] as String?;
      
      if (userId != null && email != null && name != null) {
        return User(id: userId, email: email, name: name, avatar: null);
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
}
