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
        Timeout = TimeSpan.FromSeconds(10)
    };
    private const string OtpBaseUrl = "http://aes-server:8081"; // OTP API Docker network address

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

    /// <summary>
    /// Get a user's PQC public key by email (supports internal Email or ExternalEmail)
    /// GET /api/email/pqc/public-key/{email}
    /// </summary>
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

    /// <summary>
    /// Register or update a user's PQC public key
    /// POST /api/email/pqc/public-key
    /// Body: { email, publicKey }
    /// </summary>
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

    [HttpPost("send")]
    public async Task<IActionResult> SendEmail([FromBody] SendEmailRequest request)
    {
        try
        {
            _logger.LogInformation($"Starting email send with encryption method: {request.EncryptionMethod}");
            
            // Check if recipient exists by primary app email or mapped external email
            var recipient = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.RecipientEmail || u.ExternalEmail == request.RecipientEmail);
            if (recipient == null)
            {
                return BadRequest(new { 
                    success = false, 
                    message = "Recipient email not found in our system" 
                });
            }

            // Validate encryption method and required parameters
            if (request.EncryptionMethod.StartsWith("PQC") && string.IsNullOrEmpty(request.RecipientPublicKey))
            {
                return BadRequest(new { 
                    success = false, 
                    message = "RecipientPublicKey is required for PQC encryption methods" 
                });
            }

            string subjectEnvelope, bodyEnvelope;
            string? attachmentsJson = null;

            // Check if data is already encrypted (from frontend)
            _logger.LogInformation("SendEmail: method={Method} subj.len={SL} body.len={BL}", request.EncryptionMethod, (request.Subject ?? string.Empty).Length, (request.Body ?? string.Empty).Length);
            bool isAlreadyEncrypted = IsAlreadyEncrypted(request.Subject, request.EncryptionMethod) || IsAlreadyEncrypted(request.Body, request.EncryptionMethod);
            _logger.LogInformation("SendEmail: isAlreadyEncrypted={IsEnc}", isAlreadyEncrypted);
            
            if (isAlreadyEncrypted)
            {
                _logger.LogInformation("Data is already encrypted from frontend, using as-is (storing raw envelopes)");
                subjectEnvelope = request.Subject ?? string.Empty;
                bodyEnvelope = request.Body ?? string.Empty;
                // For attachments, we'll handle them separately if needed
                attachmentsJson = request.Attachments != null ? JsonSerializer.Serialize(request.Attachments) : null;
            }
            else
            {
                // Route to appropriate encryption method
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
                        subjectEnvelope = await EncryptSingleWithPQC2LayerAsync(request.Subject, request.RecipientPublicKey);
                        bodyEnvelope = await EncryptSingleWithPQC2LayerAsync(request.Body, request.RecipientPublicKey);
                        attachmentsJson = await EncryptAttachmentsOTPAsync(request.Attachments);
                        break;

                    case "PQC_3_LAYER":
                        _logger.LogInformation("Using PQC 3-layer encryption");
                        subjectEnvelope = await EncryptSingleWithPQC3LayerAsync(request.Subject, request.RecipientPublicKey);
                        bodyEnvelope = await EncryptSingleWithPQC3LayerAsync(request.Body, request.RecipientPublicKey);
                        attachmentsJson = await EncryptAttachmentsOTPAsync(request.Attachments);
                        break;

                    default:
                        return BadRequest(new { 
                            success = false, 
                            message = $"Unsupported encryption method: {request.EncryptionMethod}. Supported: OTP, AES, PQC_2_LAYER, PQC_3_LAYER" 
                        });
                }
            }

            // Resolve sender original email if available
            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            var senderOriginal = !string.IsNullOrWhiteSpace(sender?.ExternalEmail) ? sender!.ExternalEmail! : request.SenderEmail;

            // Create email record
            var email = new Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = senderOriginal,
                RecipientEmail = request.RecipientEmail, // Store the actual recipient email from request
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

            // External SMTP delivery (automatic when recipient has configuration)
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
                // Use automatic decryption detection instead of relying on stored encryption method
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
            var emailEntities = await _context.Emails
                .Where(e => e.SenderEmail == userEmail)
                .OrderByDescending(e => e.SentAt)
                .ToListAsync();

            var emails = new List<object>(emailEntities.Count);
            foreach (var e in emailEntities)
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
                    e.IsRead
                });
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

    private static async Task<string> EncryptBodyAsync(string plaintext)
    {
        // Call OTP encrypt API and return JSON envelope string to store in DB Body
        try
        {
            var req = new OtpEncryptRequest(plaintext);
            using var response = await _http.PostAsJsonAsync($"{OtpBaseUrl}/api/otp/encrypt", req, _jsonOptions);
            response.EnsureSuccessStatusCode();
            var res = await response.Content.ReadFromJsonAsync<OtpEncryptResponse>(_jsonOptions);
            if (res == null || string.IsNullOrWhiteSpace(res.key_id) || string.IsNullOrWhiteSpace(res.ciphertext_b64url))
            {
                throw new InvalidOperationException("Invalid encrypt response");
            }
            var envelope = new BodyEnvelope(res.key_id, res.ciphertext_b64url);
            return JsonSerializer.Serialize(envelope, _jsonOptions);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Encryption service failed: {ex.Message}");
        }
    }

    private bool IsAlreadyEncrypted(string data, string method)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(data)) return false;
            var trimmed = data.Trim();
            // Check if it's a JSON string that looks like an encryption envelope
            if (trimmed.StartsWith("{") && trimmed.EndsWith("}"))
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(trimmed);
                
                // Check for AES envelope format
                if (string.Equals(method, "AES", StringComparison.OrdinalIgnoreCase))
                {
                    // Pascal/camel case envelope
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
                    // snake_case envelope from server2.py
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
                
                // Check for OTP envelope format
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
            return body; // fail open to avoid breaking inbox
        }
    }

    private async Task<string> TryDecryptBodyAsync(string body)
    {
        // Try to detect encryption type and decrypt accordingly
        try
        {
            _logger.LogInformation("Attempting to decrypt body: {Body}", body);
            
            // Check if it's AES envelope format FIRST (more specific)
            if (TryParseAESEnvelope(body, out var aesEnvelope))
            {
                _logger.LogInformation("Detected AES envelope, decrypting with AES API");
                return await DecryptAESAsync(aesEnvelope);
            }

            // Check if it's PQC envelope format
            if (TryParsePQCEnvelope(body, out var pqcEnvelope))
            {
                _logger.LogInformation("Detected PQC envelope, decrypting with PQC");
                return await DecryptPQCAsync(pqcEnvelope);
            }

            // Check if it's OTP envelope format (original format) - LAST
            if (TryParseEnvelope(body, out var otpEnvelope))
            {
                _logger.LogInformation("Detected OTP envelope, decrypting with OTP API");
                return await DecryptOTPAsync(otpEnvelope);
            }

            // If none of the above, return as-is (plain text)
            _logger.LogInformation("No encryption envelope detected, returning as plain text");
            return body;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to decrypt body, returning original");
            return body; // fail open to avoid breaking inbox
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
            _logger.LogInformation("Calling AES decrypt API with key_id: {KeyId}", envelope.KeyId);
            _logger.LogInformation("AES envelope details - KeyId: {KeyId}, IvHex: {IvHex}, CiphertextHex: {CiphertextHex}, TagHex: {TagHex}, AadHex: {AadHex}", 
                envelope.KeyId, envelope.IvHex, envelope.CiphertextHex, envelope.TagHex, envelope.AadHex);
            
            var req = new
            {
                key_id = envelope.KeyId,
                iv_hex = envelope.IvHex,
                ciphertext_hex = envelope.CiphertextHex,
                tag_hex = envelope.TagHex,
                aad_hex = envelope.AadHex
            };
            
            _logger.LogInformation("Sending AES decrypt request to: http://aes-server:8081/api/gcm/decrypt");
            using var response = await _http.PostAsJsonAsync("http://aes-server:8081/api/gcm/decrypt", req);
            
            _logger.LogInformation("AES decrypt API response status: {StatusCode}", response.StatusCode);
            
            if (response.IsSuccessStatusCode)
            {
                var decryptedBytes = await response.Content.ReadAsByteArrayAsync();
                _logger.LogInformation("AES decryption successful, decrypted {BytesCount} bytes", decryptedBytes.Length);
                return Encoding.UTF8.GetString(decryptedBytes);
            }
            
            var errorContent = await response.Content.ReadAsStringAsync();
            _logger.LogError("AES decrypt API returned status: {StatusCode}, content: {ErrorContent}", response.StatusCode, errorContent);
            return $"AES decryption failed: {response.StatusCode} - {errorContent}";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AES decryption failed with exception");
            return $"AES decryption failed: {ex.Message}";
        }
    }

    private async Task<string> DecryptPQCAsync(PQCEnvelope envelope)
    {
        try
        {
            _logger.LogInformation("Attempting PQC decryption");
            
            // For now, return the original encrypted data as JSON string
            // This allows the frontend to handle the decryption
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
            if (parsed == null)
            {
                _logger.LogInformation("TryParseAESEnvelope: Parsed result is null");
                return false;
            }
            
            _logger.LogInformation($"TryParseAESEnvelope: Parsed - KeyId: {parsed.KeyId}, IvHex: {parsed.IvHex}, CiphertextHex: {parsed.CiphertextHex}, TagHex: {parsed.TagHex}, Algorithm: {parsed.Algorithm}");
            
            if (string.IsNullOrWhiteSpace(parsed.KeyId) || string.IsNullOrWhiteSpace(parsed.CiphertextHex))
            {
                _logger.LogInformation("TryParseAESEnvelope: KeyId or CiphertextHex is empty");
                return false;
            }
            
            // Additional check: ensure it has AES-specific fields that OTP doesn't have
            if (string.IsNullOrWhiteSpace(parsed.IvHex) || string.IsNullOrWhiteSpace(parsed.TagHex))
            {
                _logger.LogInformation("TryParseAESEnvelope: IvHex or TagHex is empty");
                return false;
            }
            
            // Check if it has the Algorithm field (AES-specific)
            if (!string.IsNullOrWhiteSpace(parsed.Algorithm) && parsed.Algorithm.Contains("AES"))
            {
                _logger.LogInformation("TryParseAESEnvelope: Success - Algorithm field contains AES");
                envelope = parsed;
                return true;
            }
            
            // Even without Algorithm field, if it has all AES-specific fields, it's likely AES
            _logger.LogInformation("TryParseAESEnvelope: Success - All AES fields present");
            envelope = parsed;
            return true;
        }
        catch (Exception ex)
        {
            // Log the exception for debugging
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
                var fileName = item.ContainsKey("fileName") ? item["fileName"]?.ToString() : null;
                var contentType = item.ContainsKey("contentType") ? item["contentType"]?.ToString() : null;
                var envelope = item.ContainsKey("envelope") ? item["envelope"]?.ToString() : null;
                if (string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(contentType) || string.IsNullOrWhiteSpace(envelope))
                {
                    continue;
                }
                var decrypted = await TryDecryptBodyAsync(envelope);
                // decrypted is base64 content text
                result.Add(new { fileName, contentType, contentBase64 = decrypted });
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
            // Resolve auth secret: prefer stored encrypted app password for SENDER
            var sender = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.SenderEmail);
            string? smtpPassword = null;
            string? senderExternalEmail = null;
            if (sender != null && !string.IsNullOrWhiteSpace(sender.AppPasswordHash))
            {
                try { smtpPassword = QuMail.EmailProtocol.Services.SecretProtector.Decrypt(sender.AppPasswordHash); } catch { smtpPassword = null; }
                senderExternalEmail = sender.ExternalEmail;
            }
            if (string.IsNullOrWhiteSpace(smtpPassword) || string.IsNullOrWhiteSpace(senderExternalEmail)) return; // cannot send externally without credentials
            // Gmail/Yahoo app passwords are 16 chars without spaces; strip any spaces before use
            smtpPassword = smtpPassword!.Replace(" ", string.Empty);

            // Determine provider based on SENDER settings (not recipient)
            var providerKey = !string.IsNullOrWhiteSpace(sender?.EmailProvider) ? sender!.EmailProvider! : "gmail";
            if (!EmailProviderDefaults.DefaultProviders.TryGetValue(providerKey, out var provider))
            {
                provider = EmailProviderDefaults.DefaultProviders["gmail"]; // fallback
            }
            var smtp = provider.Smtp;

            // Resolve external recipient address
            var externalRecipient = !string.IsNullOrWhiteSpace(recipient.ExternalEmail) ? recipient.ExternalEmail! : recipient.Email;

            // Build external message: keep body as encrypted envelope JSON to avoid leaking plaintext
            var mail = new MailMessage
            {
                From = new MailAddress(senderExternalEmail), // Use sender's external email
                Subject = subjectEnvelope,
                Body = bodyEnvelope,
                IsBodyHtml = false
            };
            mail.To.Add(new MailAddress(externalRecipient));

            // Try STARTTLS 587 first, then implicit SSL 465 as fallback (some providers require 465)
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
                // Gmail fallback to implicit SSL 465
                await TrySendAsync(smtp.Host, 465, true);
            }
        }
        catch
        {
            // Fail quietly for external delivery so app send succeeds
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

    // Encryption method implementations
    private async Task<string?> EncryptAttachmentsOTPAsync(List<SendAttachment>? attachments)
    {
        if (attachments == null || attachments.Count == 0) return null;
        
        var encrypted = new List<object>(attachments.Count);
        foreach (var a in attachments)
        {
            var bytes = Convert.FromBase64String(a.ContentBase64);
            var contentText = Convert.ToBase64String(bytes);
            var envelope = await EncryptBodyAsync(contentText);
            encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
        }
        return JsonSerializer.Serialize(encrypted, _jsonOptions);
    }

    private async Task<EncryptionResult> EncryptWithAESAsync(string subject, string body, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with AES-GCM via server2.py");
        
        // Encrypt subject and body with AES
        var subjectEnvelope = await EncryptWithAESGCMAsync(subject);
        var bodyEnvelope = await EncryptWithAESGCMAsync(body);
        
        // Encrypt attachments
        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var bytes = Convert.FromBase64String(a.ContentBase64);
                var contentText = Convert.ToBase64String(bytes);
                var envelope = await EncryptWithAESGCMAsync(contentText);
                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }
        
        return new EncryptionResult { SubjectEnvelope = subjectEnvelope, BodyEnvelope = bodyEnvelope, AttachmentsJson = attachmentsJson };
    }

    private async Task<EncryptionResult> EncryptWithPQC2LayerAsync(string subject, string body, string recipientPublicKey, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with PQC 2-layer (Kyber-512 + OTP)");
        
        // Encrypt subject and body with PQC 2-layer
        var subjectEnvelope = await EncryptSingleWithPQC2LayerAsync(subject, recipientPublicKey);
        var bodyEnvelope = await EncryptSingleWithPQC2LayerAsync(body, recipientPublicKey);
        
        // Encrypt attachments
        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var bytes = Convert.FromBase64String(a.ContentBase64);
                var contentText = Convert.ToBase64String(bytes);
                var envelope = await EncryptSingleWithPQC2LayerAsync(contentText, recipientPublicKey);
                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }
        
        return new EncryptionResult { SubjectEnvelope = subjectEnvelope, BodyEnvelope = bodyEnvelope, AttachmentsJson = attachmentsJson };
    }

    private async Task<EncryptionResult> EncryptWithPQC3LayerAsync(string subject, string body, string recipientPublicKey, List<SendAttachment>? attachments)
    {
        _logger.LogInformation("Encrypting with PQC 3-layer (Kyber-1024 + AES-256 + OTP)");
        
        // Encrypt subject and body with PQC 3-layer
        var subjectEnvelope = await EncryptSingleWithPQC3LayerAsync(subject, recipientPublicKey);
        var bodyEnvelope = await EncryptSingleWithPQC3LayerAsync(body, recipientPublicKey);
        
        // Encrypt attachments
        string? attachmentsJson = null;
        if (attachments != null && attachments.Count > 0)
        {
            var encrypted = new List<object>(attachments.Count);
            foreach (var a in attachments)
            {
                var bytes = Convert.FromBase64String(a.ContentBase64);
                var contentText = Convert.ToBase64String(bytes);
                var envelope = await EncryptSingleWithPQC3LayerAsync(contentText, recipientPublicKey);
                encrypted.Add(new { fileName = a.FileName, contentType = a.ContentType, envelope });
            }
            attachmentsJson = JsonSerializer.Serialize(encrypted, _jsonOptions);
        }
        
        return new EncryptionResult { SubjectEnvelope = subjectEnvelope, BodyEnvelope = bodyEnvelope, AttachmentsJson = attachmentsJson };
    }

    private async Task<string> EncryptWithAESGCMAsync(string plaintext)
    {
        try
        {
            _logger.LogInformation("Starting AES-GCM encryption for plaintext: {Plaintext}", plaintext);
            
            var requestBody = new { plaintext = plaintext };
            _logger.LogInformation("Sending request to AES server: http://aes-server:8081/api/gcm/encrypt");
            
            var response = await _http.PostAsJsonAsync("http://aes-server:8081/api/gcm/encrypt", requestBody);
            
            _logger.LogInformation("AES server response status: {StatusCode}", response.StatusCode);
            
            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogError($"AES-GCM encryption failed: {response.StatusCode} - {errorContent}");
                throw new Exception($"AES-GCM encryption failed: {response.StatusCode} - {errorContent}");
            }
            
            var result = await response.Content.ReadFromJsonAsync<AESEncryptionResult>();
            if (result == null) 
            {
                _logger.LogError("Failed to parse AES encryption response - result is null");
                throw new Exception("Failed to parse AES encryption response - result is null");
            }
            
            _logger.LogInformation("AES encryption successful - KeyId: {KeyId}, IvHex: {IvHex}, CiphertextHex: {CiphertextHex}, TagHex: {TagHex}", 
                result.KeyId, result.IvHex, result.CiphertextHex, result.TagHex);
            
            // Store AES envelope in proper format for decryption
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
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AES-GCM encryption failed for plaintext: {Plaintext}", plaintext);
            throw;
        }
    }

    private async Task<string> EncryptSingleWithPQC2LayerAsync(string plaintext, string recipientPublicKey)
    {
        try
        {
            // Use the injected PQC service directly
            var encrypted = _pqcEmailService.EncryptEmail(plaintext, recipientPublicKey);
            
            // Store PQC envelope
            var envelope = new
            {
                encryptedBody = encrypted.EncryptedBody,
                pqcCiphertext = encrypted.PQCCiphertext,
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
            // Use the injected enhanced PQC service directly
            var encrypted = _hybridEncryption.Encrypt(
                plaintext, 
                recipientPublicKey, 
                Level3EnhancedPQC.SecurityLevel.Kyber512, 
                useAES: true);
            
            // Store PQC envelope
            var envelope = new
            {
                encryptedBody = encrypted.EncryptedBody,
                pqcCiphertext = encrypted.PQCCiphertext,
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
    public string EncryptionMethod { get; set; } = "OTP"; // OTP, AES, PQC_2_LAYER, PQC_3_LAYER
    public string? RecipientPublicKey { get; set; } // Required for PQC methods
}
public class SendAttachment
{
    public string FileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = "application/octet-stream";
    public string ContentBase64 { get; set; } = string.Empty; // raw content, base64
}

public class ValidateUserRequest
{
    public string Email { get; set; } = string.Empty;
}

// Result classes for encryption methods
public class EncryptionResult
{
    public string SubjectEnvelope { get; set; } = string.Empty;
    public string BodyEnvelope { get; set; } = string.Empty;
    public string? AttachmentsJson { get; set; }
}

public class AESEncryptionResult
{
    public string KeyId { get; set; } = string.Empty;
    public string IvHex { get; set; } = string.Empty;
    public string CiphertextHex { get; set; } = string.Empty;
    public string TagHex { get; set; } = string.Empty;
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

// Envelope classes for different encryption types
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
