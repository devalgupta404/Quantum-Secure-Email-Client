import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  static const String _baseUrl = 'http://localhost:5000/api';

  Future<bool> validateUser(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/validate-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['exists'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendEmail({
    required String senderEmail,
    required String recipientEmail,
    required String subject,
    required String body,
  }) async {
    try {
      final requestBody = {
        'senderEmail': senderEmail,
        'recipientEmail': recipientEmail,
        'subject': subject,
        'body': body,
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<Email>> getInbox(String userEmail) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/email/inbox/$userEmail'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailsJson = data['emails'] as List;
          return emailsJson.map((emailJson) => Email.fromJson(emailJson)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Email>> getSentEmails(String userEmail) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/email/sent/$userEmail'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final emailsJson = data['emails'] as List;
          return emailsJson.map((emailJson) => Email.fromJson(emailJson)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> markAsRead(String emailId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/mark-read/$emailId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class Email {
  final String id;
  final String senderEmail;
  final String recipientEmail;
  final String subject;
  final String body;
  final DateTime sentAt;
  final bool isRead;

  Email({
    required this.id,
    required this.senderEmail,
    required this.recipientEmail,
    required this.subject,
    required this.body,
    required this.sentAt,
    required this.isRead,
  });

  factory Email.fromJson(Map<String, dynamic> json) {
    return Email(
      id: json['id'],
      senderEmail: json['senderEmail'],
      recipientEmail: json['recipientEmail'],
      subject: json['subject'],
      body: json['body'],
      sentAt: DateTime.parse(json['sentAt']),
      isRead: json['isRead'] ?? false,
    );
  }
}
