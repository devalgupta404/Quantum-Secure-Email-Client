using QuMail.EmailProtocol.Interfaces;
using System.Text;

namespace QuMail.EmailProtocol.Services;

/// <summary>
/// Level 3 PQC Email Service
/// Combines CRYSTALS-Kyber post-quantum key exchange with existing OTP encryption
///
/// FLOW:
/// 1. Sender performs Kyber encapsulation with recipient's public key → gets shared secret + ciphertext
/// 2. Shared secret (32 bytes) is used as the OTP key to encrypt the email body
/// 3. Encrypted email + PQC ciphertext are sent together
/// 4. Receiver uses their private key to decapsulate → recovers shared secret
/// 5. Shared secret decrypts the email using OTP
/// </summary>
public class Level3PQCEmailService
{
    private readonly Level3KyberPQC _kyberPQC;
    private readonly IOneTimePadEngine _otpEngine;

    public Level3PQCEmailService(Level3KyberPQC kyberPQC, IOneTimePadEngine otpEngine)
    {
        _kyberPQC = kyberPQC ?? throw new ArgumentNullException(nameof(kyberPQC));
        _otpEngine = otpEngine ?? throw new ArgumentNullException(nameof(otpEngine));
    }

    /// <summary>
    /// Encrypts an email using PQC + OTP hybrid encryption
    /// </summary>
    /// <param name="plaintext">Email body to encrypt</param>
    /// <param name="recipientPublicKey">Recipient's PQC public key (Base64)</param>
    /// <returns>Encrypted email result with ciphertext and PQC data</returns>
    public PQCEncryptedEmail EncryptEmail(string plaintext, string recipientPublicKey)
    {
        try
        {
            // Step 1: Validate recipient public key
            if (!_kyberPQC.ValidatePublicKey(recipientPublicKey))
            {
                throw new ArgumentException("Invalid recipient public key", nameof(recipientPublicKey));
            }

            // Step 2: Perform Kyber encapsulation to get shared secret + ciphertext
            var encapsulation = _kyberPQC.Encapsulate(recipientPublicKey);

            // Step 3: Convert shared secret to bytes (this will be our OTP key)
            var otpKey = Convert.FromBase64String(encapsulation.SharedSecret);

            // Step 4: Convert plaintext to bytes
            var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

            // Step 5: Expand OTP key to match plaintext length if needed
            var expandedKey = ExpandKey(otpKey, plaintextBytes.Length);

            // Step 6: Encrypt using existing OTP engine (XOR encryption)
            var keyId = GenerateKeyId();
            var encryptionResult = _otpEngine.Encrypt(plaintextBytes, expandedKey, keyId);

            // Step 7: Return encrypted email with PQC metadata
            return new PQCEncryptedEmail
            {
                EncryptedBody = Convert.ToBase64String(encryptionResult.EncryptedData),
                PQCCiphertext = encapsulation.Ciphertext, // Kyber ciphertext for receiver
                Algorithm = "Kyber512-OTP",
                KeyId = keyId,
                EncryptedAt = DateTime.UtcNow
            };
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to encrypt email with PQC", ex);
        }
    }

    /// <summary>
    /// Decrypts an email that was encrypted with PQC + OTP
    /// </summary>
    /// <param name="encryptedBody">Base64-encoded encrypted email body</param>
    /// <param name="pqcCiphertext">Base64-encoded Kyber ciphertext</param>
    /// <param name="privateKey">Recipient's private key (Base64)</param>
    /// <returns>Decrypted email plaintext</returns>
    public string DecryptEmail(string encryptedBody, string pqcCiphertext, string privateKey)
    {
        try
        {
            // Step 1: Perform Kyber decapsulation to recover shared secret
            var sharedSecretBase64 = _kyberPQC.Decapsulate(pqcCiphertext, privateKey);

            // Step 2: Convert shared secret to bytes (this is our OTP key)
            var otpKey = Convert.FromBase64String(sharedSecretBase64);

            // Step 3: Convert encrypted body to bytes
            var encryptedBytes = Convert.FromBase64String(encryptedBody);

            // Step 4: Expand OTP key to match ciphertext length
            var expandedKey = ExpandKey(otpKey, encryptedBytes.Length);

            // Step 5: Decrypt using existing OTP engine (XOR decryption)
            var decryptedBytes = _otpEngine.Decrypt(encryptedBytes, expandedKey);

            // Step 6: Convert back to string
            return Encoding.UTF8.GetString(decryptedBytes);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to decrypt email with PQC", ex);
        }
    }

