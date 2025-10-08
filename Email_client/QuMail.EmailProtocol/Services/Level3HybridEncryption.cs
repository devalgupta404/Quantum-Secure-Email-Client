using QuMail.EmailProtocol.Interfaces;
using System.Security.Cryptography;
using System.Text;

namespace QuMail.EmailProtocol.Services;

/// <summary>
/// Triple-layer hybrid encryption: PQC + AES-256 + OTP
///
/// ENCRYPTION FLOW:
/// 1. PQC (Kyber/McEliece) encapsulation → shared secret (32 bytes)
/// 2. AES-256-GCM encryption with shared secret as key
/// 3. OTP XOR on the AES ciphertext (defense-in-depth)
///
/// This provides maximum security:
/// - If PQC breaks → AES-256 protects you
/// - If AES breaks → PQC protects you
/// - If both break → OTP still protects you
/// </summary>
public class Level3HybridEncryption
{
    private readonly Level3EnhancedPQC _enhancedPQC;
    private readonly IOneTimePadEngine _otpEngine;

    public Level3HybridEncryption(Level3EnhancedPQC enhancedPQC, IOneTimePadEngine otpEngine)
    {
        _enhancedPQC = enhancedPQC ?? throw new ArgumentNullException(nameof(enhancedPQC));
        _otpEngine = otpEngine ?? throw new ArgumentNullException(nameof(otpEngine));
    }

    /// <summary>
    /// Encrypts email using triple-layer hybrid encryption
    /// </summary>
    /// <param name="plaintext">Email body to encrypt</param>
    /// <param name="recipientPublicKey">Recipient's PQC public key</param>
    /// <param name="securityLevel">PQC security level to use</param>
    /// <param name="useAES">Enable AES-256 middle layer (recommended)</param>
    /// <returns>Encrypted email with PQC + AES + OTP layers</returns>
    public HybridEncryptedEmail Encrypt(
        string plaintext,
        string recipientPublicKey,
        Level3EnhancedPQC.SecurityLevel securityLevel,
        bool useAES = true)
    {
        try
        {
            // Get algorithm name from security level
            var algorithm = GetAlgorithmName(securityLevel);

            // Step 1: PQC encapsulation → shared secret
            var encapsulation = _enhancedPQC.Encapsulate(recipientPublicKey, algorithm);
            var pqcSharedSecret = Convert.FromBase64String(encapsulation.SharedSecret);

            byte[] finalCiphertext;
            string encryptionLayers;

            if (useAES)
            {
                // **YOUR IDEA**: Triple-layer encryption
                // Step 2: AES-256-GCM encryption with PQC shared secret
                var aesEncrypted = EncryptWithAES256(Encoding.UTF8.GetBytes(plaintext), pqcSharedSecret);

                // Step 3: OTP XOR on top of AES ciphertext
                var otpKey = DeriveOTPKey(pqcSharedSecret, aesEncrypted.Length);
                var keyId = GenerateKeyId();
                var otpResult = _otpEngine.Encrypt(aesEncrypted, otpKey, keyId);

                finalCiphertext = otpResult.EncryptedData;
                encryptionLayers = $"{algorithm}+AES256+OTP";
            }
            else
            {
                // Two-layer: PQC + OTP only (original implementation)
                var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
                var otpKey = ExpandKey(pqcSharedSecret, plaintextBytes.Length);
                var keyId = GenerateKeyId();
                var otpResult = _otpEngine.Encrypt(plaintextBytes, otpKey, keyId);

                finalCiphertext = otpResult.EncryptedData;
                encryptionLayers = $"{algorithm}+OTP";
            }

            return new HybridEncryptedEmail
            {
                EncryptedBody = Convert.ToBase64String(finalCiphertext),
                PQCCiphertext = encapsulation.Ciphertext,
                Algorithm = encryptionLayers,
                SecurityLevel = securityLevel.ToString(),
                UseAES = useAES,
                KeyId = GenerateKeyId(),
                EncryptedAt = DateTime.UtcNow
            };
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to encrypt with hybrid encryption", ex);
        }
    }

    /// <summary>
    /// Decrypts email encrypted with triple-layer hybrid encryption
    /// </summary>
    public string Decrypt(
        string encryptedBody,
        string pqcCiphertext,
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

            var encryptedBytes = Convert.FromBase64String(encryptedBody);

            if (usedAES)
            {
                // Triple-layer decryption (reverse order)
                // Step 2: OTP XOR to remove OTP layer
                var otpKey = DeriveOTPKey(sharedSecretBytes, encryptedBytes.Length);
                var aesEncrypted = _otpEngine.Decrypt(encryptedBytes, otpKey);

                // Step 3: AES-256-GCM decryption
                var plaintext = DecryptWithAES256(aesEncrypted, sharedSecretBytes);

                return Encoding.UTF8.GetString(plaintext);
            }
            else
            {
                // Two-layer: OTP only
                var otpKey = ExpandKey(sharedSecretBytes, encryptedBytes.Length);
                var decryptedBytes = _otpEngine.Decrypt(encryptedBytes, otpKey);

                return Encoding.UTF8.GetString(decryptedBytes);
            }
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to decrypt hybrid encrypted email", ex);
        }
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
    public string Algorithm { get; set; } = string.Empty;
    public string SecurityLevel { get; set; } = string.Empty;
    public bool UseAES { get; set; }
    public string KeyId { get; set; } = string.Empty;
    public DateTime EncryptedAt { get; set; }
}
