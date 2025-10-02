using System.Text;
using QuMail.EmailProtocol.Interfaces;

namespace QuMail.EmailProtocol.Mocks;

public class MockOneTimePadEngine : IOneTimePadEngine
{
    public EncryptionResult Encrypt(byte[] plaintext, byte[] key, string keyId)
    {
        // Mock implementation: Simple XOR for testing
        var encrypted = new byte[plaintext.Length];
        for (int i = 0; i < plaintext.Length; i++)
        {
            encrypted[i] = (byte)(plaintext[i] ^ key[i % key.Length]);
        }
        
        // Add mock encryption marker for testing
        var marker = Encoding.UTF8.GetBytes("[ENCRYPTED-MOCK]");
        var result = new byte[marker.Length + encrypted.Length];
        marker.CopyTo(result, 0);
        encrypted.CopyTo(result, marker.Length);
        
        return new EncryptionResult
        {
            EncryptedData = result,
            KeyId = keyId,
            BytesUsed = plaintext.Length
        };
    }
    
    public byte[] Decrypt(byte[] ciphertext, byte[] key)
    {
        // Remove mock marker if present
        var marker = Encoding.UTF8.GetBytes("[ENCRYPTED-MOCK]");
        var startIndex = 0;
        
        if (ciphertext.Length > marker.Length)
        {
            var hasMarker = true;
            for (int i = 0; i < marker.Length; i++)
            {
                if (ciphertext[i] != marker[i])
                {
                    hasMarker = false;
                    break;
                }
            }
            if (hasMarker) startIndex = marker.Length;
        }
        
        // Mock decryption: Simple XOR
        var actualCiphertext = new byte[ciphertext.Length - startIndex];
        Array.Copy(ciphertext, startIndex, actualCiphertext, 0, actualCiphertext.Length);
        
        var decrypted = new byte[actualCiphertext.Length];
        for (int i = 0; i < actualCiphertext.Length; i++)
        {
            decrypted[i] = (byte)(actualCiphertext[i] ^ key[i % key.Length]);
        }
        
        return decrypted;
    }
}

public class MockQuantumKeyManager : IQuantumKeyManager
{
    private readonly Dictionary<string, byte[]> _mockKeys = new();
    private readonly HashSet<string> _usedKeys = new();
    
    public Task<QuantumKey> GetKeyAsync(string keyId, int requiredBytes)
    {
        // Generate a mock key if not exists
        if (!_mockKeys.ContainsKey(keyId))
        {
            var random = new Random();
            var key = new byte[requiredBytes];
            random.NextBytes(key);
            _mockKeys[keyId] = key;
        }
        
        var keyData = _mockKeys[keyId];
        if (keyData.Length < requiredBytes)
        {
            // Extend key if needed
            var newKey = new byte[requiredBytes];
            keyData.CopyTo(newKey, 0);
            var random = new Random();
            random.NextBytes(newKey.AsSpan(keyData.Length));
            _mockKeys[keyId] = newKey;
            keyData = newKey;
        }
        
        return Task.FromResult(new QuantumKey
        {
            Id = keyId,
            Data = keyData.Take(requiredBytes).ToArray(),
            Size = requiredBytes
        });
    }
    
    public Task MarkKeyAsUsedAsync(string keyId, int bytesUsed)
    {
        _usedKeys.Add($"{keyId}:{bytesUsed}");
        return Task.CompletedTask;
    }
}