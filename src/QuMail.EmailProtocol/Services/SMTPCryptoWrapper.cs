using System.Text;
using System.Text.Json;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Logging;
using MimeKit;
using MimeKit.Text;
using QuMail.EmailProtocol.Configuration;
using QuMail.EmailProtocol.Interfaces;
using QuMail.EmailProtocol.Models;

namespace QuMail.EmailProtocol.Services;

public class SMTPCryptoWrapper : IDisposable
{
    private readonly IOneTimePadEngine _cryptoEngine;
    private readonly IQuantumKeyManager _keyManager;
    private readonly ILogger<SMTPCryptoWrapper> _logger;
    private readonly EmailProviderSettings _providerSettings;
    private SmtpClient? _smtpClient;
    
    public SMTPCryptoWrapper(
        IOneTimePadEngine cryptoEngine,
        IQuantumKeyManager keyManager,
        ILogger<SMTPCryptoWrapper> logger,
        EmailProviderSettings? providerSettings = null)
    {
        _cryptoEngine = cryptoEngine ?? throw new ArgumentNullException(nameof(cryptoEngine));
        _keyManager = keyManager ?? throw new ArgumentNullException(nameof(keyManager));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _providerSettings = providerSettings ?? new EmailProviderSettings 
        { 
            Providers = EmailProviderDefaults.DefaultProviders 
        };
    }
    
    public async Task<bool> SendEncryptedEmailAsync(
        EmailMessage message, 
        EmailAccountCredentials credentials,
        CancellationToken cancellationToken = default)
    {
        try
        {
            _logger.LogInformation("Preparing to send encrypted email to {Recipients}", 
                string.Join(", ", message.To));
            
            // Generate key ID for this email
            var keyId = GenerateKeyId(message);
            
            // Encrypt the email content
            var encryptedContent = await EncryptEmailContentAsync(message, keyId);
            
            // Create MIME message
            var mimeMessage = await CreateMimeMessageAsync(message, encryptedContent, credentials.Email);
            
            // Send via SMTP
            await SendViaSmtpAsync(mimeMessage, credentials, cancellationToken);
            
            _logger.LogInformation("Successfully sent encrypted email with KeyId: {KeyId}", keyId);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send encrypted email");
            throw;
        }
    }
    
    private async Task<EncryptedEmailContent> EncryptEmailContentAsync(EmailMessage message, string keyId)
    {
        // Calculate required key size
        var bodyBytes = Encoding.UTF8.GetBytes(message.Body);
        var totalKeySize = bodyBytes.Length;
        
        foreach (var attachment in message.Attachments)
        {
            totalKeySize += attachment.Content.Length;
        }
        
        // Get quantum key
        var quantumKey = await _keyManager.GetKeyAsync(keyId, totalKeySize);
        
        // Encrypt body
        var encryptedBody = _cryptoEngine.Encrypt(bodyBytes, quantumKey.Data.Take(bodyBytes.Length).ToArray(), keyId);
        
        // Encrypt attachments
        var encryptedAttachments = new List<EncryptedAttachment>();
        var keyOffset = bodyBytes.Length;
        
        foreach (var attachment in message.Attachments)
        {
            var attachmentKey = quantumKey.Data.Skip(keyOffset).Take(attachment.Content.Length).ToArray();
            var encryptedAttachment = _cryptoEngine.Encrypt(attachment.Content, attachmentKey, keyId);
            
            encryptedAttachments.Add(new EncryptedAttachment
            {
                FileName = attachment.FileName,
                EncryptedContent = Convert.ToBase64String(encryptedAttachment.EncryptedData),
                OriginalContentType = attachment.ContentType
            });
            
            keyOffset += attachment.Content.Length;
        }
        
        // Mark key as used
        await _keyManager.MarkKeyAsUsedAsync(keyId, totalKeySize);
        
        return new EncryptedEmailContent
        {
            KeyId = keyId,
            EncryptedBody = Convert.ToBase64String(encryptedBody.EncryptedData),
            EncryptedAttachments = encryptedAttachments,
            EncryptionVersion = "1.0",
            EncryptedAt = DateTime.UtcNow
        };
    }
    
