import 'user.dart';

class LoginRequest {
  final String email;
  final String password;

  LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class RegisterRequest {
  final String email;
  final String password;
  final String name;
  final String? username;
  final String externalEmail; // required
  final String emailProvider; // required gmail | yahoo | outlook
  final String appPassword; // required; 16 chars

  RegisterRequest({required this.email, required this.password, required this.name, this.username, required this.externalEmail, required this.emailProvider, required this.appPassword});

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    'name': name,
    if (username != null && username!.isNotEmpty) 'username': username,
    'externalEmail': externalEmail,
    'emailProvider': emailProvider,
    'appPassword': appPassword,
  };
}

class AuthResponse {
  final String token;
  final User user;

  AuthResponse({required this.token, required this.user});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    token: json['token'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );
}
