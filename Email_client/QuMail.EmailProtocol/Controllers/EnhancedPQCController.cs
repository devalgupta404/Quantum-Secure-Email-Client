using Microsoft.AspNetCore.Mvc;
using QuMail.EmailProtocol.Services;
using QuMail.EmailProtocol.Data;
using Microsoft.EntityFrameworkCore;

namespace QuMail.EmailProtocol.Controllers;

/// <summary>
/// Enhanced PQC Controller with multiple security levels
/// Supports: Kyber-512, Kyber-1024, Classic McEliece
/// With optional AES-256 middle layer
/// </summary>
[ApiController]
[Route("api/pqc/v2")]
public class EnhancedPQCController : ControllerBase
{
    private readonly Level3EnhancedPQC _enhancedPQC;
    private readonly Level3HybridEncryption _hybridEncryption;
    private readonly AuthDbContext _context;

    public EnhancedPQCController(
        Level3EnhancedPQC enhancedPQC,
        Level3HybridEncryption hybridEncryption,
        AuthDbContext context)
    {
        _enhancedPQC = enhancedPQC ?? throw new ArgumentNullException(nameof(enhancedPQC));
        _hybridEncryption = hybridEncryption ?? throw new ArgumentNullException(nameof(hybridEncryption));
        _context = context ?? throw new ArgumentNullException(nameof(context));
    }

