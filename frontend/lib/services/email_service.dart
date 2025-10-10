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
    List<SendAttachment>? attachments,
    String encryptionMethod = 'OTP',
    String? recipientPublicKey,
  }) async {
    try {
      // Diagnostics
      // ignore: avoid_print
      print('[sendEmail] method=$encryptionMethod sender=$senderEmail recipient=$recipientEmail');
      // ignore: avoid_print
      print('[sendEmail] subject(plain)="${subject}" body(plain.len)=${body.length}');

      String finalSubject = subject;
      String finalBody = body;
      
      // Encrypt based on method
      if (encryptionMethod == 'AES') {
        // AES encryption via backend proxy (GET)
        final encSubUri = Uri.parse('$_baseUrl/aes/encrypt?plaintext=${Uri.encodeComponent(subject)}');
        final encBodyUri = Uri.parse('$_baseUrl/aes/encrypt?plaintext=${Uri.encodeComponent(body)}');

        final subjectResponse = await http.get(encSubUri);
        final bodyResponse = await http.get(encBodyUri);

        // ignore: avoid_print
        print('[sendEmail][AES] encrypt subject status=${subjectResponse.statusCode} body.len=${subjectResponse.body.length}');
        // ignore: avoid_print
        print('[sendEmail][AES] encrypt body   status=${bodyResponse.statusCode} body.len=${bodyResponse.body.length}');

        if (subjectResponse.statusCode == 200 && bodyResponse.statusCode == 200) {
          finalSubject = subjectResponse.body; // already JSON envelope
          finalBody = bodyResponse.body;       // already JSON envelope
          // ignore: avoid_print
          print('[sendEmail][AES] finalSubject.preview=${finalSubject.substring(0, finalSubject.length > 120 ? 120 : finalSubject.length)}');
          // ignore: avoid_print
          print('[sendEmail][AES] finalBody.preview=${finalBody.substring(0, finalBody.length > 120 ? 120 : finalBody.length)}');
        } else {
          throw Exception('AES encryption failed');
        }
      } else if (encryptionMethod == 'OTP') {
        // OTP encryption via otp_api_test.py
        final subjectResponse = await http.post(
          Uri.parse('http://127.0.0.1:8081/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'plaintext': subject}),
        );
        
        final bodyResponse = await http.post(
          Uri.parse('http://127.0.0.1:8081/encrypt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'plaintext': body}),
        );
        
        if (subjectResponse.statusCode == 200 && bodyResponse.statusCode == 200) {
          finalSubject = jsonEncode(jsonDecode(subjectResponse.body));
          finalBody = jsonEncode(jsonDecode(bodyResponse.body));
        } else {
          throw Exception('OTP encryption failed');
        }
      }

      final requestBody = {
        'senderEmail': senderEmail,
        'recipientEmail': recipientEmail,
        'subject': finalSubject,
        'body': finalBody,
        'encryptionMethod': encryptionMethod,
        if (recipientPublicKey != null) 'recipientPublicKey': recipientPublicKey,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      // ignore: avoid_print
      print('[sendEmail] backend response status=${response.statusCode} body.len=${response.body.length}');

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
  String subject;
  String body;
  final List<EmailAttachment> attachments;
  final DateTime sentAt;
  final bool isRead;
  final String encryptionMethod;

  Email({
    required this.id,
    required this.senderEmail,
    required this.recipientEmail,
    required this.subject,
    required this.body,
    List<EmailAttachment>? attachments,
    required this.sentAt,
    required this.isRead,
    this.encryptionMethod = 'OTP',
  }) : attachments = attachments ?? const <EmailAttachment>[];

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    id: json['id'] as String,
    senderEmail: json['senderEmail'] as String,
    recipientEmail: json['recipientEmail'] as String,
    subject: json['subject'] as String,
    body: json['body'] as String,
    attachments: (json['attachments'] as List?)?.map((a) => EmailAttachment.fromJson(a as Map<String, dynamic>)).toList() ?? const <EmailAttachment>[],
    sentAt: DateTime.parse(json['sentAt'] as String),
    isRead: json['isRead'] as bool,
    encryptionMethod: json['encryptionMethod'] as String? ?? 'OTP',
  );
}

class EmailAttachment {
  final String fileName;
  final String contentType;
  final String contentBase64;

  EmailAttachment({required this.fileName, required this.contentType, required this.contentBase64});

  factory EmailAttachment.fromJson(Map<String, dynamic> json) => EmailAttachment(
    fileName: json['fileName'] as String,
    contentType: json['contentType'] as String,
    contentBase64: json['contentBase64'] as String,
  );
}

class SendAttachment {
  final String fileName;
  final String contentType;
  final String contentBase64;

  SendAttachment({required this.fileName, required this.contentType, required this.contentBase64});

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'contentType': contentType,
    'contentBase64': contentBase64,
  };
}
