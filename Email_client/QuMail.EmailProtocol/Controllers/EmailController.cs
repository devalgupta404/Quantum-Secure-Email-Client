using Microsoft.AspNetCore.Mvc;
using QuMail.EmailProtocol.Data;
using QuMail.EmailProtocol.Models;
using Microsoft.EntityFrameworkCore;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Net.Http;
using System.Net.Http.Json;

namespace QuMail.EmailProtocol.Controllers;

[ApiController]
[Route("api/[controller]")]
public class EmailController : ControllerBase
{
    private readonly AuthDbContext _context;
    private static readonly HttpClient _http = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(10)
    };
    private const string OtpBaseUrl = "http://127.0.0.1:8081"; // otp_api_test.py default

    public EmailController(AuthDbContext context)
    {
        _context = context;
    }

    [HttpPost("send")]
    public async Task<IActionResult> SendEmail([FromBody] SendEmailRequest request)
    {
        try
        {
            // Check if recipient exists
            var recipient = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.RecipientEmail);
            if (recipient == null)
            {
                return BadRequest(new { 
                    success = false, 
                    message = "Recipient email not found in our system" 
                });
            }

            // Encrypt body via OTP API (store envelope JSON in Body to avoid schema changes)
            var bodyEnvelope = await EncryptBodyAsync(request.Body);

            // Create email record
            var email = new Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = request.SenderEmail,
                RecipientEmail = request.RecipientEmail,
                Subject = request.Subject,
                Body = bodyEnvelope,
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            return Ok(new { 
                success = true, 
                message = "Email sent successfully",
                emailId = email.Id
            });
        }
        catch (Exception ex)
        {
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
                var decryptedBody = await TryDecryptBodyAsync(e.Body);
                emails.Add(new
                {
                    e.Id,
                    e.SenderEmail,
                    e.RecipientEmail,
                    e.Subject,
                    Body = decryptedBody,
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
                emails.Add(new
                {
                    e.Id,
                    e.SenderEmail,
                    e.RecipientEmail,
                    e.Subject,
                    Body = decryptedBody,
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

    private static bool TryParseEnvelope(string body, out BodyEnvelope envelope)
    {
        envelope = default!;
        if (string.IsNullOrWhiteSpace(body) || body.Length < 10) return false;
        try
        {
            var parsed = JsonSerializer.Deserialize<BodyEnvelope>(body, _jsonOptions);
            if (parsed == null || string.IsNullOrWhiteSpace(parsed.otp_key_id) || string.IsNullOrWhiteSpace(parsed.ciphertext_b64url))
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

    private static async Task<string> TryDecryptBodyAsync(string body)
    {
        if (!TryParseEnvelope(body, out var envelope))
        {
            return body; // not encrypted in our envelope format
        }

        try
        {
            var req = new OtpDecryptRequest(envelope.otp_key_id, envelope.ciphertext_b64url);
            using var response = await _http.PostAsJsonAsync($"{OtpBaseUrl}/api/otp/decrypt", req, _jsonOptions);
            response.EnsureSuccessStatusCode();
            var res = await response.Content.ReadFromJsonAsync<OtpDecryptResponse>(_jsonOptions);
            if (res == null)
            {
                return body; // fallback to original
            }
            if (!string.IsNullOrEmpty(res.text))
            {
                return res.text!;
            }
            if (!string.IsNullOrEmpty(res.plaintext_b64url))
            {
                try
                {
                    var bytes = Convert.FromBase64String(Base64UrlToBase64(res.plaintext_b64url!));
                    return Encoding.UTF8.GetString(bytes);
                }
                catch
                {
                    return body;
                }
            }
            return body;
        }
        catch
        {
            return body; // fail open to avoid breaking inbox
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
}

public class SendEmailRequest
{
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
}

public class ValidateUserRequest
{
    public string Email { get; set; } = string.Empty;
}
