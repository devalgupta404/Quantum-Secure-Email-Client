namespace QuMail.EmailProtocol.Interfaces;

public interface IOneTimePadEngine
{
    EncryptionResult Encrypt(byte[] plaintext, byte[] key, string keyId);
    byte[] Decrypt(byte[] ciphertext, byte[] key);
}

public interface IQuantumKeyManager
{
    Task<QuantumKey> GetKeyAsync(string keyId, int requiredBytes);
    Task MarkKeyAsUsedAsync(string keyId, int bytesUsed);
}

public class EncryptionResult
{
    public byte[] EncryptedData { get; set; } = Array.Empty<byte>();
    public string KeyId { get; set; } = string.Empty;
    public int BytesUsed { get; set; }
}

public class QuantumKey
{
    public string Id { get; set; } = string.Empty;
    public byte[] Data { get; set; } = Array.Empty<byte>();
    public int Size { get; set; }
}