/// Model for cached inbox emails stored locally
class CachedInboxEmail {
  final String id;
  final String subject;
  final String body;
  final String senderEmail;
  final String recipientEmail;
  final DateTime receivedAt;
  final String encryptionMethod;
  final String? attachments;
  final bool isDecrypted;
  final bool isCached;
  final DateTime cachedAt;
  final DateTime? lastAccessed;

  CachedInboxEmail({
    required this.id,
    required this.subject,
    required this.body,
    required this.senderEmail,
    required this.recipientEmail,
    required this.receivedAt,
    required this.encryptionMethod,
    this.attachments,
    this.isDecrypted = false,
    this.isCached = true,
    required this.cachedAt,
    this.lastAccessed,
  });

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'body': body,
      'senderEmail': senderEmail,
      'recipientEmail': recipientEmail,
      'receivedAt': receivedAt.toIso8601String(),
      'encryptionMethod': encryptionMethod,
      'attachments': attachments,
      'isDecrypted': isDecrypted ? 1 : 0,
      'isCached': isCached ? 1 : 0,
      'cachedAt': cachedAt.toIso8601String(),
      'lastAccessed': lastAccessed?.toIso8601String(),
    };
  }

  /// Create from Map (database retrieval)
  factory CachedInboxEmail.fromMap(Map<String, dynamic> map) {
    return CachedInboxEmail(
      id: map['id'] as String,
      subject: map['subject'] as String,
      body: map['body'] as String,
      senderEmail: map['senderEmail'] as String,
      recipientEmail: map['recipientEmail'] as String,
      receivedAt: DateTime.parse(map['receivedAt'] as String),
      encryptionMethod: map['encryptionMethod'] as String,
      attachments: map['attachments'] as String?,
      isDecrypted: (map['isDecrypted'] as int) == 1,
      isCached: (map['isCached'] as int? ?? 1) == 1,
      cachedAt: DateTime.parse(map['cachedAt'] as String),
      lastAccessed: map['lastAccessed'] != null 
          ? DateTime.parse(map['lastAccessed'] as String) 
          : null,
    );
  }

  /// Create a copy with updated fields
  CachedInboxEmail copyWith({
    String? id,
    String? subject,
    String? body,
    String? senderEmail,
    String? recipientEmail,
    DateTime? receivedAt,
    String? encryptionMethod,
    String? attachments,
    bool? isDecrypted,
    bool? isCached,
    DateTime? cachedAt,
    DateTime? lastAccessed,
  }) {
    return CachedInboxEmail(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      senderEmail: senderEmail ?? this.senderEmail,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      receivedAt: receivedAt ?? this.receivedAt,
      encryptionMethod: encryptionMethod ?? this.encryptionMethod,
      attachments: attachments ?? this.attachments,
      isDecrypted: isDecrypted ?? this.isDecrypted,
      isCached: isCached ?? this.isCached,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
    );
  }

  @override
  String toString() {
    return 'CachedInboxEmail(id: $id, subject: $subject, senderEmail: $senderEmail, isDecrypted: $isDecrypted)';
  }
}