    private async Task<MimeMessage> CreateMimeMessageAsync(
        EmailMessage message, 
        EncryptedEmailContent encryptedContent,
        string fromEmail)
    {
        var mimeMessage = new MimeMessage();
        
        // Set from
        mimeMessage.From.Add(new MailboxAddress(fromEmail, fromEmail));
        
        // Set recipients
        foreach (var to in message.To)
        {
            mimeMessage.To.Add(new MailboxAddress(to, to));
        }
        
        foreach (var cc in message.Cc)
        {
            mimeMessage.Cc.Add(new MailboxAddress(cc, cc));
        }
        
        foreach (var bcc in message.Bcc)
        {
            mimeMessage.Bcc.Add(new MailboxAddress(bcc, bcc));
        }
        
        // Set subject
        mimeMessage.Subject = message.Subject;
        
        // Add custom headers for quantum encryption
        mimeMessage.Headers.Add("X-QuMail-Encrypted", "true");
        mimeMessage.Headers.Add("X-QuMail-KeyId", encryptedContent.KeyId);
        mimeMessage.Headers.Add("X-QuMail-Version", encryptedContent.EncryptionVersion);
        
        // Create multipart message
        var multipart = new Multipart("mixed");
        
        // Add encrypted body
        var bodyPart = new TextPart(TextFormat.Plain)
        {
            Text = FormatEncryptedBody(encryptedContent)
        };
        multipart.Add(bodyPart);
        
        // Add encrypted attachments
        foreach (var encAttachment in encryptedContent.EncryptedAttachments)
        {
            var attachment = new MimePart("application", "octet-stream")
            {
                Content = new MimeContent(
                    new MemoryStream(Convert.FromBase64String(encAttachment.EncryptedContent))),
                ContentDisposition = new ContentDisposition(ContentDisposition.Attachment),
                ContentTransferEncoding = ContentEncoding.Base64,
                FileName = $"{encAttachment.FileName}.qenc"
            };
            
            attachment.Headers.Add("X-QuMail-Original-Type", encAttachment.OriginalContentType);
            multipart.Add(attachment);
        }
        
        mimeMessage.Body = multipart;
        
        return mimeMessage;
    }
    
    private string FormatEncryptedBody(EncryptedEmailContent content)
    {
        // Format the encrypted content for non-quantum email clients
        var sb = new StringBuilder();
        sb.AppendLine("=== QuMail Quantum-Encrypted Email ===");
        sb.AppendLine();
        sb.AppendLine("This email has been encrypted using quantum one-time pad encryption.");
        sb.AppendLine("To decrypt this message, you need QuMail client with the corresponding quantum key.");
        sb.AppendLine();
        sb.AppendLine($"Key ID: {content.KeyId}");
        sb.AppendLine($"Encrypted At: {content.EncryptedAt:yyyy-MM-dd HH:mm:ss} UTC");
        sb.AppendLine($"Version: {content.EncryptionVersion}");
        sb.AppendLine();
        sb.AppendLine("=== Encrypted Content ===");
        sb.AppendLine(content.EncryptedBody);
        sb.AppendLine("=== End Encrypted Content ===");
        
        return sb.ToString();
    }
    
    private async Task SendViaSmtpAsync(
        MimeMessage message, 
        EmailAccountCredentials credentials,
        CancellationToken cancellationToken)
    {
        // Get provider settings
        if (!_providerSettings.Providers.TryGetValue(credentials.Provider, out var provider))
        {
            throw new InvalidOperationException($"Unknown email provider: {credentials.Provider}");
        }
        
        using var client = new SmtpClient();
        
        try
        {
            // Connect to SMTP server
            await client.ConnectAsync(
                provider.Smtp.Host, 
                provider.Smtp.Port, 
                provider.Smtp.EnableSsl ? SecureSocketOptions.StartTls : SecureSocketOptions.None,
                cancellationToken);
            
            // Authenticate
            if (provider.Smtp.AuthType == AuthenticationType.OAuth2 && !string.IsNullOrEmpty(credentials.OAuth2Token))
            {
                var oauth2 = new SaslMechanismOAuth2(credentials.Email, credentials.OAuth2Token);
                await client.AuthenticateAsync(oauth2, cancellationToken);
            }
            else
            {
                await client.AuthenticateAsync(credentials.Email, credentials.Password, cancellationToken);
            }
            
            // Send message
            var response = await client.SendAsync(message, cancellationToken);
            _logger.LogInformation("SMTP Response: {Response}", response);
            
            // Disconnect
            await client.DisconnectAsync(true, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SMTP operation failed");
            throw;
        }
    }
    
    private string GenerateKeyId(EmailMessage message)
    {
        // Generate a unique key ID based on message properties and timestamp
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var hash = System.Security.Cryptography.SHA256.HashData(
            Encoding.UTF8.GetBytes($"{message.From}{string.Join(",", message.To)}{timestamp}"));
        return $"QuMail-{Convert.ToBase64String(hash).Replace("/", "-").Replace("+", "_").Substring(0, 16)}";
    }
    
    public void Dispose()
    {
        _smtpClient?.Dispose();
    }
}