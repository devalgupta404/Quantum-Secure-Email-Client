using QuMail.EmailProtocol.Interfaces;

namespace QuMail.EmailProtocol.Services;

public class Level1OneTimePadEngine : IOneTimePadEngine
{
    public EncryptionResult Encrypt(byte[] plaintext, byte[] key, string keyId)
    {
        // Validate inputs
        if (plaintext == null || plaintext.Length == 0)
            throw new ArgumentException("Plaintext cannot be null or empty", nameof(plaintext));
        
        if (key == null || key.Length == 0)
            throw new ArgumentException("Key cannot be null or empty", nameof(key));
        
        if (plaintext.Length > key.Length)
            throw new ArgumentException("Key must be at least as long as plaintext", nameof(key));

        // Perform one-time pad encryption (XOR)
        var encryptedData = new byte[plaintext.Length];
        for (int i = 0; i < plaintext.Length; i++)
        {
            encryptedData[i] = (byte)(plaintext[i] ^ key[i]);
        }

        return new EncryptionResult
        {
            EncryptedData = encryptedData,
            KeyId = keyId,
            BytesUsed = plaintext.Length
        };
    }

    public byte[] Decrypt(byte[] ciphertext, byte[] key)
    {
        // Validate inputs
        if (ciphertext == null || ciphertext.Length == 0)
            throw new ArgumentException("Ciphertext cannot be null or empty", nameof(ciphertext));
        
        if (key == null || key.Length == 0)
            throw new ArgumentException("Key cannot be null or empty", nameof(key));
        
        if (ciphertext.Length > key.Length)
            throw new ArgumentException("Key must be at least as long as ciphertext", nameof(key));

        // Perform one-time pad decryption (XOR - same operation as encryption)
        var decryptedData = new byte[ciphertext.Length];
        for (int i = 0; i < ciphertext.Length; i++)
        {
            decryptedData[i] = (byte)(ciphertext[i] ^ key[i]);
        }

        return decryptedData;
    }
}
