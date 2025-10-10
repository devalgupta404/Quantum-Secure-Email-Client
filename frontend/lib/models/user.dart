class User {
  final String id;
  final String email;
  final String name;
  final String? avatar;
  final String? externalEmail;
  final String? emailProvider;

  User({required this.id, required this.email, required this.name, this.avatar, this.externalEmail, this.emailProvider});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    avatar: json['avatar'] as String?,
    externalEmail: json['externalEmail'] as String?,
    emailProvider: json['emailProvider'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'avatar': avatar,
    'externalEmail': externalEmail,
    'emailProvider': emailProvider,
  };
}
