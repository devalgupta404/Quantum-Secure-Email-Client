namespace QuMail.EmailProtocol.Models;

/// <summary>
/// Represents a secure key exchange mechanism
/// </summary>
public class KeyExchange
{
    public string KeyId { get; set; } = string.Empty;
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public KeyExchangeStatus Status { get; set; }
    public string? PublicKey { get; set; }
}

public enum KeyExchangeStatus
{
    Pending,
    Accepted,
    Rejected,
    Expired
}

/// <summary>
/// Request to initiate key exchange between two parties
/// </summary>
public class KeyExchangeRequest
{
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public string SenderPublicKey { get; set; } = string.Empty;
    public string? Message { get; set; }
}

/// <summary>
/// Response to a key exchange request
/// </summary>
public class KeyExchangeResponse
{
    public string KeyId { get; set; } = string.Empty;
    public string RecipientPublicKey { get; set; } = string.Empty;
    public KeyExchangeStatus Status { get; set; }
    public string? Message { get; set; }
}