    /// <summary>
    /// Expands a key to match the required length using a deterministic method
    /// This allows using the 32-byte shared secret for messages of any length
    /// </summary>
    /// <param name="key">Original key (32 bytes from Kyber)</param>
    /// <param name="requiredLength">Length needed for encryption</param>
    /// <returns>Expanded key of required length</returns>
    private byte[] ExpandKey(byte[] key, int requiredLength)
    {
        if (requiredLength <= key.Length)
        {
            return key.Take(requiredLength).ToArray();
        }

        // Use a deterministic key expansion algorithm
        // For production, consider using HKDF or similar KDF
        var expanded = new byte[requiredLength];
        var rounds = (requiredLength + key.Length - 1) / key.Length;

        using (var sha256 = System.Security.Cryptography.SHA256.Create())
        {
            var currentKey = key;
            var offset = 0;

            for (int round = 0; round < rounds; round++)
            {
                // Hash the current key with round number for uniqueness
                var input = currentKey.Concat(BitConverter.GetBytes(round)).ToArray();
                var hash = sha256.ComputeHash(input);

                var bytesToCopy = Math.Min(hash.Length, requiredLength - offset);
                Array.Copy(hash, 0, expanded, offset, bytesToCopy);
                offset += bytesToCopy;

                // Use hash as input for next round
                currentKey = hash;
            }
        }

        return expanded;
    }

    /// <summary>
    /// Generates a unique key ID for tracking
    /// </summary>
    private string GenerateKeyId()
    {
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var randomBytes = new byte[8];
        using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
        {
            rng.GetBytes(randomBytes);
        }
        return $"PQC-{timestamp}-{Convert.ToBase64String(randomBytes).Replace("/", "").Replace("+", "").Substring(0, 8)}";
    }

    /// <summary>
    /// Creates a formatted email body for non-PQC clients
    /// This is the fallback display for regular email clients
    /// </summary>
    public string FormatPQCEmail(PQCEncryptedEmail encrypted)
    {
        var sb = new StringBuilder();
        sb.AppendLine("=== QuMail Post-Quantum Encrypted Email ===");
        sb.AppendLine();
        sb.AppendLine("This email has been encrypted using CRYSTALS-Kyber post-quantum cryptography.");
        sb.AppendLine("To decrypt this message, you need QuMail client with your PQC private key.");
        sb.AppendLine();
        sb.AppendLine($"Algorithm: {encrypted.Algorithm}");
        sb.AppendLine($"Key ID: {encrypted.KeyId}");
        sb.AppendLine($"Encrypted At: {encrypted.EncryptedAt:yyyy-MM-dd HH:mm:ss} UTC");
        sb.AppendLine();
        sb.AppendLine("=== PQC Ciphertext (Kyber) ===");
        sb.AppendLine(encrypted.PQCCiphertext);
        sb.AppendLine();
        sb.AppendLine("=== Encrypted Email Body ===");
        sb.AppendLine(encrypted.EncryptedBody);
        sb.AppendLine();
        sb.AppendLine("=== End QuMail PQC Email ===");
        return sb.ToString();
    }
}

/// <summary>
/// Represents an email encrypted with PQC + OTP
/// </summary>
public class PQCEncryptedEmail
{
    /// <summary>
    /// OTP-encrypted email body (Base64)
    /// </summary>
    public string EncryptedBody { get; set; } = string.Empty;

    /// <summary>
    /// Kyber ciphertext containing encapsulated shared secret (Base64)
    /// This is what the receiver uses with their private key to decrypt
    /// </summary>
    public string PQCCiphertext { get; set; } = string.Empty;

    /// <summary>
    /// Algorithm identifier
    /// </summary>
    public string Algorithm { get; set; } = string.Empty;

    /// <summary>
    /// Unique key ID for tracking
    /// </summary>
    public string KeyId { get; set; } = string.Empty;

    /// <summary>
    /// Timestamp when email was encrypted
    /// </summary>
    public DateTime EncryptedAt { get; set; }
}
