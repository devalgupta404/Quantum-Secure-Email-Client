using Microsoft.AspNetCore.Mvc;
using QuMail.EmailProtocol.Data;
using QuMail.EmailProtocol.Models;
using Microsoft.EntityFrameworkCore;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Net.Http;
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using System.Net.Mail;
using System.Net;
using QuMail.EmailProtocol.Configuration;
using QuMail.EmailProtocol.Services;

namespace QuMail.EmailProtocol.Controllers;

[ApiController]
[Route("api/[controller]")]
public class EmailController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly ILogger<EmailController> _logger;
    private readonly Level3KyberPQC _kyberPQC;
    private readonly Level3PQCEmailService _pqcEmailService;
    private readonly Level3EnhancedPQC _enhancedPQC;
    private readonly Level3HybridEncryption _hybridEncryption;
    private static readonly HttpClient _http = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(30)
    };
    private const string OtpBaseUrl = "http://otp-server:2021";
    private const string AesBaseUrl = "http://aes-server:2022";
    private const int MaxRetries = 3;

    public EmailController(
        AuthDbContext context, 
        ILogger<EmailController> logger,
        Level3KyberPQC kyberPQC,
        Level3PQCEmailService pqcEmailService,
        Level3EnhancedPQC enhancedPQC,
        Level3HybridEncryption hybridEncryption)
    {
        _context = context;
        _logger = logger;
        _kyberPQC = kyberPQC;
        _pqcEmailService = pqcEmailService;
        _enhancedPQC = enhancedPQC;
        _hybridEncryption = hybridEncryption;
    }

    [HttpGet("pqc/public-key/{email}")]
    public async Task<IActionResult> GetPqcPublicKey(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return BadRequest(new { success = false, message = "Email is required" });
        }

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email || u.ExternalEmail == email);
        if (user == null)
        {
            return NotFound(new { success = false, message = "User not found" });
        }

        if (string.IsNullOrWhiteSpace(user.PqcPublicKey))
        {
            return NotFound(new { success = false, message = "PQC public key not available for this user" });
        }

        return Ok(new { success = true, data = new { publicKey = user.PqcPublicKey } });
    }

    public class RegisterPqcKeyRequest
    {
        public string Email { get; set; } = string.Empty;
        public string PublicKey { get; set; } = string.Empty;
    }

    [HttpPost("pqc/public-key")]
    public async Task<IActionResult> RegisterPqcPublicKey([FromBody] RegisterPqcKeyRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.PublicKey))
        {
            return BadRequest(new { success = false, message = "Email and publicKey are required" });
        }

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.Email || u.ExternalEmail == request.Email);
        if (user == null)
        {
            return NotFound(new { success = false, message = "User not found" });
        }

        user.PqcPublicKey = request.PublicKey;
        user.PqcKeyGeneratedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return Ok(new { success = true });
    }

    [HttpPost("send-pqc2-encrypted")]
    public async Task<IActionResult> SendPqc2EncryptedEmail([FromBody] SendPqcEncryptedRequest request)
    {
        try
        {
            _logger.LogInformation("Sending PQC_2_LAYER email from {Sender} to {Recipient}", request.SenderEmail, request.RecipientEmail);

            var recipient = await _context.Users.FirstOrDefaultAsync(u =>
                u.Email == request.RecipientEmail || u.ExternalEmail == request.RecipientEmail);
            if (recipient == null)
            {
                return BadRequest(new {
                    success = false,
                    message = "Recipient email not found in our system"
                });
            }

            if (string.IsNullOrWhiteSpace(recipient.PqcPublicKey))
            {
                return BadRequest(new {
                    success = false,
                    message = "Recipient does not have a PQC public key registered"
                });
            }

            _logger.LogInformation("Applying OTP encryption to PQC data");
            var finalSubject = await EncryptBodyAsync(request.PqcEncryptedSubject);
            var finalBody = await EncryptBodyAsync(request.PqcEncryptedBody);

            string? attachmentsJson = null;
            if (request.Attachments != null && request.Attachments.Count > 0)
            {
                _logger.LogInformation("Encrypting {Count} attachments with PQC 2-layer (PQC + OTP)", request.Attachments.Count);
                var encrypted = new List<object>(request.Attachments.Count);
                foreach (var a in request.Attachments)
                {
                    var pqcEnvelope = await EncryptSingleWithPQC2LayerAsync(a.ContentBase64, recipient.PqcPublicKey);

                    var finalEnvelope = await EncryptBodyAsync(pqcEnvelope);
                    encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope = finalEnvelope });
                }
                attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
            }

            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            var senderOriginal = !string.IsNullOrWhiteSpace(sender?.ExternalEmail) ?
                sender!.ExternalEmail! : request.SenderEmail;

            var email = new Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = senderOriginal,
                RecipientEmail = request.RecipientEmail,
                Subject = finalSubject,
                Body = finalBody,
                EncryptionMethod = "PQC_2_LAYER",
                Attachments = attachmentsJson,
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            _logger.LogInformation("PQC_2_LAYER email saved with ID: {EmailId}", email.Id);

            return Ok(new {
                success = true,
                message = "PQC_2_LAYER email sent successfully",
                emailId = email.Id,
                encryptionMethod = "PQC_2_LAYER"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send PQC_2_LAYER email");
            return BadRequest(new {
                success = false,
                message = $"Failed to send PQC_2_LAYER email: {ex.Message}",
                detail = ex.InnerException?.Message
            });
        }
    }

    [HttpPost("send-pqc-encrypted")]
    public async Task<IActionResult> SendPqcEncryptedEmail([FromBody] SendPqcEncryptedRequest request)
    {
        try
        {
            _logger.LogInformation("Sending PQC-encrypted email from {Sender} to {Recipient}", request.SenderEmail, request.RecipientEmail);

            var recipient = await _context.Users.FirstOrDefaultAsync(u =>
                u.Email == request.RecipientEmail || u.ExternalEmail == request.RecipientEmail);
            if (recipient == null)
            {
                return BadRequest(new {
                    success = false,
                    message = "Recipient email not found in our system"
                });
            }

            if (string.IsNullOrWhiteSpace(recipient.PqcPublicKey))
            {
                return BadRequest(new {
                    success = false,
                    message = "Recipient does not have a PQC public key registered"
                });
            }

            _logger.LogInformation("Applying AES encryption to PQC data");
            
            var pqcSubjectForAES = PreparePqcEnvelopeForAES(request.PqcEncryptedSubject);
            var pqcBodyForAES = PreparePqcEnvelopeForAES(request.PqcEncryptedBody);
            
            var aesSubject = await EncryptWithAESGCMAsync(pqcSubjectForAES);
            var aesBody = await EncryptWithAESGCMAsync(pqcBodyForAES);

            _logger.LogInformation("Applying OTP encryption to AES data");
            var finalSubject = await EncryptBodyAsync(aesSubject);
            var finalBody = await EncryptBodyAsync(aesBody);

            string? attachmentsJson = null;
            if (request.Attachments != null && request.Attachments.Count > 0)
            {
                _logger.LogInformation("Encrypting {Count} attachments with PQC 3-layer (PQC + AES + OTP)", request.Attachments.Count);
                var encrypted = new List<object>(request.Attachments.Count);
                foreach (var a in request.Attachments)
                {
                    var pqcEnvelope = await EncryptSingleWithPQC3LayerAsync(a.ContentBase64, recipient.PqcPublicKey);

                    var pqcEnvelopeForAES = pqcEnvelope;

                    var aesEnvelope = await EncryptWithAESGCMAsync(pqcEnvelopeForAES);

                    var finalEnvelope = await EncryptBodyAsync(aesEnvelope);
                    encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope = finalEnvelope });
                }
                attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
            }

            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            var senderOriginal = !string.IsNullOrWhiteSpace(sender?.ExternalEmail) ?
                sender!.ExternalEmail! : request.SenderEmail;

            var email = new Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = senderOriginal,
                RecipientEmail = request.RecipientEmail,
                Subject = finalSubject,
                Body = finalBody,
                EncryptionMethod = "PQC_3_LAYER",
                Attachments = attachmentsJson,
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            _logger.LogInformation("PQC email saved with ID: {EmailId}", email.Id);

            return Ok(new {
                success = true,
                message = "PQC email sent successfully",
                emailId = email.Id,
                encryptionMethod = "PQC_3_LAYER"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send PQC-encrypted email");
            return BadRequest(new {
                success = false,
                message = $"Failed to send PQC email: {ex.Message}",
                detail = ex.InnerException?.Message
            });
        }
    }

    [HttpPost("send")]
    public async Task<IActionResult> SendEmail([FromBody] SendEmailRequest request)
    {
        try
        {
            _logger.LogInformation($"Starting email send with encryption method: {request.EncryptionMethod}");
            
            var recipient = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.RecipientEmail || u.ExternalEmail == request.RecipientEmail);
            if (recipient == null)
            {
                return BadRequest(new { 
                    success = false, 
                    message = "Recipient email not found in our system" 
                });
            }

            if (request.EncryptionMethod.StartsWith("PQC") && string.IsNullOrEmpty(request.RecipientPublicKey))
            {
                return BadRequest(new { 
                    success = false, 
                    message = "RecipientPublicKey is required for PQC encryption methods" 
                });
            }

            string subjectEnvelope, bodyEnvelope;
            string? attachmentsJson = null;

            _logger.LogInformation("SendEmail: method={Method} subj.len={SL} body.len={BL}", request.EncryptionMethod, (request.Subject ?? string.Empty).Length, (request.Body ?? string.Empty).Length);
            bool isAlreadyEncrypted = IsAlreadyEncrypted(request.Subject, request.EncryptionMethod) || IsAlreadyEncrypted(request.Body, request.EncryptionMethod);
            _logger.LogInformation("SendEmail: isAlreadyEncrypted={IsEnc}", isAlreadyEncrypted);
            
            if (isAlreadyEncrypted)
            {
                _logger.LogInformation("Data is already encrypted from frontend, using as-is (storing raw envelopes)");
                subjectEnvelope = request.Subject ?? string.Empty;
                bodyEnvelope = request.Body ?? string.Empty;
                attachmentsJson = request.Attachments != null ? JsonSerializer.Serialize(request.Attachments) : null;
            }
            else
            {
                switch (request.EncryptionMethod.ToUpper())
                {
                    case "OTP":
                        _logger.LogInformation("Using OTP encryption");
                        subjectEnvelope = await EncryptBodyAsync(request.Subject);
                        bodyEnvelope = await EncryptBodyAsync(request.Body);
                        attachmentsJson = await EncryptAttachmentsOTPAsync(request.Attachments);
                        break;

                    case "AES":
                        _logger.LogInformation("Using AES-GCM encryption");
                        var aesResult = await EncryptWithAESAsync(request.Subject, request.Body, request.Attachments);
                        subjectEnvelope = aesResult.SubjectEnvelope;
                        bodyEnvelope = aesResult.BodyEnvelope;
                        attachmentsJson = aesResult.AttachmentsJson;
                        break;

                    case "PQC_2_LAYER":
                        _logger.LogInformation("Using PQC 2-layer encryption");
                        var pqc2Result = await EncryptWithPQC2LayerAsync(request.Subject, request.Body, request.RecipientPublicKey, request.Attachments);
                        subjectEnvelope = pqc2Result.SubjectEnvelope;
                        bodyEnvelope = pqc2Result.BodyEnvelope;
                        attachmentsJson = pqc2Result.AttachmentsJson;
                        break;

                    case "PQC_3_LAYER":
                        _logger.LogInformation("Using PQC 3-layer encryption");
                        var pqc3Result = await EncryptWithPQC3LayerAsync(request.Subject, request.Body, request.RecipientPublicKey, request.Attachments);
                        subjectEnvelope = pqc3Result.SubjectEnvelope;
                        bodyEnvelope = pqc3Result.BodyEnvelope;
                        attachmentsJson = pqc3Result.AttachmentsJson;
                        break;

                    default:
                        return BadRequest(new { 
                            success = false, 
                            message = $"Unsupported encryption method: {request.EncryptionMethod}. Supported: OTP, AES, PQC_2_LAYER, PQC_3_LAYER" 
                        });
                }
            }

            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            var senderOriginal = !string.IsNullOrWhiteSpace(sender?.ExternalEmail) ? sender!.ExternalEmail! : request.SenderEmail;

            var email = new Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = senderOriginal,
                RecipientEmail = request.RecipientEmail,
                Subject = subjectEnvelope,
                Body = bodyEnvelope,
                EncryptionMethod = request.EncryptionMethod,
                Attachments = attachmentsJson,
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            _logger.LogInformation($"Email saved to database with ID: {email.Id}");

            await TrySendExternallyAsync(request, recipient, subjectEnvelope, bodyEnvelope);

            return Ok(new { 
                success = true, 
                message = $"Email sent successfully using {request.EncryptionMethod} encryption",
                emailId = email.Id,
                encryptionMethod = request.EncryptionMethod
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Failed to send email with method {request.EncryptionMethod}: {ex.Message}");
            return BadRequest(new { 
                success = false, 
                message = $"Failed to send email: {ex.Message}",
                innerException = ex.InnerException?.Message,
                stackTrace = ex.StackTrace
            });
        }
    }

    [HttpGet("inbox/{userEmail}")]
    public async Task<IActionResult> GetInbox(string userEmail)
    {
        try
        {
            var emailEntities = await _context.Emails
                .Where(e => e.RecipientEmail == userEmail)
                .OrderByDescending(e => e.SentAt)
                .ToListAsync();

            var emails = new List<object>(emailEntities.Count);
            foreach (var e in emailEntities)
            {
                if (e.EncryptionMethod == "PQC_2_LAYER" || e.EncryptionMethod == "PQC_3_LAYER")
                {
                    _logger.LogInformation("PQC email detected - returning encrypted data (frontend will decrypt via separate endpoint)");
                    emails.Add(new
                    {
                        e.Id,
                        e.SenderEmail,
                        e.RecipientEmail,
                        Subject = e.Subject,
                        Body = e.Body,
                        attachments = new object[] { },
                        e.SentAt,
                        e.IsRead,
                        e.EncryptionMethod
                    });
                }
                else
                {
                    var decryptedBody = await TryDecryptBodyAsync(e.Body);
                    var decryptedSubject = await TryDecryptBodyAsync(e.Subject);
                    var attachments = await TryDecryptAttachmentsAsync(e.Attachments);
                    emails.Add(new
                    {
                        e.Id,
                        e.SenderEmail,
                        e.RecipientEmail,
                        Subject = decryptedSubject,
                        Body = decryptedBody,
                        attachments = attachments,
                        e.SentAt,
                        e.IsRead,
                        e.EncryptionMethod
                    });
                }
            }

            return Ok(new {
                success = true,
                emails = emails
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new {
                success = false,
                message = $"Failed to get inbox: {ex.Message}"
            });
        }
    }

    [HttpGet("sent/{userEmail}")]
    public async Task<IActionResult> GetSentEmails(string userEmail)
    {
        try
        {
            _logger.LogInformation("===== BACKEND: FETCHING SENT EMAILS =====");
            _logger.LogInformation("User email: {UserEmail}", userEmail);

            var emailEntities = await _context.Emails
                .Where(e => e.SenderEmail == userEmail)
                .OrderByDescending(e => e.SentAt)
                .ToListAsync();

            _logger.LogInformation("Found {Count} emails in database", emailEntities.Count);

            var emails = new List<object>(emailEntities.Count);
            for (int i = 0; i < emailEntities.Count; i++)
            {
                var e = emailEntities[i];
                _logger.LogInformation("----- Processing email {Index} -----", i);
                _logger.LogInformation("Email ID: {Id}", e.Id);
                _logger.LogInformation("Encryption method: {Method}", e.EncryptionMethod);
                _logger.LogInformation("Subject length: {Length}", e.Subject?.Length ?? 0);
                _logger.LogInformation("Body length: {Length}", e.Body?.Length ?? 0);

                if (e.EncryptionMethod == "PQC_2_LAYER" || e.EncryptionMethod == "PQC_3_LAYER")
                {
                    _logger.LogInformation("PQC email detected - returning encrypted data (frontend will load from local DB)");
                    emails.Add(new
                    {
                        e.Id,
                        e.SenderEmail,
                        e.RecipientEmail,
                        Subject = e.Subject,
                        Body = e.Body,
                        attachments = new object[] { },
                        e.SentAt,
                        e.IsRead,
                        e.EncryptionMethod
                    });
                }
                else
                {
                    _logger.LogInformation("Non-PQC email - decrypting on backend");
                    var decryptedBody = await TryDecryptBodyAsync(e.Body);
                    var decryptedSubject = await TryDecryptBodyAsync(e.Subject);
                    var attachments = await TryDecryptAttachmentsAsync(e.Attachments);

                    emails.Add(new
                    {
                        e.Id,
                        e.SenderEmail,
                        e.RecipientEmail,
                        Subject = decryptedSubject,
                        Body = decryptedBody,
                        attachments = attachments,
                        e.SentAt,
                        e.IsRead,
                        e.EncryptionMethod
                    });
                }
            }

            _logger.LogInformation("===== BACKEND: SENT EMAILS RESPONSE READY: {Count} emails =====", emails.Count);

            return Ok(new {
                success = true,
                emails = emails
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get sent emails");
            return BadRequest(new {
                success = false,
                message = $"Failed to get sent emails: {ex.Message}"
            });
        }
    }

    [HttpPost("mark-read/{emailId}")]
    public async Task<IActionResult> MarkAsRead(Guid emailId)
    {
        try
        {
            var email = await _context.Emails.FindAsync(emailId);
            if (email == null)
            {
                return NotFound(new {
                    success = false,
                    message = "Email not found"
                });
            }

            email.IsRead = true;
            await _context.SaveChangesAsync();

            return Ok(new {
                success = true,
                message = "Email marked as read"
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new {
                success = false,
                message = $"Failed to mark email as read: {ex.Message}"
            });
        }
    }

    [HttpGet("decrypt-to-pqc2/{emailId}")]
    public async Task<IActionResult> DecryptToPqc2(Guid emailId)
    {
        try
        {
            _logger.LogInformation("Decrypting PQC_2_LAYER email {EmailId} to PQC layer", emailId);

            var email = await _context.Emails.FindAsync(emailId);
            if (email == null)
            {
                return NotFound(new {
                    success = false,
                    message = "Email not found"
                });
            }

            if (email.EncryptionMethod != "PQC_2_LAYER")
            {
                return BadRequest(new {
                    success = false,
                    message = $"This endpoint only supports PQC_2_LAYER emails. Email encryption method: {email.EncryptionMethod}"
                });
            }

            _logger.LogInformation("Decrypting OTP layer for subject and body");
            string pqcSubject, pqcBody;

            if (TryParseEnvelope(email.Subject, out var otpSubjectEnvelope))
            {
                pqcSubject = await DecryptOTPAsync(otpSubjectEnvelope);
                if (pqcSubject == "OTP decryption failed" || pqcSubject == "Decryption failed")
                {
                    _logger.LogError("OTP decryption failed for subject");
                    return BadRequest(new {
                        success = false,
                        message = "Failed to decrypt email: OTP decryption failed for subject",
                        detail = "The OTP service may be unavailable or the encryption key may have expired"
                    });
                }
            }
            else
            {
                _logger.LogWarning("Failed to parse OTP envelope for subject");
                pqcSubject = email.Subject;
            }

            if (TryParseEnvelope(email.Body, out var otpBodyEnvelope))
            {
                pqcBody = await DecryptOTPAsync(otpBodyEnvelope);
                if (pqcBody == "OTP decryption failed" || pqcBody == "Decryption failed")
                {
                    _logger.LogError("OTP decryption failed for body");
                    return BadRequest(new {
                        success = false,
                        message = "Failed to decrypt email: OTP decryption failed for body",
                        detail = "The OTP service may be unavailable or the encryption key may have expired"
                    });
                }
            }
            else
            {
                _logger.LogWarning("Failed to parse OTP envelope for body");
                pqcBody = email.Body;
            }
            _logger.LogInformation("Decrypting attachments for PQC_2_LAYER email");
            string? pqcAttachmentsJson = null;
            if (!string.IsNullOrWhiteSpace(email.Attachments))
            {
                try
                {
                    var attachmentsList = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(email.Attachments, _jsonOptions);
                    if (attachmentsList != null && attachmentsList.Count > 0)
                    {
                        var decryptedAttachments = new List<object>();
                        foreach (var item in attachmentsList)
                        {
                            var fileName = item.ContainsKey("fileName") ? item["fileName"]?.ToString() : null;
                            var contentType = item.ContainsKey("contentType") ? item["contentType"]?.ToString() : null;
                            var envelope = item.ContainsKey("envelope") ? item["envelope"]?.ToString() : null;

                            if (!string.IsNullOrWhiteSpace(fileName) && !string.IsNullOrWhiteSpace(envelope))
                            {
                                if (TryParseEnvelope(envelope, out var otpEnvelope))
                                {
                                    var pqcEnvelope = await DecryptOTPAsync(otpEnvelope);
                                    decryptedAttachments.Add(new { fileName, contentType, pqcEnvelope });
                                }
                            }
                        }
                        pqcAttachmentsJson = JsonSerializer.Serialize(decryptedAttachments, _jsonOptions);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to decrypt attachments for PQC_2_LAYER email");
                }
            }
            _logger.LogInformation("Returning PQC-encrypted data to frontend for client-side decryption");

            return Ok(new {
                success = true,
                email = new {
                    id = email.Id,
                    senderEmail = email.SenderEmail,
                    recipientEmail = email.RecipientEmail,
                    pqcEncryptedSubject = pqcSubject,
                    pqcEncryptedBody = pqcBody,        
                    pqcAttachmentsJson = pqcAttachmentsJson,  
                    sentAt = email.SentAt,
                    isRead = email.IsRead,
                    encryptionMethod = email.EncryptionMethod,
                    requiresPqcDecryption = true       
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt PQC_2_LAYER email {EmailId} to PQC layer", emailId);
            return BadRequest(new {
                success = false,
                message = $"Failed to decrypt email: {ex.Message}",
                detail = ex.InnerException?.Message
            });
        }
    }

    [HttpGet("decrypt-to-pqc/{emailId}")]
    public async Task<IActionResult> DecryptToPqc(Guid emailId)
    {
        try
        {
            _logger.LogInformation("Decrypting email {EmailId} to PQC layer", emailId);

            var email = await _context.Emails.FindAsync(emailId);
            if (email == null)
            {
                return NotFound(new {
                    success = false,
                    message = "Email not found"
                });
            }

            if (email.EncryptionMethod != "PQC_3_LAYER")
            {
                return BadRequest(new {
                    success = false,
                    message = $"This endpoint only supports PQC_3_LAYER emails. Email encryption method: {email.EncryptionMethod}"
                });
            }
            _logger.LogInformation("Decrypting OTP layer for subject and body");
            string aesSubject, aesBody;
            bool subjectDecryptionFailed = false;
            bool bodyDecryptionFailed = false;

            if (TryParseEnvelope(email.Subject, out var otpSubjectEnvelope))
            {
                aesSubject = await DecryptOTPAsync(otpSubjectEnvelope);
                if (aesSubject == "OTP decryption failed" || aesSubject == "Decryption failed")
                {
                    _logger.LogWarning("OTP decryption failed for subject, using fallback message");
                    aesSubject = "[Decryption Failed - OTP key may have expired]";
                    subjectDecryptionFailed = true;
                }
            }
            else
            {
                _logger.LogWarning("Failed to parse OTP envelope for subject");
                aesSubject = email.Subject;
            }

            if (TryParseEnvelope(email.Body, out var otpBodyEnvelope))
            {
                aesBody = await DecryptOTPAsync(otpBodyEnvelope);
                if (aesBody == "OTP decryption failed" || aesBody == "Decryption failed")
                {
                    _logger.LogWarning("OTP decryption failed for body, using fallback message");
                    aesBody = "[Decryption Failed - OTP key may have expired. The encryption key for this message is no longer available.]";
                    bodyDecryptionFailed = true;
                }
            }
            else
            {
                _logger.LogWarning("Failed to parse OTP envelope for body");
                aesBody = email.Body;
            _logger.LogInformation("Decrypting AES layer for subject and body");
            string pqcSubject, pqcBody;

            if (!subjectDecryptionFailed && TryParseAESEnvelope(aesSubject, out var aesSubjectEnvelope))
            {
                try
                {
                    var aesSubjectResult = await DecryptAESAsync(aesSubjectEnvelope);
                    pqcSubject = RestorePqcEnvelopeFromAES(aesSubjectResult);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "AES decryption or envelope restoration failed for subject, using fallback message");
                    pqcSubject = "[Decryption Failed - AES decryption error]";
                    subjectDecryptionFailed = true;
                }
            }
            else
            {
                if (!subjectDecryptionFailed)
                {
                    _logger.LogWarning("Failed to parse AES envelope for subject");
                }
                pqcSubject = aesSubject;
            }

            if (!bodyDecryptionFailed && TryParseAESEnvelope(aesBody, out var aesBodyEnvelope))
            {
                try
                {
                    var aesBodyResult = await DecryptAESAsync(aesBodyEnvelope);
                    pqcBody = RestorePqcEnvelopeFromAES(aesBodyResult);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "AES decryption or envelope restoration failed for body, using fallback message");
                    pqcBody = "[Decryption Failed - AES decryption error. The encryption key for this message is no longer available.]";
                    bodyDecryptionFailed = true;
                }
            }
            else
            {
                if (!bodyDecryptionFailed)
                {
                    _logger.LogWarning("Failed to parse AES envelope for body");
                }
                pqcBody = aesBody;
            }
            _logger.LogInformation("Decrypting attachments for PQC_3_LAYER email");
            string? pqcAttachmentsJson = null;
            if (!string.IsNullOrWhiteSpace(email.Attachments))
            {
                try
                {
                    var attachmentsList = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(email.Attachments, _jsonOptions);
                    if (attachmentsList != null && attachmentsList.Count > 0)
                    {
                        var decryptedAttachments = new List<object>();
                        for (int idx = 0; idx < attachmentsList.Count; idx++)
                        {
                            try
                            {
                                var item = attachmentsList[idx];
                                var fileName = item.ContainsKey("fileName") ? item["fileName"]?.ToString() : null;
                                var contentType = item.ContainsKey("contentType") ? item["contentType"]?.ToString() : null;
                                var envelope = item.ContainsKey("envelope") ? item["envelope"]?.ToString() : null;

                                if (!string.IsNullOrWhiteSpace(fileName) && !string.IsNullOrWhiteSpace(envelope))
                                {
                                    _logger.LogInformation("Processing attachment {Index}: {FileName}", idx, fileName);

                                    if (TryParseEnvelope(envelope, out var otpEnvelope))
                                    {
                                        var aesEnvelope = await DecryptOTPAsync(otpEnvelope);

                                        if (aesEnvelope == "OTP decryption failed" || aesEnvelope == "Decryption failed")
                                        {
                                            _logger.LogWarning("OTP decryption failed for attachment {Index}: {FileName}, skipping", idx, fileName);
                                            continue;
                                        }
                                        if (TryParseAESEnvelope(aesEnvelope, out var aesEnvelopeObj))
                                        {
                                            var aesDecryptedResult = await DecryptAESAsync(aesEnvelopeObj);
                                            var pqcEnvelope = aesDecryptedResult;

                                            decryptedAttachments.Add(new { fileName, contentType, pqcEnvelope });
                                            _logger.LogInformation("Successfully decrypted attachment {Index}: {FileName}", idx, fileName);
                                        }
                                        else
                                        {
                                            _logger.LogWarning("Failed to parse AES envelope for attachment {Index}: {FileName}", idx, fileName);
                                        }
                                    }
                                    else
                                    {
                                        _logger.LogWarning("Failed to parse OTP envelope for attachment {Index}: {FileName}", idx, fileName);
                                    }
                                }
                            }
                            catch (Exception attEx)
                            {
                                _logger.LogError(attEx, "Failed to decrypt individual attachment {Index}, continuing with others", idx);
                            }
                        }
                        pqcAttachmentsJson = JsonSerializer.Serialize(decryptedAttachments, _jsonOptions);
                        _logger.LogInformation("Successfully decrypted {Count} out of {Total} attachments", decryptedAttachments.Count, attachmentsList.Count);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to decrypt attachments for PQC_3_LAYER email");
                }
            }
            _logger.LogInformation("Returning PQC-encrypted data to frontend for client-side decryption");

            return Ok(new {
                success = true,
                email = new {
                    id = email.Id,
                    senderEmail = email.SenderEmail,
                    recipientEmail = email.RecipientEmail,
                    pqcEncryptedSubject = pqcSubject,  
                    pqcEncryptedBody = pqcBody,        
                    pqcAttachmentsJson = pqcAttachmentsJson, 
                    sentAt = email.SentAt,
                    isRead = email.IsRead,
                    encryptionMethod = email.EncryptionMethod,
                    requiresPqcDecryption = true
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt email {EmailId} to PQC layer", emailId);
            return BadRequest(new {
                success = false,
                message = $"Failed to decrypt email: {ex.Message}",
                detail = ex.InnerException?.Message
            });
        }
    }

    private static readonly JsonSerializerOptions _jsonOptions = new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private sealed record OtpEncryptRequest(string text);
    private sealed record OtpEncryptResponse(string key_id, string ciphertext_b64url);
    private sealed record OtpDecryptRequest(string key_id, string ciphertext_b64url);
    private sealed record OtpDecryptResponse(string? plaintext_b64url, string? text);

    private sealed record BodyEnvelope(string otp_key_id, string ciphertext_b64url);

    private bool TryParseEnvelope(string body, out BodyEnvelope envelope)
    {
        envelope = default!;
        if (string.IsNullOrWhiteSpace(body) || body.Length < 10) 
        {
            _logger.LogInformation("TryParseEnvelope: Body is empty or too short");
            return false;
        }
        try
        {
            _logger.LogInformation($"TryParseEnvelope: Attempting to parse body: {body}");
            
            var parsed = JsonSerializer.Deserialize<BodyEnvelope>(body, _jsonOptions);
            if (parsed == null)
            {
                _logger.LogInformation("TryParseEnvelope: Parsed result is null");
                return false;
            }
            
            _logger.LogInformation($"TryParseEnvelope: Parsed - otp_key_id: {parsed.otp_key_id}, ciphertext_b64url: {parsed.ciphertext_b64url}");
            
            if (string.IsNullOrWhiteSpace(parsed.otp_key_id) || string.IsNullOrWhiteSpace(parsed.ciphertext_b64url))
            {
                _logger.LogInformation("TryParseEnvelope: otp_key_id or ciphertext_b64url is empty");
                return false;
            }
            
            _logger.LogInformation("TryParseEnvelope: Success - OTP envelope detected");
            envelope = parsed;
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"TryParseEnvelope failed: {ex.Message}, body: {body}");
            return false;
        }
    }

    private async Task<string> EncryptBodyAsync(string plaintext)
    {
        return await RetryAsync(async () =>
        {
            _logger.LogInformation("Calling OTP encrypt API at {OtpUrl}/api/otp/encrypt for plaintext length {Length}", OtpBaseUrl, plaintext?.Length ?? 0);

            var req = new OtpEncryptRequest(plaintext);
            using var response = await _http.PostAsJsonAsync($"{OtpBaseUrl}/api/otp/encrypt", req, _jsonOptions);

            _logger.LogInformation("OTP encrypt API response status: {StatusCode}", response.StatusCode);

            response.EnsureSuccessStatusCode();
            var res = await response.Content.ReadFromJsonAsync<OtpEncryptResponse>(_jsonOptions);

            if (res == null || string.IsNullOrWhiteSpace(res.key_id) || string.IsNullOrWhiteSpace(res.ciphertext_b64url))
            {
                _logger.LogError("OTP encrypt returned invalid response - null or missing fields");
                throw new InvalidOperationException("Invalid encrypt response");
            }

            var envelope = new BodyEnvelope(res.key_id, res.ciphertext_b64url);
            _logger.LogInformation("OTP encryption successful, key_id: {KeyId}", res.key_id);
            return JsonSerializer.Serialize(envelope, _jsonOptions);
        }, "OTP encryption");
    }

    private async Task<T> RetryAsync<T>(Func<Task<T>> operation, string operationName)
    {
        for (int attempt = 1; attempt <= MaxRetries; attempt++)
        {
            try
            {
                return await operation();
            }
            catch (HttpRequestException ex) when (attempt < MaxRetries)
            {
                var delaySeconds = Math.Pow(2, attempt);
                _logger.LogWarning(ex, "{Operation} failed (attempt {Attempt}/{MaxRetries}), retrying in {Delay}s...",
                    operationName, attempt, MaxRetries, delaySeconds);
                await Task.Delay(TimeSpan.FromSeconds(delaySeconds));
            }
            catch (Exception ex) when (attempt == MaxRetries)
            {
                _logger.LogError(ex, "{Operation} failed after {MaxRetries} attempts", operationName, MaxRetries);
                throw new InvalidOperationException($"{operationName} failed: {ex.Message}", ex);
            }
        }
        throw new InvalidOperationException($"{operationName} failed after {MaxRetries} retries");
    }

    private bool IsAlreadyEncrypted(string data, string method)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(data)) return false;
            var trimmed = data.Trim();
            if (trimmed.StartsWith("{") && trimmed.EndsWith("}"))
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(trimmed);
                
                if (string.Equals(method, "AES", StringComparison.OrdinalIgnoreCase))
                {
                    if (parsed.TryGetProperty("keyId", out var keyId) && 
                        parsed.TryGetProperty("ivHex", out var ivHex) &&
                        parsed.TryGetProperty("ciphertextHex", out var ciphertextHex) &&
                        parsed.TryGetProperty("tagHex", out var tagHex))
                    {
                        return !string.IsNullOrEmpty(keyId.GetString()) && 
                               !string.IsNullOrEmpty(ivHex.GetString()) &&
                               !string.IsNullOrEmpty(ciphertextHex.GetString()) &&
                               !string.IsNullOrEmpty(tagHex.GetString());
                    }
                    if (parsed.TryGetProperty("key_id", out var key_id) && 
                        parsed.TryGetProperty("iv_hex", out var iv_hex) &&
                        parsed.TryGetProperty("ciphertext_hex", out var ciphertext_hex) &&
                        parsed.TryGetProperty("tag_hex", out var tag_hex2))
                    {
                        return !string.IsNullOrEmpty(key_id.GetString()) && 
                               !string.IsNullOrEmpty(iv_hex.GetString()) &&
                               !string.IsNullOrEmpty(ciphertext_hex.GetString()) &&
                               !string.IsNullOrEmpty(tag_hex2.GetString());
                    }
                }
                
                if ((string.Equals(method, "OTP", StringComparison.OrdinalIgnoreCase)) &&
                    parsed.TryGetProperty("otp_key_id", out var otpKeyId) && 
                    parsed.TryGetProperty("ciphertext_b64url", out var ciphertextB64))
                {
                    return !string.IsNullOrEmpty(otpKeyId.GetString()) && 
                           !string.IsNullOrEmpty(ciphertextB64.GetString());
                }
            }
            return false;
        }
        catch
        {
            _logger.LogWarning("IsAlreadyEncrypted parse failed for method={Method}. Preview={Preview}", method, data?.Substring(0, Math.Min(120, data.Length)));
            return false;
        }
    }

    private async Task<string> DecryptByMethodAsync(string body, string encryptionMethod)
    {
        try
        {
            _logger.LogInformation("Decrypting body using method: {Method}", encryptionMethod);
            
            switch (encryptionMethod.ToUpper())
            {
                case "AES":
                    if (TryParseAESEnvelope(body, out var aesEnvelope))
                    {
                        _logger.LogInformation("Decrypting AES envelope");
                        return await DecryptAESAsync(aesEnvelope);
                    }
                    _logger.LogWarning("Failed to parse AES envelope, returning as-is");
                    return body;
                    
                case "OTP":
                    if (TryParseEnvelope(body, out var otpEnvelope))
                    {
                        _logger.LogInformation("Decrypting OTP envelope");
                        return await DecryptOTPAsync(otpEnvelope);
                    }
                    _logger.LogWarning("Failed to parse OTP envelope, returning as-is");
                    return body;
                    
                case "PQC_2_LAYER":
                    if (TryParseEnvelope(body, out var otpEnvelope2))
                    {
                        _logger.LogInformation("Decrypting PQC_2_LAYER: OTP layer first");
                        var otpDecrypted2 = await DecryptOTPAsync(otpEnvelope2);
                        
                        if (TryParsePQCEnvelope(otpDecrypted2, out var pqcEnvelope2))
                        {
                            _logger.LogInformation("OTP decrypted to PQC envelope, returning for frontend decryption");
                            return JsonSerializer.Serialize(pqcEnvelope2, _jsonOptions);
                        }
                        
                        return otpDecrypted2;
                    }
                    _logger.LogWarning("Failed to parse OTP envelope for PQC_2_LAYER, returning as-is");
                    return body;
                    
                case "PQC_3_LAYER":
                    if (TryParsePQCEnvelope(body, out var pqcEnvelope))
                    {
                        _logger.LogInformation("Decrypting PQC envelope");
                        return await DecryptPQCAsync(pqcEnvelope);
                    }
                    _logger.LogWarning("Failed to parse PQC envelope, returning as-is");
                    return body;
                    
                default:
                    _logger.LogWarning("Unknown encryption method: {Method}, returning as-is", encryptionMethod);
                    return body;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt body with method {Method}, returning original", encryptionMethod);
            return body;
        }
    }

    private async Task<string> TryDecryptBodyAsync(string body)
    {
        try
        {
            _logger.LogInformation("Attempting to decrypt body: {Body}", body);
            
            if (TryParseAESEnvelope(body, out var aesEnvelope))
            {
                _logger.LogInformation("Detected AES envelope, decrypting with AES API");
                return await DecryptAESAsync(aesEnvelope);
            }

            if (TryParseEnvelope(body, out var otpEnvelope3))
            {
                _logger.LogInformation("Detected OTP envelope, decrypting with OTP API");
                var otpDecrypted3 = await DecryptOTPAsync(otpEnvelope3);
                
                if (TryParsePQCEnvelope(otpDecrypted3, out var pqcEnvelope3))
                {
                    _logger.LogInformation("OTP decrypted to PQC envelope, returning PQC data for frontend decryption");
                    return JsonSerializer.Serialize(pqcEnvelope3, _jsonOptions);
                }
                
                return otpDecrypted3;
            }

            if (TryParsePQCEnvelope(body, out var pqcEnvelope4))
            {
                _logger.LogInformation("Detected direct PQC envelope, returning for frontend decryption");
                return JsonSerializer.Serialize(pqcEnvelope4, _jsonOptions);
            }

            _logger.LogInformation("No encryption envelope detected, returning as plain text");
            return body;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to decrypt body, returning original");
            return body;
        }
    }

    private async Task<string> DecryptOTPAsync(BodyEnvelope envelope)
    {
        try
        {
            _logger.LogInformation("Calling OTP decrypt API with key_id: {KeyId}", envelope.otp_key_id);
            var req = new OtpDecryptRequest(envelope.otp_key_id, envelope.ciphertext_b64url);
            using var response = await _http.PostAsJsonAsync($"{OtpBaseUrl}/api/otp/decrypt", req, _jsonOptions);
            response.EnsureSuccessStatusCode();
            var res = await response.Content.ReadFromJsonAsync<OtpDecryptResponse>(_jsonOptions);
            if (res == null)
            {
                _logger.LogError("OTP decrypt API returned null response");
                return "Decryption failed";
            }
            if (!string.IsNullOrEmpty(res.text))
            {
                _logger.LogInformation("OTP decryption successful");
                return res.text!;
            }
            if (!string.IsNullOrEmpty(res.plaintext_b64url))
            {
                try
                {
                    var bytes = Convert.FromBase64String(Base64UrlToBase64(res.plaintext_b64url!));
                    _logger.LogInformation("OTP decryption successful (base64)");
                    return Encoding.UTF8.GetString(bytes);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to decode base64 from OTP response");
                    return "Decryption failed";
                }
            }
            _logger.LogError("OTP decrypt API returned empty response");
            return "Decryption failed";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OTP decryption failed");
            return "OTP decryption failed";
        }
    }

    private async Task<string> DecryptAESAsync(AESEnvelope envelope)
    {
        try
        {
            _logger.LogInformation("=== AES DECRYPT START ===");
            _logger.LogInformation("Calling AES decrypt API with key_id: {KeyId}", envelope.KeyId);
            _logger.LogInformation("AES envelope - KeyId: {KeyId}", envelope.KeyId);
            _logger.LogInformation("AES envelope - IvHex length: {IvLen}", envelope.IvHex?.Length ?? 0);
            _logger.LogInformation("AES envelope - CiphertextHex length: {CtLen}", envelope.CiphertextHex?.Length ?? 0);
            _logger.LogInformation("AES envelope - TagHex length: {TagLen}", envelope.TagHex?.Length ?? 0);
            _logger.LogInformation("AES envelope - AadHex length: {AadLen}", envelope.AadHex?.Length ?? 0);

            var ctPreview = envelope.CiphertextHex?.Length > 100 ? envelope.CiphertextHex.Substring(0, 100) + "..." : envelope.CiphertextHex;
            _logger.LogInformation("AES envelope - CiphertextHex preview: {CtPreview}", ctPreview);

            var req = new
            {
                key_id = envelope.KeyId,
                iv_hex = envelope.IvHex,
                ciphertext_hex = envelope.CiphertextHex,
                tag_hex = envelope.TagHex,
                aad_hex = envelope.AadHex
            };

            _logger.LogInformation("Sending AES decrypt request to: {AesUrl}/api/gcm/decrypt", AesBaseUrl);
            _logger.LogInformation("Request payload size: ~{Size} bytes", JsonSerializer.Serialize(req).Length);

            using var response = await _http.PostAsJsonAsync($"{AesBaseUrl}/api/gcm/decrypt", req);

            _logger.LogInformation("AES decrypt API response status: {StatusCode}", response.StatusCode);
            _logger.LogInformation("AES decrypt API response headers: {Headers}", string.Join(", ", response.Headers.Select(h => $"{h.Key}={string.Join(",", h.Value)}")));
            
            if (response.IsSuccessStatusCode)
            {
                var contentType = response.Content.Headers.ContentType?.MediaType;
                _logger.LogInformation("AES decrypt response content type: {ContentType}", contentType);
                
                var responseContent = await response.Content.ReadAsStringAsync();
                _logger.LogInformation("AES decrypt raw response: {Response}", responseContent);
                
                try
                {
                    var jsonDoc = JsonDocument.Parse(responseContent);
                    if (jsonDoc.RootElement.TryGetProperty("plaintext", out var plaintextElement))
                    {
                        var plaintext = plaintextElement.GetString();
                        _logger.LogInformation("AES decryption successful, extracted plaintext from JSON: {Plaintext}", plaintext);
                        return plaintext ?? string.Empty;
                    }
                }
                catch (JsonException)
                {
                }
                
                _logger.LogInformation("AES decryption successful, returning raw content length: {Length}", responseContent?.Length ?? 0);
                _logger.LogInformation("=== AES DECRYPT END (SUCCESS) ===");
                return responseContent;
            }

            var errorContent = await response.Content.ReadAsStringAsync();
            _logger.LogError("AES decrypt API returned ERROR status: {StatusCode}", response.StatusCode);
            _logger.LogError("AES decrypt error content length: {Length}", errorContent?.Length ?? 0);
            _logger.LogError("AES decrypt error content preview: {Preview}", errorContent?.Length > 500 ? errorContent.Substring(0, 500) + "..." : errorContent);
            _logger.LogInformation("=== AES DECRYPT END (FAILED) ===");
            throw new InvalidOperationException($"AES decryption failed: HTTP {response.StatusCode}. The AES service may be unavailable or the encryption key may be invalid.");
        }
        catch (InvalidOperationException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AES decryption failed with exception: {Message}", ex.Message);
            _logger.LogError("Exception stack trace: {StackTrace}", ex.StackTrace);
            _logger.LogInformation("=== AES DECRYPT END (EXCEPTION) ===");
            throw new InvalidOperationException($"AES decryption failed: {ex.Message}", ex);
        }
    }

    private async Task<string> DecryptPQCAsync(PQCEnvelope envelope)
    {
        try
        {
            _logger.LogInformation("Attempting PQC decryption");
            
            var jsonString = JsonSerializer.Serialize(envelope, _jsonOptions);
            _logger.LogInformation("Returning PQC envelope as JSON for frontend decryption");
            return jsonString;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "PQC decryption failed");
            return "PQC decryption failed";
        }
    }

    private bool TryParseAESEnvelope(string body, out AESEnvelope envelope)
    {
        envelope = default!;
        try
        {
            _logger.LogInformation($"TryParseAESEnvelope: Attempting to parse body: {body}");
            
            var parsed = JsonSerializer.Deserialize<AESEnvelope>(body, _jsonOptions);
            if (parsed != null && !string.IsNullOrWhiteSpace(parsed.KeyId) && !string.IsNullOrWhiteSpace(parsed.CiphertextHex))
            {
                _logger.LogInformation($"TryParseAESEnvelope: Success with camelCase format - KeyId: {parsed.KeyId}, IvHex: {parsed.IvHex}, CiphertextHex: {parsed.CiphertextHex}, TagHex: {parsed.TagHex}");
                envelope = parsed;
                return true;
            }
            
            var jsonDoc = JsonDocument.Parse(body);
            var root = jsonDoc.RootElement;
            
            var keyId = root.TryGetProperty("keyId", out var kidCamel) ? kidCamel.GetString() : 
                       (root.TryGetProperty("key_id", out var kidSnake) ? kidSnake.GetString() : null);
            var ivHex = root.TryGetProperty("ivHex", out var ivCamel) ? ivCamel.GetString() : 
                       (root.TryGetProperty("iv_hex", out var ivSnake) ? ivSnake.GetString() : null);
            var ciphertextHex = root.TryGetProperty("ciphertextHex", out var ctCamel) ? ctCamel.GetString() : 
                               (root.TryGetProperty("ciphertext_hex", out var ctSnake) ? ctSnake.GetString() : null);
            var tagHex = root.TryGetProperty("tagHex", out var tagCamel) ? tagCamel.GetString() : 
                        (root.TryGetProperty("tag_hex", out var tagSnake) ? tagSnake.GetString() : null);
            var aadHex = root.TryGetProperty("aadHex", out var aadCamel) ? aadCamel.GetString() : 
                        (root.TryGetProperty("aad_hex", out var aadSnake) ? aadSnake.GetString() : "");
            var algorithm = root.TryGetProperty("algorithm", out var algProp) ? algProp.GetString() : "AES-256-GCM";
            
            if (string.IsNullOrWhiteSpace(keyId) || string.IsNullOrWhiteSpace(ciphertextHex))
            {
                _logger.LogInformation("TryParseAESEnvelope: KeyId or CiphertextHex is empty after parsing both formats");
                return false;
            }
            
            if (string.IsNullOrWhiteSpace(ivHex) || string.IsNullOrWhiteSpace(tagHex))
            {
                _logger.LogInformation("TryParseAESEnvelope: IvHex or TagHex is empty");
                return false;
            }
            
            envelope = new AESEnvelope
            {
                KeyId = keyId,
                IvHex = ivHex,
                CiphertextHex = ciphertextHex,
                TagHex = tagHex,
                AadHex = aadHex ?? "",
                Algorithm = algorithm ?? "AES-256-GCM"
            };
            
            _logger.LogInformation($"TryParseAESEnvelope: Success with snake_case conversion - KeyId: {envelope.KeyId}, IvHex: {envelope.IvHex}, CiphertextHex: {envelope.CiphertextHex}, TagHex: {envelope.TagHex}");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"TryParseAESEnvelope failed: {ex.Message}, body: {body}");
            return false;
        }
    }

    private static bool TryParsePQCEnvelope(string body, out PQCEnvelope envelope)
    {
        envelope = default!;
        try
        {
            var parsed = JsonSerializer.Deserialize<PQCEnvelope>(body, _jsonOptions);
            if (parsed == null || string.IsNullOrWhiteSpace(parsed.EncryptedBody) || string.IsNullOrWhiteSpace(parsed.PQCCiphertext))
            {
                return false;
            }
            envelope = parsed;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string Base64UrlToBase64(string base64Url)
    {
        var s = base64Url.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return s;
    }

    private async Task<object[]?> TryDecryptAttachmentsAsync(string? attachmentsJson)
    {
        if (string.IsNullOrWhiteSpace(attachmentsJson)) return null;
        try
        {
            var list = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(attachmentsJson, _jsonOptions);
            if (list == null || list.Count == 0) return null;
            var result = new List<object>(list.Count);
            foreach (var item in list)
            {
                var fileName = item.ContainsKey("fileName") ? item["fileName"]?.ToString() :
                              (item.ContainsKey("FileName") ? item["FileName"]?.ToString() : null);
                var contentType = item.ContainsKey("contentType") ? item["contentType"]?.ToString() :
                                 (item.ContainsKey("ContentType") ? item["ContentType"]?.ToString() : null);

                if (string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(contentType))
                {
                    _logger.LogWarning("Skipping attachment with missing fileName or contentType");
                    continue;
                }

                var envelope = item.ContainsKey("envelope") ? item["envelope"]?.ToString() : null;
                var plainBase64 = item.ContainsKey("contentBase64") ? item["contentBase64"]?.ToString() :
                                 (item.ContainsKey("ContentBase64") ? item["ContentBase64"]?.ToString() : null);

                string contentBase64;
                if (!string.IsNullOrWhiteSpace(envelope))
                {
                    _logger.LogInformation("Decrypting attachment: {FileName}", fileName);
                    contentBase64 = await TryDecryptBodyAsync(envelope);
                }
                else if (!string.IsNullOrWhiteSpace(plainBase64))
                {
                    _logger.LogWarning("Found plain (unencrypted) attachment: {FileName}", fileName);
                    contentBase64 = plainBase64;
                }
                else
                {
                    _logger.LogWarning("Skipping attachment with no envelope or contentBase64: {FileName}", fileName);
                    continue;
                }

                result.Add(new { fileName, contentType, contentBase64 });
            }
            return result.ToArray();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt attachments");
            return null;
        }
    }
    private async Task TrySendExternallyAsync(SendEmailRequest request, User recipient, string subjectEnvelope, string bodyEnvelope)
    {
        try
        {
            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            string? smtpPassword = null;
            string? senderExternalEmail = null;
            if (sender != null && !string.IsNullOrWhiteSpace(sender.AppPasswordHash))
            {
                try { smtpPassword = QuMail.EmailProtocol.Services.SecretProtector.Decrypt(sender.AppPasswordHash); } catch { smtpPassword = null; }
                senderExternalEmail = sender.ExternalEmail;
            }
            if (string.IsNullOrWhiteSpace(smtpPassword) || string.IsNullOrWhiteSpace(senderExternalEmail)) return;
            smtpPassword = smtpPassword!.Replace(" ", string.Empty);

            var providerKey = !string.IsNullOrWhiteSpace(sender?.EmailProvider) ? sender!.EmailProvider! : "gmail";
            if (!EmailProviderDefaults.DefaultProviders.TryGetValue(providerKey, out var provider))
            {
                provider = EmailProviderDefaults.DefaultProviders["gmail"];
            }
            var smtp = provider.Smtp;

            var externalRecipient = !string.IsNullOrWhiteSpace(recipient.ExternalEmail) ? recipient.ExternalEmail! : recipient.Email;

            var mail = new MailMessage
            {
                From = new MailAddress(senderExternalEmail),
                Subject = subjectEnvelope,
                Body = bodyEnvelope,
                IsBodyHtml = false
            };
            mail.To.Add(new MailAddress(externalRecipient));

            async Task<bool> TrySendAsync(string host, int port, bool enableSsl)
            {
                using var client = new SmtpClient(host, port)
                {
                    EnableSsl = enableSsl,
                    DeliveryMethod = SmtpDeliveryMethod.Network,
                    UseDefaultCredentials = false,
                    Credentials = new NetworkCredential(senderExternalEmail, smtpPassword)
                };
                try
                {
                    await client.SendMailAsync(mail);
                    _logger?.LogInformation("SMTP sent to {Recipient} via {Host}:{Port} (SSL={SSL})", externalRecipient, host, port, enableSsl);
                    return true;
                }
                catch (SmtpException ex)
                {
                    _logger?.LogError(ex, "SMTP send failed to {Recipient} via {Host}:{Port} (SSL={SSL})", externalRecipient, host, port, enableSsl);
                    return false;
                }
            }

            var sent = await TrySendAsync(smtp.Host, smtp.Port, smtp.EnableSsl);
            if (!sent && smtp.Host.Contains("gmail"))
            {
                await TrySendAsync(smtp.Host, 465, true);
            }
        }
        catch
        {
        }
    }
    [HttpPost("validate-user")]
    public async Task<IActionResult> ValidateUser([FromBody] ValidateUserRequest request)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.Email);

            return Ok(new {
                success = true,
                exists = user != null,
                name = user?.Name,
                message = user != null ? "User exists" : "User not found"
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new {
                success = false,
                message = $"Failed to validate user: {ex.Message}"
            });
        }
    }

    [HttpPost("validate-recipient")]
    public async Task<IActionResult> ValidateRecipient([FromBody] ValidateRecipientRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.RecipientEmail))
            {
                return BadRequest(new { success = false, message = "Recipient email is required" });
            }

            var recipient = await _context.Users.FirstOrDefaultAsync(u =>
                u.Email == request.RecipientEmail || u.ExternalEmail == request.RecipientEmail);

            if (recipient == null)
            {
                return Ok(new {
                    success = true,
                    exists = false,
                    message = "Recipient not found"
                });
            }

            return Ok(new {
                success = true,
                exists = true,
                publicKey = recipient.PqcPublicKey ?? "",
                name = recipient.Name,
                message = "Recipient found"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to validate recipient");
            return BadRequest(new {
                success = false,
                message = $"Failed to validate recipient: {ex.Message}"
            });
        }
    }

    private async Task<string?> EncryptAttachmentsOTPAsync(List<SendAttachment>? attachments)
    {
        if (attachments == null || attachments.Count == 0) return null;

        var encrypted = new List<object>(attachments.Count);
        foreach (var a in attachments)
        {
            var envelope = await EncryptBodyAsync(a.ContentBase64);
            encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
        }
        return JsonSerializer.Serialize(encrypted, _jsonOptions);
    }

    private async Task<string?> EncryptAttachmentsPQC2LayerAsync(List<SendAttachment>? attachments, string recipientPublicKey)
    {
        if (attachments == null || attachments.Count == 0) return null;

        var encrypted = new List<object>(attachments.Count);
        foreach (var a in attachments)
        {
            var envelope = await EncryptSingleWithPQC2LayerAsync(a.ContentBase64, recipientPublicKey);
            encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
        }
        return JsonSerializer.Serialize(encrypted, _jsonOptions);
    }

    private async Task<string?> EncryptAttachmentsPQC3LayerAsync(List<SendAttachment>? attachments, string recipientPublicKey)
    {
        if (attachments == null || attachments.Count == 0) return null;

        var encrypted = new List<object>(attachments.Count);
        foreach (var a in attachments)
        {
            var envelope = await EncryptSingleWithPQC3LayerAsync(a.ContentBase64, recipientPublicKey);
            encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
        }
        return JsonSerializer.Serialize(encrypted, _jsonOptions);
    }

    private async Task<EncryptionResult> EncryptWithAESAsync(string subject, string body, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with AES-GCM via server2.py");

        var subjectEnvelope = await EncryptWithAESGCMAsync(subject);
        var bodyEnvelope = await EncryptWithAESGCMAsync(body);

        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var envelope = await EncryptWithAESGCMAsync(a.ContentBase64);
                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }

        return new EncryptionResult { SubjectEnvelope = subjectEnvelope, BodyEnvelope = bodyEnvelope, AttachmentsJson = attachmentsJson };
    }

    private async Task<EncryptionResult> EncryptWithPQC2LayerAsync(string subject, string body, string recipientPublicKey, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with PQC 2-layer (Kyber-512 + OTP)");
        
        var subjectEnvelope = await EncryptSingleWithPQC2LayerAsync(subject, recipientPublicKey);
        var bodyEnvelope = await EncryptSingleWithPQC2LayerAsync(body, recipientPublicKey);
        
        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var envelope = await EncryptSingleWithPQC2LayerAsync(a.ContentBase64, recipientPublicKey);
                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }
        
        return new EncryptionResult { SubjectEnvelope = subjectEnvelope, BodyEnvelope = bodyEnvelope, AttachmentsJson = attachmentsJson };
    }

    private async Task<EncryptionResult> EncryptWithPQC3LayerAsync(string subject, string body, string recipientPublicKey, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with PQC 3-layer (Kyber-1024 + AES-256 + OTP)");

        _logger.LogInformation("Phase 1: PQC encryption");
        var pqcSubject = await EncryptSingleWithPQC3LayerAsync(subject, recipientPublicKey);
        var pqcBody = await EncryptSingleWithPQC3LayerAsync(body, recipientPublicKey);

        _logger.LogInformation("Phase 2: Preparing PQC envelopes for AES encryption");
        var pqcSubjectForAES = PreparePqcEnvelopeForAES(pqcSubject);
        var pqcBodyForAES = PreparePqcEnvelopeForAES(pqcBody);

        _logger.LogInformation("Phase 3: AES encryption");
        var aesSubject = await EncryptWithAESGCMAsync(pqcSubjectForAES);
        var aesBody = await EncryptWithAESGCMAsync(pqcBodyForAES);

        _logger.LogInformation("Phase 4: OTP encryption");
        var finalSubject = await EncryptBodyAsync(aesSubject);
        var finalBody = await EncryptBodyAsync(aesBody);

        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            _logger.LogInformation("Encrypting {Count} attachments with PQC 3-layer", attachments.Count);
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var pqcEnvelope = await EncryptSingleWithPQC3LayerAsync(a.ContentBase64, recipientPublicKey);

                var pqcEnvelopeForAES = pqcEnvelope;

                var aesEnvelope = await EncryptWithAESGCMAsync(pqcEnvelopeForAES);

                var finalEnvelope = await EncryptBodyAsync(aesEnvelope);

                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope = finalEnvelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }

        return new EncryptionResult { SubjectEnvelope = finalSubject, BodyEnvelope = finalBody, AttachmentsJson = attachmentsJson };
    }

    private string PreparePqcEnvelopeForAES(string pqcJsonEnvelope)
    {
        try
        {
            _logger.LogInformation("Preparing PQC JSON envelope for AES encryption");
            
            if (string.IsNullOrWhiteSpace(pqcJsonEnvelope))
            {
                _logger.LogWarning("Empty PQC envelope provided, returning as-is");
                return pqcJsonEnvelope;
            }
            
            using var testDoc = JsonDocument.Parse(pqcJsonEnvelope);
            if (!testDoc.RootElement.TryGetProperty("encryptedBody", out _))
            {
                _logger.LogWarning("PQC envelope missing 'encryptedBody' property, returning as-is");
                return pqcJsonEnvelope;
            }
            
            var base64Encoded = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(pqcJsonEnvelope));
            _logger.LogInformation("Successfully prepared PQC envelope for AES encryption (size: {Size} chars)", base64Encoded.Length);
            return base64Encoded;
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Invalid JSON in PQC envelope, using original");
            return pqcJsonEnvelope;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to prepare PQC envelope for AES, using original");
            return pqcJsonEnvelope;
        }
    }

    private string RestorePqcEnvelopeFromAES(string aesDecryptedResult)
    {
        try
        {
            _logger.LogInformation("Restoring PQC JSON envelope from AES decryption result");
            
            if (string.IsNullOrWhiteSpace(aesDecryptedResult))
            {
                _logger.LogWarning("Empty AES decryption result provided, returning as-is");
                return aesDecryptedResult;
            }
            
            var jsonBytes = Convert.FromBase64String(aesDecryptedResult);
            var originalJsonEnvelope = System.Text.Encoding.UTF8.GetString(jsonBytes);
            
            using var testDoc = JsonDocument.Parse(originalJsonEnvelope);
            if (!testDoc.RootElement.TryGetProperty("encryptedBody", out _))
            {
                _logger.LogWarning("Restored envelope missing 'encryptedBody' property, using original");
                return aesDecryptedResult;
            }
            
            _logger.LogInformation("Successfully restored PQC envelope from AES decryption (size: {Size} chars)", originalJsonEnvelope.Length);
            return originalJsonEnvelope;
        }
        catch (FormatException ex)
        {
            _logger.LogError(ex, "Invalid base64 format in AES decryption result - data is corrupted");
            throw new InvalidOperationException("Failed to restore PQC envelope: AES decryption result is not valid base64. The data may be corrupted or the AES service returned an error.", ex);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Invalid JSON structure after base64 decode - PQC envelope is malformed");
            throw new InvalidOperationException("Failed to restore PQC envelope: Invalid JSON structure after base64 decode. The encrypted data may be corrupted.", ex);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error restoring PQC envelope from AES: {Error}", ex.Message);
            throw new InvalidOperationException($"Failed to restore PQC envelope from AES: {ex.Message}", ex);
        }
    }

    private async Task<string> EncryptWithAESGCMAsync(string plaintext)
    {
        return await RetryAsync(async () =>
        {
            _logger.LogInformation("Starting AES-GCM encryption for plaintext: {Plaintext}", plaintext);

            var requestBody = new { plaintext = plaintext };
            _logger.LogInformation("Sending request to AES server: {AesUrl}/api/gcm/encrypt", AesBaseUrl);

            var response = await _http.PostAsJsonAsync($"{AesBaseUrl}/api/gcm/encrypt", requestBody);

            _logger.LogInformation("AES server response status: {StatusCode}", response.StatusCode);

            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogError($"AES-GCM encryption failed: {response.StatusCode} - {errorContent}");
                throw new HttpRequestException($"AES-GCM encryption failed: {response.StatusCode} - {errorContent}");
            }

            var result = await response.Content.ReadFromJsonAsync<AESEncryptionResult>();
            if (result == null)
            {
                _logger.LogError("Failed to parse AES encryption response - result is null");
                throw new Exception("Failed to parse AES encryption response - result is null");
            }

            _logger.LogInformation("AES encryption successful - KeyId: {KeyId}, IvHex: {IvHex}, CiphertextHex: {CiphertextHex}, TagHex: {TagHex}",
                result.KeyId, result.IvHex, result.CiphertextHex, result.TagHex);

            var envelope = new AESEnvelope
            {
                KeyId = result.KeyId,
                IvHex = result.IvHex,
                CiphertextHex = result.CiphertextHex,
                TagHex = result.TagHex,
                AadHex = result.AadHex,
                Algorithm = "AES-256-GCM"
            };

            var serialized = JsonSerializer.Serialize(envelope, _jsonOptions);
            _logger.LogInformation("AES envelope serialized: {Envelope}", serialized);

            return serialized;
        }, "AES-GCM encryption");
    }

    private async Task<string> EncryptSingleWithPQC2LayerAsync(string plaintext, string recipientPublicKey)
    {
        try
        {
            var encrypted = _pqcEmailService.EncryptEmail(plaintext, recipientPublicKey);
            
            var envelope = new
            {
                encryptedBody = encrypted.EncryptedBody,
                pqcCiphertext = encrypted.PQCCiphertext,
                encryptedKeyId = encrypted.EncryptedKeyId,
                algorithm = encrypted.Algorithm,
                keyId = encrypted.KeyId,
                securityLevel = "Kyber512",
                useAES = false
            };

            return JsonSerializer.Serialize(envelope, _jsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "PQC 2-layer encryption failed for plaintext");
            throw;
        }
    }

    private async Task<string> EncryptSingleWithPQC3LayerAsync(string plaintext, string recipientPublicKey)
    {
        try
        {
            var encrypted = _hybridEncryption.Encrypt(
                plaintext, 
                recipientPublicKey, 
                Level3EnhancedPQC.SecurityLevel.Kyber512, 
                useAES: true);
            var envelope = new
            {
                encryptedBody = encrypted.EncryptedBody,
                pqcCiphertext = encrypted.PQCCiphertext,
                encryptedKeyId = encrypted.EncryptedKeyId, 
                algorithm = encrypted.Algorithm,
                keyId = encrypted.KeyId,
                securityLevel = encrypted.SecurityLevel,
                useAES = encrypted.UseAES
            };

            return JsonSerializer.Serialize(envelope, _jsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "PQC 3-layer encryption failed for plaintext");
            throw;
        }
    }
}

