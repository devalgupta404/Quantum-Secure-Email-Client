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
  final String? externalEmail;
  final String? emailProvider; // gmail | yahoo | outlook
  final String? appPassword; // optional; 16 chars typical

  RegisterRequest({required this.email, required this.password, required this.name, this.username, this.externalEmail, this.emailProvider, this.appPassword});

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    'name': name,
    if (username != null && username!.isNotEmpty) 'username': username,
    if (externalEmail != null && externalEmail!.isNotEmpty) 'externalEmail': externalEmail,
    if (emailProvider != null && emailProvider!.isNotEmpty) 'emailProvider': emailProvider,
    if (appPassword != null && appPassword!.isNotEmpty) 'appPassword': appPassword,
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
