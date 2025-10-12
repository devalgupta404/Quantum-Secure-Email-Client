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

  SentPqcEmail({
    required this.id,
    required this.subject,
    required this.body,
    required this.recipientEmail,
    required this.senderEmail,
    required this.sentAt,
  });

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'body': body,
      'recipientEmail': recipientEmail,
      'senderEmail': senderEmail,
      'sentAt': sentAt.toIso8601String(),
    };
  }

  /// Create from database Map
  factory SentPqcEmail.fromMap(Map<String, dynamic> map) {
    return SentPqcEmail(
      id: map['id'] as String,
      subject: map['subject'] as String,
      body: map['body'] as String,
      recipientEmail: map['recipientEmail'] as String,
      senderEmail: map['senderEmail'] as String,
      sentAt: DateTime.parse(map['sentAt'] as String),
    );
  }

  @override
  String toString() {
    return 'SentPqcEmail{id: $id, subject: $subject, recipientEmail: $recipientEmail, sentAt: $sentAt}';
  }
}
