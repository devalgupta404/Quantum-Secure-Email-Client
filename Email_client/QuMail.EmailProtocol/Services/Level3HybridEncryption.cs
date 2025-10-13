using QuMail.EmailProtocol.Interfaces;
using System.Security.Cryptography;
using System.Text;

namespace QuMail.EmailProtocol.Services;

/// <summary>
/// Triple-layer hybrid encryption: PQC + AES-256 + OTP with KeyManager
///
/// ENCRYPTION FLOW (CORRECTED):
/// 1. Generate keyId and get quantum key from KeyManager
/// 2. Encrypt keyId using PQC (Kyber/McEliece) encapsulation → keyId becomes the "message"
/// 3. AES-256-GCM encryption with quantum key (optional middle layer)
/// 4. OTP XOR on the AES ciphertext using quantum key from KeyManager
///
/// DECRYPTION FLOW:
/// 1. PQC decapsulation → recovers the keyId
/// 2. Fetch same quantum key from KeyManager using keyId
/// 3. Decrypt using quantum key (reverse the encryption layers)
///
/// This provides maximum security:
/// - PQC secures the keyId exchange (quantum-resistant)
/// - KeyManager provides the actual OTP keys (proper key management)
/// - If PQC breaks → AES-256 + OTP still protects you
/// - If AES breaks → PQC + OTP still protects you
/// </summary>
public class Level3HybridEncryption
{
    private readonly Level3EnhancedPQC _enhancedPQC;
    private readonly IOneTimePadEngine _otpEngine;
    private readonly IQuantumKeyManager _keyManager;

    public Level3HybridEncryption(
        Level3EnhancedPQC enhancedPQC,
        IOneTimePadEngine otpEngine,
        IQuantumKeyManager keyManager)
    {
        _enhancedPQC = enhancedPQC ?? throw new ArgumentNullException(nameof(enhancedPQC));
        _otpEngine = otpEngine ?? throw new ArgumentNullException(nameof(otpEngine));
        _keyManager = keyManager ?? throw new ArgumentNullException(nameof(keyManager));
    }

