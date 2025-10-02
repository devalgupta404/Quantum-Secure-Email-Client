using MimeKit;

namespace QuMail.EmailProtocol.Models;

public class EmailMessage
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string From { get; set; } = string.Empty;
    public List<string> To { get; set; } = new();
    public List<string> Cc { get; set; } = new();
    public List<string> Bcc { get; set; } = new();
    public string Subject { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public bool IsHtml { get; set; } = false;
    public List<EmailAttachment> Attachments { get; set; } = new();
    public DateTime SentDate { get; set; }
    public DateTime ReceivedDate { get; set; }
    
    // Quantum encryption metadata
    public string? KeyId { get; set; }
    public bool IsEncrypted { get; set; }
    public string? EncryptionVersion { get; set; } = "1.0";
    
    // Email protocol metadata
    public Dictionary<string, string> Headers { get; set; } = new();
    public string? MessageId { get; set; }
    public string? InReplyTo { get; set; }
    public List<string> References { get; set; } = new();
}

public class EmailAttachment
{
    public string FileName { get; set; } = string.Empty;
    public byte[] Content { get; set; } = Array.Empty<byte>();
    public string ContentType { get; set; } = "application/octet-stream";
    public bool IsEncrypted { get; set; }
    public string? KeyId { get; set; }
}

public class EncryptedEmailContent
{
    public string KeyId { get; set; } = string.Empty;
    public string EncryptedBody { get; set; } = string.Empty;
    public List<EncryptedAttachment> EncryptedAttachments { get; set; } = new();
    public string EncryptionVersion { get; set; } = "1.0";
    public DateTime EncryptedAt { get; set; }
}

public class EncryptedAttachment
{
    public string FileName { get; set; } = string.Empty;
    public string EncryptedContent { get; set; } = string.Empty;
    public string OriginalContentType { get; set; } = string.Empty;
}