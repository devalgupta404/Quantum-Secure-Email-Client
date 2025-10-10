using QuMail.EmailProtocol.Interfaces;
using System.Text;

namespace QuMail.EmailProtocol.Services;

/// <summary>
/// Level 3 PQC Email Service with KeyManager Integration (CORRECTED)
/// Combines CRYSTALS-Kyber post-quantum key exchange with KeyManager for proper key management
///
/// FLOW (CORRECTED):
/// ENCRYPTION:
/// 1. Generate keyId and get quantum key from KeyManager
/// 2. Encrypt keyId using PQC (Kyber) shared secret
/// 3. Encrypt email body using quantum key from KeyManager
/// 4. Send: encrypted body + PQC ciphertext + encrypted keyId
///
/// DECRYPTION:
/// 1. Receiver uses their private key to decapsulate PQC ciphertext → recovers shared secret
/// 2. Decrypt keyId using PQC shared secret
/// 3. Fetch same quantum key from KeyManager using keyId
/// 4. Decrypt email body using quantum key
/// </summary>
public class Level3PQCEmailService
{
    private readonly Level3KyberPQC _kyberPQC;
    private readonly IOneTimePadEngine _otpEngine;
    private readonly IQuantumKeyManager _keyManager;

    public Level3PQCEmailService(
        Level3KyberPQC kyberPQC,
        IOneTimePadEngine otpEngine,
        IQuantumKeyManager keyManager)
    {
        _kyberPQC = kyberPQC ?? throw new ArgumentNullException(nameof(kyberPQC));
        _otpEngine = otpEngine ?? throw new ArgumentNullException(nameof(otpEngine));
        _keyManager = keyManager ?? throw new ArgumentNullException(nameof(keyManager));
    }

    /// <summary>
    /// Encrypts an email using PQC + OTP with KeyManager (CORRECTED)
    /// </summary>
    /// <param name="plaintext">Email body to encrypt</param>
    /// <param name="recipientPublicKey">Recipient's PQC public key (Base64)</param>
    /// <returns>Encrypted email result with ciphertext and PQC data</returns>
    public async Task<PQCEncryptedEmail> EncryptEmailAsync(string plaintext, string recipientPublicKey)
    {
        try
        {
            // Step 1: Validate recipient public key
            if (!_kyberPQC.ValidatePublicKey(recipientPublicKey))
            {
                throw new ArgumentException("Invalid recipient public key", nameof(recipientPublicKey));
            }

            var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

            // Step 2: Generate keyId and get quantum key from KeyManager
            var keyId = GenerateKeyId();
            var quantumKey = await _keyManager.GetKeyAsync(keyId, plaintextBytes.Length);

            // Step 3: Perform Kyber encapsulation to get shared secret
            var encapsulation = _kyberPQC.Encapsulate(recipientPublicKey);
            var pqcSharedSecret = Convert.FromBase64String(encapsulation.SharedSecret);

            // Step 4: Encrypt the keyId using PQC shared secret (so receiver can retrieve same key)
            var keyIdBytes = Encoding.UTF8.GetBytes(keyId);
            var encryptedKeyId = XorBytes(keyIdBytes, pqcSharedSecret.Take(keyIdBytes.Length).ToArray());

            // Step 5: Encrypt email body using quantum key from KeyManager
            var encryptionResult = _otpEngine.Encrypt(plaintextBytes, quantumKey.Data.Take(plaintextBytes.Length).ToArray(), keyId);

            // Step 6: Mark key as used
            await _keyManager.MarkKeyAsUsedAsync(keyId, plaintextBytes.Length);

            // Step 7: Return encrypted email with PQC metadata
            return new PQCEncryptedEmail
            {
                EncryptedBody = Convert.ToBase64String(encryptionResult.EncryptedData),
                PQCCiphertext = encapsulation.Ciphertext, // Kyber ciphertext for receiver
                EncryptedKeyId = Convert.ToBase64String(encryptedKeyId), // NEW: encrypted keyId
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

    // Keep synchronous version for backward compatibility
    public PQCEncryptedEmail EncryptEmail(string plaintext, string recipientPublicKey)
    {
        return EncryptEmailAsync(plaintext, recipientPublicKey).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Decrypts an email that was encrypted with PQC + OTP using KeyManager (CORRECTED)
    /// </summary>
    /// <param name="encryptedBody">Base64-encoded encrypted email body</param>
    /// <param name="pqcCiphertext">Base64-encoded Kyber ciphertext</param>
    /// <param name="encryptedKeyId">Base64-encoded encrypted keyId</param>
    /// <param name="privateKey">Recipient's private key (Base64)</param>
    /// <returns>Decrypted email plaintext</returns>
    public async Task<string> DecryptEmailAsync(string encryptedBody, string pqcCiphertext, string encryptedKeyId, string privateKey)
    {
        try
        {
            // Step 1: Perform Kyber decapsulation to recover shared secret
            var sharedSecretBase64 = _kyberPQC.Decapsulate(pqcCiphertext, privateKey);
            var pqcSharedSecret = Convert.FromBase64String(sharedSecretBase64);

            // Step 2: Decrypt the keyId using PQC shared secret
            var encryptedKeyIdBytes = Convert.FromBase64String(encryptedKeyId);
            var keyIdBytes = XorBytes(encryptedKeyIdBytes, pqcSharedSecret.Take(encryptedKeyIdBytes.Length).ToArray());
            var keyId = Encoding.UTF8.GetString(keyIdBytes);

            // Step 3: Retrieve the quantum key from KeyManager using keyId
            var encryptedBytes = Convert.FromBase64String(encryptedBody);
            var quantumKey = await _keyManager.GetKeyAsync(keyId, encryptedBytes.Length);

            // Step 4: Decrypt using quantum key from KeyManager
            var decryptedBytes = _otpEngine.Decrypt(encryptedBytes, quantumKey.Data.Take(encryptedBytes.Length).ToArray());

            // Step 5: Convert back to string
            return Encoding.UTF8.GetString(decryptedBytes);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to decrypt email with PQC", ex);
        }
    }

    // Keep synchronous version for backward compatibility
    public string DecryptEmail(string encryptedBody, string pqcCiphertext, string encryptedKeyId, string privateKey)
    {
        return DecryptEmailAsync(encryptedBody, pqcCiphertext, encryptedKeyId, privateKey).GetAwaiter().GetResult();
    }

    // Helper method for XOR operation
    private byte[] XorBytes(byte[] data, byte[] key)
    {
        var result = new byte[data.Length];
        for (int i = 0; i < data.Length; i++)
        {
            result[i] = (byte)(data[i] ^ key[i]);
        }
        return result;
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
    /// Encrypted keyId (Base64) - receiver decrypts this to get keyId for KeyManager
    /// </summary>
    public string EncryptedKeyId { get; set; } = string.Empty;

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