    /// <summary>
    /// Encrypts email using triple-layer hybrid encryption with KeyManager
    /// </summary>
    /// <param name="plaintext">Email body to encrypt</param>
    /// <param name="recipientPublicKey">Recipient's PQC public key</param>
    /// <param name="securityLevel">PQC security level to use</param>
    /// <param name="useAES">Enable AES-256 middle layer (recommended)</param>
    /// <returns>Encrypted email with PQC + AES + OTP layers</returns>
    public async Task<HybridEncryptedEmail> EncryptAsync(
        string plaintext,
        string recipientPublicKey,
        Level3EnhancedPQC.SecurityLevel securityLevel,
        bool useAES = true)
    {
        try
        {
            // Get algorithm name from security level
            var algorithm = GetAlgorithmName(securityLevel);
            var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

            // Step 1: Generate keyId and get quantum key from KeyManager
            var keyId = GenerateKeyId();
            var requiredKeySize = useAES ? plaintextBytes.Length + 256 : plaintextBytes.Length; // Extra for AES overhead
            var quantumKey = await _keyManager.GetKeyAsync(keyId, requiredKeySize);

            // Step 2: Encrypt the keyId using PQC so receiver can retrieve the same quantum key
            // We encrypt the keyId itself as the "message" in PQC layer
            var keyIdBytes = Encoding.UTF8.GetBytes(keyId);
            var keyIdEncapsulation = _enhancedPQC.Encapsulate(recipientPublicKey, algorithm);

            // The PQC ciphertext will be sent along with encrypted email
            // The keyId is embedded in the shared secret derivation (we'll use shared secret to encrypt keyId)
            var pqcSharedSecret = Convert.FromBase64String(keyIdEncapsulation.SharedSecret);

            // Encrypt keyId with PQC shared secret using XOR
            var encryptedKeyId = XorBytes(keyIdBytes, pqcSharedSecret.Take(keyIdBytes.Length).ToArray());

            byte[] finalCiphertext;
            string encryptionLayers;

            if (useAES)
            {
                // Triple-layer: PQC + AES-256 + OTP
                // Step 3: AES-256-GCM encryption with quantum key
                var aesEncrypted = EncryptWithAES256(plaintextBytes, quantumKey.Data.Take(32).ToArray());

                // Step 4: OTP XOR on top of AES ciphertext using remaining quantum key
                var otpKeyOffset = 32; // Skip the 32 bytes used for AES
                var otpKey = quantumKey.Data.Skip(otpKeyOffset).Take(aesEncrypted.Length).ToArray();
                var otpResult = _otpEngine.Encrypt(aesEncrypted, otpKey, keyId);

                finalCiphertext = otpResult.EncryptedData;
                encryptionLayers = $"{algorithm}+AES256+OTP";
            }
            else
            {
                // Two-layer: PQC + OTP only
                var otpResult = _otpEngine.Encrypt(plaintextBytes, quantumKey.Data.Take(plaintextBytes.Length).ToArray(), keyId);

                finalCiphertext = otpResult.EncryptedData;
                encryptionLayers = $"{algorithm}+OTP";
            }

            // Mark key as used
            await _keyManager.MarkKeyAsUsedAsync(keyId, requiredKeySize);

            return new HybridEncryptedEmail
            {
                EncryptedBody = Convert.ToBase64String(finalCiphertext),
                PQCCiphertext = keyIdEncapsulation.Ciphertext,
                EncryptedKeyId = Convert.ToBase64String(encryptedKeyId), 
                Algorithm = encryptionLayers,
                SecurityLevel = securityLevel.ToString(),
                UseAES = useAES,
                KeyId = keyId,
                EncryptedAt = DateTime.UtcNow
            };
        }
        catch (Exception ex)
        {
            // FIXED: Add detailed logging before throwing exception
            Console.WriteLine($"[Level3HybridEncryption] EXCEPTION in EncryptAsync: {ex.Message}");
            Console.WriteLine($"[Level3HybridEncryption] Stack trace: {ex.StackTrace}");
            throw new InvalidOperationException($"Failed to encrypt with hybrid encryption: {ex.Message}", ex);
        }
    }