    /// <summary>
    /// Generate PQC key pair at specified security level
    /// POST /api/pqc/v2/generate-keypair?level=Kyber1024
    /// </summary>
    [HttpPost("generate-keypair")]
    public IActionResult GenerateKeyPair([FromQuery] string level = "Kyber512")
    {
        try
        {
            if (!Enum.TryParse<Level3EnhancedPQC.SecurityLevel>(level, true, out var securityLevel))
            {
                return BadRequest(new
                {
                    success = false,
                    message = $"Invalid security level. Valid options: Kyber512, Kyber1024, McEliece"
                });
            }

            var keyPair = _enhancedPQC.GenerateKeyPair(securityLevel);
            var info = _enhancedPQC.GetAlgorithmInfo(securityLevel);

            return Ok(new
            {
                success = true,
                message = $"PQC key pair generated successfully with {level}",
                data = new
                {
                    publicKey = keyPair.PublicKey,
                    privateKey = keyPair.PrivateKey,
                    algorithm = keyPair.Algorithm,
                    securityLevel = level,
                    generatedAt = keyPair.GeneratedAt,
                    keyInfo = info
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to generate key pair: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Encrypt with hybrid encryption (PQC + optional AES-256 + OTP)
    /// POST /api/pqc/v2/encrypt
    /// Body: {
    ///   "plaintext": "message",
    ///   "recipientPublicKey": "base64...",
    ///   "securityLevel": "Kyber1024",
    ///   "useAES": true
    /// }
    /// </summary>
    [HttpPost("encrypt")]
    public IActionResult Encrypt([FromBody] EnhancedEncryptRequest request)
    {
        try
        {
            if (string.IsNullOrEmpty(request.Plaintext))
            {
                return BadRequest(new { success = false, message = "Plaintext cannot be empty" });
            }

            if (string.IsNullOrEmpty(request.RecipientPublicKey))
            {
                return BadRequest(new { success = false, message = "Recipient public key is required" });
            }

            if (!Enum.TryParse<Level3EnhancedPQC.SecurityLevel>(request.SecurityLevel, true, out var level))
            {
                level = Level3EnhancedPQC.SecurityLevel.Kyber512; // Default
            }

            var encrypted = _hybridEncryption.Encrypt(
                request.Plaintext,
                request.RecipientPublicKey,
                level,
                request.UseAES);

            return Ok(new
            {
                success = true,
                message = "Email encrypted successfully with enhanced PQC",
                data = new
                {
                    encryptedBody = encrypted.EncryptedBody,
                    pqcCiphertext = encrypted.PQCCiphertext,
                    algorithm = encrypted.Algorithm,
                    securityLevel = encrypted.SecurityLevel,
                    useAES = encrypted.UseAES,
                    keyId = encrypted.KeyId,
                    encryptedAt = encrypted.EncryptedAt,
                    layers = encrypted.UseAES ? "PQC + AES-256-GCM + OTP" : "PQC + OTP"
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to encrypt: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Decrypt hybrid encrypted email
    /// POST /api/pqc/v2/decrypt
    /// </summary>
    [HttpPost("decrypt")]
    public IActionResult Decrypt([FromBody] EnhancedDecryptRequest request)
    {
        try
        {
            if (string.IsNullOrEmpty(request.EncryptedBody) ||
                string.IsNullOrEmpty(request.PQCCiphertext) ||
                string.IsNullOrEmpty(request.PrivateKey))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Missing required parameters"
                });
            }

            var decrypted = _hybridEncryption.Decrypt(
                request.EncryptedBody,
                request.PQCCiphertext,
                request.EncryptedKeyId,
                request.PrivateKey,
                request.Algorithm,
                request.UsedAES);

            return Ok(new
            {
                success = true,
                message = "Email decrypted successfully",
                data = new
                {
                    plaintext = decrypted
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to decrypt: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Get information about all security levels
    /// GET /api/pqc/v2/info
    /// </summary>
    [HttpGet("info")]
    public IActionResult GetInfo([FromQuery] string? level = null)
    {
        try
        {
            if (string.IsNullOrEmpty(level))
            {
                // Return info for all levels
                var allLevels = new[]
                {
                    _enhancedPQC.GetAlgorithmInfo(Level3EnhancedPQC.SecurityLevel.Kyber512),
                    _enhancedPQC.GetAlgorithmInfo(Level3EnhancedPQC.SecurityLevel.Kyber1024),
                    _enhancedPQC.GetAlgorithmInfo(Level3EnhancedPQC.SecurityLevel.McEliece)
                };

                return Ok(new
                {
                    success = true,
                    data = new
                    {
                        levels = allLevels,
                        hybridOptions = new
                        {
                            aes256Supported = true,
                            otpSupported = true,
                            recommendedCombo = "PQC + AES-256-GCM + OTP (triple-layer)"
                        }
                    }
                });
            }
            else
            {
                if (!Enum.TryParse<Level3EnhancedPQC.SecurityLevel>(level, true, out var securityLevel))
                {
                    return BadRequest(new
                    {
                        success = false,
                        message = "Invalid security level"
                    });
                }

                var info = _enhancedPQC.GetAlgorithmInfo(securityLevel);
                return Ok(new
                {
                    success = true,
                    data = info
                });
            }
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to get info: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Send email with double-layer PQC encryption (Kyber-512 + OTP)
    /// POST /api/pqc/v2/send-double-layer
    /// Recommended for: Standard secure communication
    /// </summary>
    [HttpPost("send-double-layer")]
    public async Task<IActionResult> SendDoubleLayerEmail([FromBody] SendPQCEmailRequest request)
    {
        try
        {
            // Validate recipient exists
            var recipient = await _context.Users
                .FirstOrDefaultAsync(u => u.Email == request.RecipientEmail);

            if (recipient == null)
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Recipient email not found in our system"
                });
            }

            // Encrypt with Kyber-512 + OTP (double-layer)
            var encrypted = _hybridEncryption.Encrypt(
                request.Body,
                request.RecipientPublicKey,
                Level3EnhancedPQC.SecurityLevel.Kyber512,
                useAES: false);

            // Create envelope with PQC data
            var pqcEnvelope = new PQCEmailEnvelope
            {
                EncryptedBody = encrypted.EncryptedBody,
                PQCCiphertext = encrypted.PQCCiphertext,
                Algorithm = encrypted.Algorithm,
                SecurityLevel = encrypted.SecurityLevel,
                UseAES = encrypted.UseAES,
                KeyId = encrypted.KeyId
            };

            // Store in database (Body field contains the JSON envelope)
            var email = new QuMail.EmailProtocol.Models.Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = request.SenderEmail,
                RecipientEmail = request.RecipientEmail,
                Subject = request.Subject,
                Body = System.Text.Json.JsonSerializer.Serialize(pqcEnvelope),
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = "Email sent with double-layer PQC encryption (Kyber-512 + OTP)",
                emailId = email.Id,
                algorithm = encrypted.Algorithm,
                layers = "PQC + OTP"
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to send PQC email: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Send email with triple-layer PQC encryption (Kyber-1024 + AES-256 + OTP)
    /// POST /api/pqc/v2/send-triple-layer
    /// Recommended for: Maximum security communication
    /// </summary>
    [HttpPost("send-triple-layer")]
    public async Task<IActionResult> SendTripleLayerEmail([FromBody] SendPQCEmailRequest request)
    {
        try
        {
            // Validate recipient exists
            var recipient = await _context.Users
                .FirstOrDefaultAsync(u => u.Email == request.RecipientEmail);

            if (recipient == null)
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Recipient email not found in our system"
                });
            }

            // Encrypt with Kyber-1024 + AES-256 + OTP (triple-layer)
            var encrypted = _hybridEncryption.Encrypt(
                request.Body,
                request.RecipientPublicKey,
                Level3EnhancedPQC.SecurityLevel.Kyber1024,
                useAES: true);

            // Create envelope with PQC data
            var pqcEnvelope = new PQCEmailEnvelope
            {
                EncryptedBody = encrypted.EncryptedBody,
                PQCCiphertext = encrypted.PQCCiphertext,
                Algorithm = encrypted.Algorithm,
                SecurityLevel = encrypted.SecurityLevel,
                UseAES = encrypted.UseAES,
                KeyId = encrypted.KeyId
            };

            // Store in database (Body field contains the JSON envelope)
            var email = new QuMail.EmailProtocol.Models.Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = request.SenderEmail,
                RecipientEmail = request.RecipientEmail,
                Subject = request.Subject,
                Body = System.Text.Json.JsonSerializer.Serialize(pqcEnvelope),
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = "Email sent with triple-layer PQC encryption (Kyber-1024 + AES-256 + OTP)",
                emailId = email.Id,
                algorithm = encrypted.Algorithm,
                layers = "PQC + AES-256-GCM + OTP"
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to send PQC email: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Test all security levels
    /// POST /api/pqc/v2/test-all
    /// </summary>
    [HttpPost("test-all")]
    public IActionResult TestAllLevels([FromBody] TestRequest request)
    {
        var testMessage = request.Message ?? "Test message for all PQC levels!";
        var results = new List<object>();

        foreach (var level in Enum.GetValues<Level3EnhancedPQC.SecurityLevel>())
        {
            try
            {
                // Generate keys
                var keyPair = _enhancedPQC.GenerateKeyPair(level);

                // Test without AES
                var encrypted1 = _hybridEncryption.Encrypt(testMessage, keyPair.PublicKey, level, useAES: false);
                var decrypted1 = _hybridEncryption.Decrypt(
                    encrypted1.EncryptedBody,
                    encrypted1.PQCCiphertext,
                    encrypted1.EncryptedKeyId,
                    keyPair.PrivateKey,
                    encrypted1.Algorithm,
                    false);

                // Test with AES
                var encrypted2 = _hybridEncryption.Encrypt(testMessage, keyPair.PublicKey, level, useAES: true);
                var decrypted2 = _hybridEncryption.Decrypt(
                    encrypted2.EncryptedBody,
                    encrypted2.PQCCiphertext,
                    encrypted2.EncryptedKeyId,
                    keyPair.PrivateKey,
                    encrypted2.Algorithm,
                    true);

                results.Add(new
                {
                    level = level.ToString(),
                    algorithm = keyPair.Algorithm,
                    withoutAES = new
                    {
                        success = decrypted1 == testMessage,
                        layers = "PQC + OTP"
                    },
                    withAES = new
                    {
                        success = decrypted2 == testMessage,
                        layers = "PQC + AES-256 + OTP"
                    }
                });
            }
            catch (Exception ex)
            {
                results.Add(new
                {
                    level = level.ToString(),
                    error = ex.Message
                });
            }
        }

        return Ok(new
        {
            success = true,
            message = "Tested all security levels",
            data = results
        });
    }
}

// Request models
public class EnhancedEncryptRequest
{
    public string Plaintext { get; set; } = string.Empty;
    public string RecipientPublicKey { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = "Kyber512";
    public bool UseAES { get; set; } = true;
}

public class EnhancedDecryptRequest
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string EncryptedKeyId { get; set; } = string.Empty; // NEW: Required for KeyManager
    public string PrivateKey { get; set; } = string.Empty;
    public string Algorithm { get; set; } = string.Empty;
    public bool UsedAES { get; set; } = true;
}

public class TestRequest
{
    public string? Message { get; set; }
}

public class SendPQCEmailRequest
{
    public string SenderEmail { get; set; } = string.Empty;
    public string RecipientEmail { get; set; } = string.Empty;
    public string RecipientPublicKey { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
}

public class PQCEmailEnvelope
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string Algorithm { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = string.Empty;
    public bool UseAES { get; set; }
    public string KeyId { get; set; } = string.Empty;
}