public class SendEmailRequest
{
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public List<SendAttachment>? Attachments { get; set; }
    public string EncryptionMethod { get; set; } = "OTP";
    public string? RecipientPublicKey { get; set; }
}
public class SendAttachment
{
    public string FileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = "application/octet-stream";
    public string ContentBase64 { get; set; } = string.Empty; 
}

public class ValidateUserRequest
{
    public string Email { get; set; } = string.Empty;
}

public class ValidateRecipientRequest
{
    public string RecipientEmail { get; set; } = string.Empty;
}

public class SendPqcEncryptedRequest
{
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public string PqcEncryptedSubject { get; set; } = string.Empty;
    public string PqcEncryptedBody { get; set; } = string.Empty;
    public List<SendAttachment>? Attachments { get; set; }
}

public class EncryptionResult
{
    public string SubjectEnvelope { get; set; } = string.Empty;
    public string BodyEnvelope { get; set; } = string.Empty;
    public string? AttachmentsJson { get; set; }
}

public class AESEncryptionResult
{
    [JsonPropertyName("key_id")]
    public string KeyId { get; set; } = string.Empty;

    [JsonPropertyName("iv_hex")]
    public string IvHex { get; set; } = string.Empty;

    [JsonPropertyName("ciphertext_hex")]
    public string CiphertextHex { get; set; } = string.Empty;

    [JsonPropertyName("tag_hex")]
    public string TagHex { get; set; } = string.Empty;

    [JsonPropertyName("aad_hex")]
    public string AadHex { get; set; } = string.Empty;
}

public class PQCEncryptionResult
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public PQCEncryptionData? Data { get; set; }
}

public class PQCEncryptionData
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string Algorithm { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = string.Empty;
    public bool UseAES { get; set; }
    public string KeyId { get; set; } = string.Empty;
}

public class AESEnvelope
{
    public string KeyId { get; set; } = string.Empty;
    public string IvHex { get; set; } = string.Empty;
    public string CiphertextHex { get; set; } = string.Empty;
    public string TagHex { get; set; } = string.Empty;
    public string AadHex { get; set; } = string.Empty;
    public string Algorithm { get; set; } = string.Empty;
}

public class PQCEnvelope
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string Algorithm { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = string.Empty;
    public bool UseAES { get; set; }
    public string KeyId { get; set; } = string.Empty;
}