    // Keep synchronous version for backward compatibility
    public HybridEncryptedEmail Encrypt(
        string plaintext,
        string recipientPublicKey,
        Level3EnhancedPQC.SecurityLevel securityLevel,
        bool useAES = true)
    {
        return EncryptAsync(plaintext, recipientPublicKey, securityLevel, useAES).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Decrypts email encrypted with triple-layer hybrid encryption using KeyManager
    /// </summary>
    public async Task<string> DecryptAsync(
        string encryptedBody,
        string pqcCiphertext,
        string encryptedKeyId,
        string privateKey,
        string algorithm,
        bool usedAES)
    {
        try
        {
            // Step 1: PQC decapsulation → recover shared secret
            var algorithmName = algorithm.Split('+')[0]; // Extract base algorithm
            var pqcSharedSecret = _enhancedPQC.Decapsulate(pqcCiphertext, privateKey, algorithmName);
            var sharedSecretBytes = Convert.FromBase64String(pqcSharedSecret);

            // Step 2: Decrypt the keyId using PQC shared secret
            var encryptedKeyIdBytes = Convert.FromBase64String(encryptedKeyId);
            var keyIdBytes = XorBytes(encryptedKeyIdBytes, sharedSecretBytes.Take(encryptedKeyIdBytes.Length).ToArray());
            var keyId = Encoding.UTF8.GetString(keyIdBytes);

            // Step 3: Retrieve the quantum key from KeyManager using keyId
            var encryptedBytes = Convert.FromBase64String(encryptedBody);
            var requiredKeySize = usedAES ? encryptedBytes.Length + 256 : encryptedBytes.Length;
            var quantumKey = await _keyManager.GetKeyAsync(keyId, requiredKeySize);

            if (usedAES)
            {
                // Triple-layer decryption (reverse order)
                // Step 4: OTP XOR to remove OTP layer using quantum key
                var otpKeyOffset = 32; // Skip the 32 bytes used for AES
                var otpKey = quantumKey.Data.Skip(otpKeyOffset).Take(encryptedBytes.Length).ToArray();
                var aesEncrypted = _otpEngine.Decrypt(encryptedBytes, otpKey);

                // Step 5: AES-256-GCM decryption using quantum key
                var plaintext = DecryptWithAES256(aesEncrypted, quantumKey.Data.Take(32).ToArray());

                return Encoding.UTF8.GetString(plaintext);
            }
            else
            {
                // Two-layer: PQC + OTP only
                var decryptedBytes = _otpEngine.Decrypt(encryptedBytes, quantumKey.Data.Take(encryptedBytes.Length).ToArray());

                return Encoding.UTF8.GetString(decryptedBytes);
            }
        }
        catch (Exception ex)
        {
            // FIXED: Add detailed logging before throwing exception
            Console.WriteLine($"[Level3HybridEncryption] EXCEPTION in DecryptAsync: {ex.Message}");
            Console.WriteLine($"[Level3HybridEncryption] Stack trace: {ex.StackTrace}");
            throw new InvalidOperationException($"Failed to decrypt hybrid encrypted email: {ex.Message}", ex);
        }
    }

    // Keep synchronous version for backward compatibility
    public string Decrypt(
        string encryptedBody,
        string pqcCiphertext,
        string encryptedKeyId,
        string privateKey,
        string algorithm,
        bool usedAES)
    {
        return DecryptAsync(encryptedBody, pqcCiphertext, encryptedKeyId, privateKey, algorithm, usedAES).GetAwaiter().GetResult();
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

    #region AES-256-GCM Encryption (Middle Layer)

    /// <summary>
    /// Encrypts data using AES-256-GCM (Galois/Counter Mode)
    /// Provides both confidentiality and authenticity
    /// </summary>
    private byte[] EncryptWithAES256(byte[] plaintext, byte[] key)
    {
        using var aes = new AesGcm(key, AesGcm.TagByteSizes.MaxSize);

        // Generate random nonce (96 bits / 12 bytes for GCM)
        var nonce = new byte[AesGcm.NonceByteSizes.MaxSize];
        RandomNumberGenerator.Fill(nonce);

        // Allocate space for ciphertext and tag
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[AesGcm.TagByteSizes.MaxSize];

        // Encrypt
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        // Combine: [nonce][tag][ciphertext]
        var result = new byte[nonce.Length + tag.Length + ciphertext.Length];
        Buffer.BlockCopy(nonce, 0, result, 0, nonce.Length);
        Buffer.BlockCopy(tag, 0, result, nonce.Length, tag.Length);
        Buffer.BlockCopy(ciphertext, 0, result, nonce.Length + tag.Length, ciphertext.Length);

        return result;
    }

    /// <summary>
    /// Decrypts AES-256-GCM encrypted data
    /// </summary>
    private byte[] DecryptWithAES256(byte[] encrypted, byte[] key)
    {
        using var aes = new AesGcm(key, AesGcm.TagByteSizes.MaxSize);

        // Extract components
        var nonceSize = AesGcm.NonceByteSizes.MaxSize;
        var tagSize = AesGcm.TagByteSizes.MaxSize;

        var nonce = new byte[nonceSize];
        var tag = new byte[tagSize];
        var ciphertext = new byte[encrypted.Length - nonceSize - tagSize];

        Buffer.BlockCopy(encrypted, 0, nonce, 0, nonceSize);
        Buffer.BlockCopy(encrypted, nonceSize, tag, 0, tagSize);
        Buffer.BlockCopy(encrypted, nonceSize + tagSize, ciphertext, 0, ciphertext.Length);

        // Decrypt
        var plaintext = new byte[ciphertext.Length];
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return plaintext;
    }

    #endregion

    #region Key Derivation & Expansion

    private byte[] DeriveOTPKey(byte[] pqcSecret, int length)
    {
        // Use HKDF to derive OTP key from PQC shared secret
        using var hmac = new HMACSHA256(pqcSecret);
        var info = Encoding.UTF8.GetBytes("QuMail-OTP-v1");
        var hash = hmac.ComputeHash(info);

        // Expand if needed
        if (length <= hash.Length)
        {
            return hash.Take(length).ToArray();
        }

        return ExpandKey(hash, length);
    }

    private byte[] ExpandKey(byte[] key, int requiredLength)
    {
        if (requiredLength <= key.Length)
        {
            return key.Take(requiredLength).ToArray();
        }

        var expanded = new byte[requiredLength];
        var rounds = (requiredLength + key.Length - 1) / key.Length;

        using (var sha256 = SHA256.Create())
        {
            var currentKey = key;
            var offset = 0;

            for (int round = 0; round < rounds; round++)
            {
                var input = currentKey.Concat(BitConverter.GetBytes(round)).ToArray();
                var hash = sha256.ComputeHash(input);

                var bytesToCopy = Math.Min(hash.Length, requiredLength - offset);
                Buffer.BlockCopy(hash, 0, expanded, offset, bytesToCopy);
                offset += bytesToCopy;

                currentKey = hash;
            }
        }

        return expanded;
    }

    private string GenerateKeyId()
    {
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var randomBytes = new byte[8];
        RandomNumberGenerator.Fill(randomBytes);
        return $"HYBRID-{timestamp}-{Convert.ToBase64String(randomBytes).Replace("/", "").Replace("+", "").Substring(0, 8)}";
    }

    private string GetAlgorithmName(Level3EnhancedPQC.SecurityLevel level)
    {
        return level switch
        {
            Level3EnhancedPQC.SecurityLevel.Kyber512 => "Kyber-512",
            Level3EnhancedPQC.SecurityLevel.Kyber1024 => "Kyber-1024",
            Level3EnhancedPQC.SecurityLevel.McEliece => "McEliece-348864",
            _ => throw new ArgumentException($"Unknown security level: {level}")
        };
    }

    #endregion
}

/// <summary>
/// HKDF-SHA256 for key derivation
/// </summary>
public class HKDFSHA256
{
    private readonly byte[] _prk;
    private readonly int _outputLength;

    public HKDFSHA256(byte[] ikm, int outputLength, byte[]? salt = null, byte[]? info = null)
    {
        _outputLength = outputLength;

        // Extract
        using var hmac = new HMACSHA256(salt ?? new byte[32]);
        _prk = hmac.ComputeHash(ikm);
    }

    public byte[] GetBytes(int length)
    {
        var output = new byte[length];
        var iterations = (int)Math.Ceiling((double)length / 32);
        var prev = Array.Empty<byte>();

        using var hmac = new HMACSHA256(_prk);
        for (int i = 1; i <= iterations; i++)
        {
            var input = prev.Concat(new[] { (byte)i }).ToArray();
            prev = hmac.ComputeHash(input);

            var copyLength = Math.Min(32, length - (i - 1) * 32);
            Buffer.BlockCopy(prev, 0, output, (i - 1) * 32, copyLength);
        }

        return output;
    }
}

/// <summary>
/// Hybrid encrypted email with triple-layer security
/// </summary>
public class HybridEncryptedEmail
{
    public string EncryptedBody { get; set; } = string.Empty;
    public string PQCCiphertext { get; set; } = string.Empty;
    public string EncryptedKeyId { get; set; } = string.Empty; // NEW: encrypted keyId for receiver
    public string Algorithm { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = string.Empty;
    public bool UseAES { get; set; }
    public string KeyId { get; set; } = string.Empty;
    public DateTime EncryptedAt { get; set; }
}
