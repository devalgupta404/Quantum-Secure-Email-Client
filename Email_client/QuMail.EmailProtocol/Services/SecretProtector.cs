using System.Security.Cryptography;
using System.Text;

namespace QuMail.EmailProtocol.Services;

public static class SecretProtector
{
    // AES-256-GCM with key from environment variable APP_SECRET_KEY (base64 or raw)
    private static byte[] GetKey()
    {
        var keyStr = Environment.GetEnvironmentVariable("APP_SECRET_KEY");
        if (string.IsNullOrWhiteSpace(keyStr))
        {
            throw new InvalidOperationException("APP_SECRET_KEY is not configured");
        }
        try
        {
            // Try base64 first
            return Convert.FromBase64String(keyStr);
        }
        catch
        {
            // Fallback to UTF8 bytes
            return Encoding.UTF8.GetBytes(keyStr);
        }
    }

    public static string Encrypt(string plaintext)
    {
        if (plaintext == null) throw new ArgumentNullException(nameof(plaintext));
        var key = GetKey();
        using var aes = new AesGcm(NormalizeKey(key));
        var nonce = RandomNumberGenerator.GetBytes(12);
        var plainBytes = Encoding.UTF8.GetBytes(plaintext);
        var cipher = new byte[plainBytes.Length];
        var tag = new byte[16];
        aes.Encrypt(nonce, plainBytes, cipher, tag);
        // Package: nonce|tag|cipher all base64
        var payload = Convert.ToBase64String(nonce) + ":" + Convert.ToBase64String(tag) + ":" + Convert.ToBase64String(cipher);
        return payload;
    }

    public static string Decrypt(string payload)
    {
        if (string.IsNullOrWhiteSpace(payload)) throw new ArgumentNullException(nameof(payload));
        var parts = payload.Split(':');
        if (parts.Length != 3) throw new InvalidOperationException("Invalid secret payload format");
        var nonce = Convert.FromBase64String(parts[0]);
        var tag = Convert.FromBase64String(parts[1]);
        var cipher = Convert.FromBase64String(parts[2]);
        var key = GetKey();
        using var aes = new AesGcm(NormalizeKey(key));
        var plain = new byte[cipher.Length];
        aes.Decrypt(nonce, cipher, tag, plain);
        return Encoding.UTF8.GetString(plain);
    }

    private static byte[] NormalizeKey(byte[] key)
    {
        // Ensure 32 bytes
        if (key.Length == 32) return key;
        using var sha256 = SHA256.Create();
        return sha256.ComputeHash(key);
    }
}


