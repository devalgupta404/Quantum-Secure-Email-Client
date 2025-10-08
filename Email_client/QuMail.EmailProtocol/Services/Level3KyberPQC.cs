using Org.BouncyCastle.Pqc.Crypto.Crystals.Kyber;
using Org.BouncyCastle.Security;
using System.Security.Cryptography;

namespace QuMail.EmailProtocol.Services;

/// <summary>
/// Level 3: Post-Quantum Cryptography implementation using CRYSTALS-Kyber
/// This class handles key generation, encapsulation, and decapsulation for quantum-resistant encryption
/// </summary>
public class Level3KyberPQC
{
    // Kyber-512: Balanced security and performance (NIST Level 1)
    // Provides security equivalent to AES-128 against quantum attacks
    private static readonly KyberParameters KyberParams = KyberParameters.kyber512;

    /// <summary>
    /// Generates a new Kyber-512 key pair for PQC encryption
    /// </summary>
    /// <returns>PQC key pair containing public and private keys</returns>
    public PQCKeyPair GenerateKeyPair()
    {
        try
        {
            // Initialize Kyber key pair generator
            var keyGenParams = new KyberKeyGenerationParameters(new SecureRandom(), KyberParams);
            var keyPairGenerator = new KyberKeyPairGenerator();
            keyPairGenerator.Init(keyGenParams);

            // Generate key pair
            var keyPair = keyPairGenerator.GenerateKeyPair();

            var publicKey = (KyberPublicKeyParameters)keyPair.Public;
            var privateKey = (KyberPrivateKeyParameters)keyPair.Private;

            // Extract raw bytes from keys
            var publicKeyBytes = publicKey.GetEncoded();
            var privateKeyBytes = privateKey.GetEncoded();

            return new PQCKeyPair
            {
                PublicKey = Convert.ToBase64String(publicKeyBytes),
                PrivateKey = Convert.ToBase64String(privateKeyBytes),
                Algorithm = "Kyber-512",
                GeneratedAt = DateTime.UtcNow
            };
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to generate PQC key pair", ex);
        }
    }

    /// <summary>
    /// Performs key encapsulation (sender side)
    /// Takes recipient's public key and generates a shared secret + ciphertext
    /// </summary>
    /// <param name="recipientPublicKey">Base64-encoded recipient public key</param>
    /// <returns>Encapsulation result with shared secret and ciphertext</returns>
    public PQCEncapsulationResult Encapsulate(string recipientPublicKey)
    {
        try
        {
            // Decode public key
            var publicKeyBytes = Convert.FromBase64String(recipientPublicKey);
            var publicKeyParams = new KyberPublicKeyParameters(KyberParams, publicKeyBytes);

            // Initialize KEM for encapsulation
            var kem = new KyberKemGenerator(new SecureRandom());
            var encapsulated = kem.GenerateEncapsulated(publicKeyParams);

            // Extract shared secret and ciphertext
            var sharedSecret = encapsulated.GetSecret();
            var ciphertext = encapsulated.GetEncapsulation();

            // Ensure shared secret is exactly 32 bytes for OTP encryption
            var derivedKey = DeriveKey(sharedSecret, 32);

            return new PQCEncapsulationResult
            {
                SharedSecret = Convert.ToBase64String(derivedKey),
                Ciphertext = Convert.ToBase64String(ciphertext),
                Algorithm = "Kyber-512-KEM"
            };
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to encapsulate with PQC", ex);
        }
    }

    /// <summary>
    /// Performs key decapsulation (receiver side)
    /// Takes ciphertext and private key to recover the shared secret
    /// </summary>
    /// <param name="ciphertext">Base64-encoded PQC ciphertext</param>
    /// <param name="privateKey">Base64-encoded private key</param>
    /// <returns>Shared secret that matches the sender's secret</returns>
    public string Decapsulate(string ciphertext, string privateKey)
    {
        try
        {
            // Decode inputs
            var ciphertextBytes = Convert.FromBase64String(ciphertext);
            var privateKeyBytes = Convert.FromBase64String(privateKey);

            var privateKeyParams = new KyberPrivateKeyParameters(KyberParams, privateKeyBytes);

            // Initialize KEM for decapsulation
            var kem = new KyberKemExtractor(privateKeyParams);
            var sharedSecret = kem.ExtractSecret(ciphertextBytes);

            // Ensure shared secret is exactly 32 bytes for OTP encryption
            var derivedKey = DeriveKey(sharedSecret, 32);

            return Convert.ToBase64String(derivedKey);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Failed to decapsulate with PQC", ex);
        }
    }

    /// <summary>
    /// Derives a fixed-length key from the Kyber shared secret using SHA-256
    /// This ensures we always get a 32-byte key for OTP encryption
    /// </summary>
    /// <param name="secret">Raw shared secret from Kyber KEM</param>
    /// <param name="keyLength">Desired key length in bytes</param>
    /// <returns>Derived key of specified length</returns>
    private byte[] DeriveKey(byte[] secret, int keyLength)
    {
        // Use SHA-256 to derive a fixed-length key
        // In production, consider using HKDF for better key derivation
        using var sha256 = SHA256.Create();
        var hash = sha256.ComputeHash(secret);

        // Return first keyLength bytes (32 bytes for SHA-256)
        return hash.Take(keyLength).ToArray();
    }

    /// <summary>
    /// Validates if a public key is well-formed
    /// </summary>
    public bool ValidatePublicKey(string publicKey)
    {
        try
        {
            var publicKeyBytes = Convert.FromBase64String(publicKey);
            _ = new KyberPublicKeyParameters(KyberParams, publicKeyBytes);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Gets information about the Kyber parameters being used
    /// </summary>
    public PQCInfo GetPQCInfo()
    {
        return new PQCInfo
        {
            Algorithm = "CRYSTALS-Kyber",
            Variant = "Kyber-512",
            SecurityLevel = "NIST Level 1 (equivalent to AES-128)",
            PublicKeySize = 800,  // bytes
            PrivateKeySize = 1632, // bytes
            CiphertextSize = 768,  // bytes
            SharedSecretSize = 32  // bytes (after derivation)
        };
    }
}
