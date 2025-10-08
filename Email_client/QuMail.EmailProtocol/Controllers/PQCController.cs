using Microsoft.AspNetCore.Mvc;
using QuMail.EmailProtocol.Services;
using QuMail.EmailProtocol.Data;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace QuMail.EmailProtocol.Controllers;

/// <summary>
/// API Controller for Level 3 Post-Quantum Cryptography operations
/// Provides endpoints for key generation, encryption, and decryption using CRYSTALS-Kyber
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class PQCController : ControllerBase
{
    private readonly Level3KyberPQC _kyberPQC;
    private readonly Level3PQCEmailService _pqcEmailService;
    private readonly AuthDbContext _context;

    public PQCController(
        Level3KyberPQC kyberPQC,
        Level3PQCEmailService pqcEmailService,
        AuthDbContext context)
    {
        _kyberPQC = kyberPQC ?? throw new ArgumentNullException(nameof(kyberPQC));
        _pqcEmailService = pqcEmailService ?? throw new ArgumentNullException(nameof(pqcEmailService));
        _context = context ?? throw new ArgumentNullException(nameof(context));
    }

    /// <summary>
    /// Generates a new PQC key pair for a user
    /// POST /api/pqc/generate-keypair
    /// </summary>
    [HttpPost("generate-keypair")]
    public IActionResult GenerateKeyPair()
    {
        try
        {
            var keyPair = _kyberPQC.GenerateKeyPair();

            return Ok(new
            {
                success = true,
                message = "PQC key pair generated successfully",
                data = new
                {
                    publicKey = keyPair.PublicKey,
                    privateKey = keyPair.PrivateKey,
                    algorithm = keyPair.Algorithm,
                    generatedAt = keyPair.GeneratedAt
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
    /// Encrypts an email using PQC
    /// POST /api/pqc/encrypt
    /// Body: { "plaintext": "email body", "recipientPublicKey": "base64..." }
    /// </summary>
    [HttpPost("encrypt")]
    public IActionResult EncryptEmail([FromBody] PQCEncryptRequest request)
    {
        try
        {
            if (string.IsNullOrEmpty(request.Plaintext))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Plaintext cannot be empty"
                });
            }

            if (string.IsNullOrEmpty(request.RecipientPublicKey))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Recipient public key is required"
                });
            }

            var encrypted = _pqcEmailService.EncryptEmail(request.Plaintext, request.RecipientPublicKey);

            return Ok(new
            {
                success = true,
                message = "Email encrypted successfully with PQC",
                data = new
                {
                    encryptedBody = encrypted.EncryptedBody,
                    pqcCiphertext = encrypted.PQCCiphertext,
                    algorithm = encrypted.Algorithm,
                    keyId = encrypted.KeyId,
                    encryptedAt = encrypted.EncryptedAt
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to encrypt email: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Decrypts an email that was encrypted with PQC
    /// POST /api/pqc/decrypt
    /// Body: { "encryptedBody": "base64...", "pqcCiphertext": "base64...", "privateKey": "base64..." }
    /// </summary>
    [HttpPost("decrypt")]
    public IActionResult DecryptEmail([FromBody] PQCDecryptRequest request)
    {
        try
        {
            if (string.IsNullOrEmpty(request.EncryptedBody))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Encrypted body cannot be empty"
                });
            }

            if (string.IsNullOrEmpty(request.PQCCiphertext))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "PQC ciphertext is required"
                });
            }

            if (string.IsNullOrEmpty(request.PrivateKey))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Private key is required"
                });
            }

            var decrypted = _pqcEmailService.DecryptEmail(
                request.EncryptedBody,
                request.PQCCiphertext,
                request.PrivateKey);

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
                message = $"Failed to decrypt email: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Sends an email with PQC encryption (Level 3)
    /// POST /api/pqc/send
    /// </summary>
    [HttpPost("send")]
    public async Task<IActionResult> SendPQCEmail([FromBody] SendPQCEmailRequest request)
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

            // Encrypt email with PQC
            var encrypted = _pqcEmailService.EncryptEmail(request.Body, request.RecipientPublicKey);

            // Create envelope with PQC data
            var pqcEnvelope = new PQCEmailEnvelope
            {
                EncryptedBody = encrypted.EncryptedBody,
                PQCCiphertext = encrypted.PQCCiphertext,
                Algorithm = encrypted.Algorithm,
                KeyId = encrypted.KeyId
            };

            // Store in database (Body field contains the JSON envelope)
            var email = new QuMail.EmailProtocol.Models.Email
            {
                Id = Guid.NewGuid(),
                SenderEmail = request.SenderEmail,
                RecipientEmail = request.RecipientEmail,
                Subject = request.Subject,
                Body = JsonSerializer.Serialize(pqcEnvelope),
                SentAt = DateTime.UtcNow,
                IsRead = false
            };

            _context.Emails.Add(email);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = "PQC-encrypted email sent successfully",
                emailId = email.Id,
                algorithm = encrypted.Algorithm
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
    /// Gets PQC algorithm information
    /// GET /api/pqc/info
    /// </summary>
    [HttpGet("info")]
    public IActionResult GetPQCInfo()
    {
        try
        {
            var info = _kyberPQC.GetPQCInfo();

            return Ok(new
            {
                success = true,
                data = info
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to get PQC info: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Validates a PQC public key
    /// POST /api/pqc/validate-key
    /// </summary>
    [HttpPost("validate-key")]
    public IActionResult ValidatePublicKey([FromBody] ValidateKeyRequest request)
    {
        try
        {
            var isValid = _kyberPQC.ValidatePublicKey(request.PublicKey);

            return Ok(new
            {
                success = true,
                isValid = isValid,
                message = isValid ? "Public key is valid" : "Public key is invalid"
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"Failed to validate key: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Test endpoint to verify PQC encryption/decryption flow
    /// POST /api/pqc/test
    /// </summary>
    [HttpPost("test")]
    public IActionResult TestPQC([FromBody] PQCTestRequest request)
    {
        try
        {
            var testMessage = request.Message ?? "Hello, Post-Quantum World!";

            // Generate key pair
            var keyPair = _kyberPQC.GenerateKeyPair();

            // Encrypt
            var encrypted = _pqcEmailService.EncryptEmail(testMessage, keyPair.PublicKey);

            // Decrypt
            var decrypted = _pqcEmailService.DecryptEmail(
                encrypted.EncryptedBody,
                encrypted.PQCCiphertext,
                keyPair.PrivateKey);

            var success = testMessage == decrypted;

            return Ok(new
            {
                success = success,
                message = success ? "PQC test passed!" : "PQC test failed!",
                data = new
                {
                    originalMessage = testMessage,
                    decryptedMessage = decrypted,
                    algorithm = encrypted.Algorithm,
                    publicKeySize = keyPair.PublicKey.Length,
                    privateKeySize = keyPair.PrivateKey.Length,
                    encryptedBodySize = encrypted.EncryptedBody.Length,
                    pqcCiphertextSize = encrypted.PQCCiphertext.Length
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new
            {
                success = false,
                message = $"PQC test failed: {ex.Message}",
                stackTrace = ex.StackTrace
            });
        }
    }
}

// Request/Response Models

public class PQCEncryptRequest
{
    public string Plaintext { get; set; } = string.Empty;
    public string RecipientPublicKey { get; set; } = string.Empty;
}

public class PQCDecryptRequest
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
}

public class ValidateKeyRequest
{
    public string PublicKey { get; set; } = string.Empty;
}

public class PQCTestRequest
{
    public string? Message { get; set; }
}
