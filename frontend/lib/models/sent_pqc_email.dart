import 'dart:convert';

/// Model for locally stored sent PQC emails
/// These are stored in device-local SQLite database for privacy
/// Private keys never leave the device, so sent PQC emails need local storage
class SentPqcEmail {
  final String id; // Email ID from backend
  final String subject; // Plaintext subject
  final String body; // Plaintext body
  final String recipientEmail;
  final String senderEmail;
  final DateTime sentAt;
  final List<PqcAttachment> attachments; // Plaintext attachments

  SentPqcEmail({
    required this.id,
    required this.subject,
    required this.body,
    required this.recipientEmail,
    required this.senderEmail,
    required this.sentAt,
    List<PqcAttachment>? attachments,
  }) : attachments = attachments ?? [];

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'body': body,
      'recipientEmail': recipientEmail,
      'senderEmail': senderEmail,
      'sentAt': sentAt.toIso8601String(),
      'attachments': jsonEncode(attachments.map((a) => a.toMap()).toList()),
    };
  }

  /// Create from database Map
  factory SentPqcEmail.fromMap(Map<String, dynamic> map) {
    List<PqcAttachment> attachments = [];
    if (map.containsKey('attachments') && map['attachments'] != null) {
      try {
        final List<dynamic> attachmentsList = jsonDecode(map['attachments'] as String);
        attachments = attachmentsList.map((a) => PqcAttachment.fromMap(a as Map<String, dynamic>)).toList();
      } catch (e) {
        print('[SentPqcEmail] Error parsing attachments: $e');
      }
    }

    return SentPqcEmail(
      id: map['id'] as String,
      subject: map['subject'] as String,
      body: map['body'] as String,
      recipientEmail: map['recipientEmail'] as String,
      senderEmail: map['senderEmail'] as String,
      sentAt: DateTime.parse(map['sentAt'] as String),
      attachments: attachments,
    );
  }

  @override
  String toString() {
    return 'SentPqcEmail{id: $id, subject: $subject, recipientEmail: $recipientEmail, sentAt: $sentAt, attachments: ${attachments.length}}';
  }
}

/// Attachment model for PQC emails stored locally
class PqcAttachment {
  final String fileName;
  final String contentType;
  final String contentBase64; // Plaintext base64 data

  PqcAttachment({
    required this.fileName,
    required this.contentType,
    required this.contentBase64,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'contentType': contentType,
      'contentBase64': contentBase64,
    };
  }

  factory PqcAttachment.fromMap(Map<String, dynamic> map) {
    return PqcAttachment(
      fileName: map['fileName'] as String,
      contentType: map['contentType'] as String,
      contentBase64: map['contentBase64'] as String,
    );
  }
}
