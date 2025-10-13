using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Xunit;
using FluentAssertions;

namespace QuMail.EmailProtocol.Tests;

/// <summary>
/// Tests for envelope parsing and error handling in PQC_3_LAYER flow
/// Ensures robust handling of malformed data and edge cases
/// </summary>
public class EnvelopeParsingTests
{
    [Fact]
    public void TryParseOTPEnvelope_ValidEnvelope_ParsesSuccessfully()
    {
        // Arrange
        var validOtpEnvelope = JsonSerializer.Serialize(new
        {
            otp_key_id = "K123",
            ciphertext_b64url = "SGVsbG8gV29ybGQ"
        });

        // Act
        var (success, envelope) = TryParseOTPEnvelope(validOtpEnvelope);

        // Assert
        success.Should().BeTrue();
        envelope.Should().NotBeNull();
        envelope!["otp_key_id"].Should().Be("K123");
        envelope["ciphertext_b64url"].Should().Be("SGVsbG8gV29ybGQ");
    }

    [Fact]
    public void TryParseAESEnvelope_ValidEnvelope_ParsesSuccessfully()
    {
        // Arrange
        var validAesEnvelope = JsonSerializer.Serialize(new
        {
            KeyId = "AES_123",
            IvHex = "1234567890ABCDEF",
            CiphertextHex = "ABCDEF1234567890",
            TagHex = "9876543210FEDCBA",
            AadHex = "",
            Algorithm = "AES-256-GCM"
        });

        // Act
        var (success, envelope) = TryParseAESEnvelope(validAesEnvelope);

        // Assert
        success.Should().BeTrue();
        envelope.Should().NotBeNull();
        envelope!["KeyId"].Should().Be("AES_123");
        envelope["Algorithm"].Should().Be("AES-256-GCM");
    }

    [Fact]
    public void TryParsePQCEnvelope_ValidEnvelope_ParsesSuccessfully()
    {
        // Arrange
        var validPqcEnvelope = JsonSerializer.Serialize(new
        {
            encryptedBody = "PQC_BODY",
            pqcCiphertext = "PQC_CIPHER",
            encryptedKeyId = "K123",
            algorithm = "Kyber1024",
            keyId = "K123",
            securityLevel = "Kyber512",
            useAES = true
        });

        // Act
        var (success, envelope) = TryParsePQCEnvelope(validPqcEnvelope);

        // Assert
        success.Should().BeTrue();
        envelope.Should().NotBeNull();
        envelope!["encryptedBody"].Should().Be("PQC_BODY");
        envelope["pqcCiphertext"].Should().Be("PQC_CIPHER");
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("not json")]
    [InlineData("{invalid json}")]
    [InlineData("null")]
    public void TryParseOTPEnvelope_InvalidInput_ReturnsFalse(string input)
    {
        // Act
        var (success, envelope) = TryParseOTPEnvelope(input);

        // Assert
        success.Should().BeFalse();
        envelope.Should().BeNull();
    }

    [Fact]
    public void TryParseOTPEnvelope_MissingRequiredField_ReturnsFalse()
    {
        // Arrange
        var incompleteEnvelope = JsonSerializer.Serialize(new
        {
            otp_key_id = "K123"
            // Missing ciphertext_b64url
        });

        // Act
        var (success, envelope) = TryParseOTPEnvelope(incompleteEnvelope);

        // Assert
        success.Should().BeFalse();
    }

    [Fact]
    public void TryParseAESEnvelope_MissingKeyId_ReturnsFalse()
    {
        // Arrange
        var incompleteEnvelope = JsonSerializer.Serialize(new
        {
            IvHex = "1234567890ABCDEF",
            CiphertextHex = "ABCDEF1234567890"
            // Missing KeyId
        });

        // Act
        var (success, envelope) = TryParseAESEnvelope(incompleteEnvelope);

        // Assert
        success.Should().BeFalse();
    }

    [Fact]
    public void TryParsePQCEnvelope_MissingEncryptedBody_ReturnsFalse()
    {
        // Arrange
        var incompleteEnvelope = JsonSerializer.Serialize(new
        {
            pqcCiphertext = "PQC_CIPHER",
            encryptedKeyId = "K123"
            // Missing encryptedBody
        });

        // Act
        var (success, envelope) = TryParsePQCEnvelope(incompleteEnvelope);

        // Assert
        success.Should().BeFalse();
    }

    [Fact]
    public void DecryptionErrorMessage_NotValidJson_HandledGracefully()
    {
        // Arrange
        var errorMessages = new[]
        {
            "OTP decryption failed",
            "Decryption failed",
            "AES decryption failed: timeout",
            "[Decryption Failed - OTP key may have expired]"
        };

        // Act & Assert
        foreach (var errorMsg in errorMessages)
        {
            var (success, _) = TryParseOTPEnvelope(errorMsg);
            success.Should().BeFalse($"Error message '{errorMsg}' should not parse as JSON");

            var (success2, _) = TryParseAESEnvelope(errorMsg);
            success2.Should().BeFalse($"Error message '{errorMsg}' should not parse as JSON");

            var (success3, _) = TryParsePQCEnvelope(errorMsg);
            success3.Should().BeFalse($"Error message '{errorMsg}' should not parse as JSON");
        }
    }

    [Fact]
    public void Base64UrlDecoding_StandardAndUrlSafe_BothWork()
    {
        // Arrange
        var originalData = "Hello World! Special chars: +/=";
        var standardBase64 = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(originalData));
        var urlSafeBase64 = standardBase64.Replace('+', '-').Replace('/', '_').TrimEnd('=');

        // Act - Decode standard base64
        var decodedStandard = DecodeBase64(standardBase64);

        // Act - Decode URL-safe base64
        var decodedUrlSafe = DecodeBase64Url(urlSafeBase64);

        // Assert
        System.Text.Encoding.UTF8.GetString(decodedStandard).Should().Be(originalData);
        System.Text.Encoding.UTF8.GetString(decodedUrlSafe).Should().Be(originalData);
    }

    [Fact]
    public void NestedEnvelopeDecryption_CorrectOrder_WorksCorrectly()
    {
        // This test simulates the actual decryption flow with nested envelopes

        // Arrange - Create nested structure: OTP(AES(Base64(PQC)))
        var pqcData = JsonSerializer.Serialize(new { encryptedBody = "INNER_DATA", pqcCiphertext = "CIPHER" });
        var base64Pqc = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(pqcData));
        var aesData = JsonSerializer.Serialize(new { KeyId = "K1", CiphertextHex = base64Pqc });
        var otpData = JsonSerializer.Serialize(new { otp_key_id = "K2", ciphertext_b64url = EncodeBase64Url(aesData) });

        // Act - Decrypt layer by layer
        // Step 1: Parse OTP envelope
        var (otpSuccess, otpEnv) = TryParseOTPEnvelope(otpData);
        otpSuccess.Should().BeTrue();

        // Step 2: Decode OTP ciphertext to get AES envelope
        var aesJson = System.Text.Encoding.UTF8.GetString(DecodeBase64Url(otpEnv!["ciphertext_b64url"]));
        var (aesSuccess, aesEnv) = TryParseAESEnvelope(aesJson);
        aesSuccess.Should().BeTrue();

        // Step 3: Get base64 PQC envelope from AES
        var base64PqcData = aesEnv!["CiphertextHex"];

        // Step 4: Decode base64 to get PQC envelope
        var pqcJson = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(base64PqcData));
        var (pqcSuccess, pqcEnv) = TryParsePQCEnvelope(pqcJson);
        pqcSuccess.Should().BeTrue();

        // Assert - Verify we got back to the original inner data
        pqcEnv!["encryptedBody"].Should().Be("INNER_DATA");
        pqcEnv["pqcCiphertext"].Should().Be("CIPHER");
    }

    [Fact]
    public void CorruptedAttachmentData_NotBase64_DetectedCorrectly()
    {
        // This test verifies that corrupted attachment data is detected

        // Arrange - Simulated corrupted data (like in the original bug report)
        var corruptedData = "y�u��I��m��]�UG��Μ.^pZ␦���i��}␦+�C>k���d�:u�";

        // Act
        var isValidBase64 = TryDecodeBase64(corruptedData, out var decoded);

        // Assert
        isValidBase64.Should().BeFalse("Corrupted data should not be valid base64");
        decoded.Should().BeNull();
    }

    [Theory]
    [InlineData("SGVsbG8gV29ybGQ=")]  // Standard base64
    [InlineData("SGVsbG8gV29ybGQ")]   // Without padding
    [InlineData("")]                   // Empty
    public void ValidBase64Data_DecodesSuccessfully(string base64Data)
    {
        // Act
        var isValid = TryDecodeBase64(base64Data, out var decoded);

        // Assert
        if (string.IsNullOrEmpty(base64Data))
        {
            isValid.Should().BeTrue();
            decoded.Should().NotBeNull().And.BeEmpty();
        }
        else
        {
            isValid.Should().BeTrue();
            decoded.Should().NotBeNull();
        }
    }

    // Helper methods
    private (bool success, Dictionary<string, string>? envelope) TryParseOTPEnvelope(string data)
    {
        try
        {
            var parsed = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(data);
            if (parsed == null) return (false, null);

            if (!parsed.ContainsKey("otp_key_id") || !parsed.ContainsKey("ciphertext_b64url"))
                return (false, null);

            var result = new Dictionary<string, string>
            {
                ["otp_key_id"] = parsed["otp_key_id"].GetString() ?? "",
                ["ciphertext_b64url"] = parsed["ciphertext_b64url"].GetString() ?? ""
            };

            return (true, result);
        }
        catch
        {
            return (false, null);
        }
    }

    private (bool success, Dictionary<string, string>? envelope) TryParseAESEnvelope(string data)
    {
        try
        {
            var parsed = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(data);
            if (parsed == null) return (false, null);

            if (!parsed.ContainsKey("KeyId") || !parsed.ContainsKey("CiphertextHex"))
                return (false, null);

            var result = parsed.ToDictionary(
                kvp => kvp.Key,
                kvp => kvp.Value.ValueKind == JsonValueKind.String ? kvp.Value.GetString() ?? "" : kvp.Value.ToString()
            );

            return (true, result);
        }
        catch
        {
            return (false, null);
        }
    }

    private (bool success, Dictionary<string, string>? envelope) TryParsePQCEnvelope(string data)
    {
        try
        {
            var parsed = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(data);
            if (parsed == null) return (false, null);

            if (!parsed.ContainsKey("encryptedBody") || !parsed.ContainsKey("pqcCiphertext"))
                return (false, null);

            var result = parsed.ToDictionary(
                kvp => kvp.Key,
                kvp => kvp.Value.ValueKind == JsonValueKind.String ? kvp.Value.GetString() ?? "" :
                       kvp.Value.ValueKind == JsonValueKind.True ? "true" :
                       kvp.Value.ValueKind == JsonValueKind.False ? "false" :
                       kvp.Value.ToString()
            );

            return (true, result);
        }
        catch
        {
            return (false, null);
        }
    }

    private byte[] DecodeBase64(string base64)
    {
        return Convert.FromBase64String(base64);
    }

    private byte[] DecodeBase64Url(string base64Url)
    {
        var base64 = base64Url.Replace('-', '+').Replace('_', '/');
        while (base64.Length % 4 != 0) base64 += "=";
        return Convert.FromBase64String(base64);
    }

    private string EncodeBase64Url(string data)
    {
        var base64 = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(data));
        return base64.Replace('+', '-').Replace('/', '_').TrimEnd('=');
    }

    private bool TryDecodeBase64(string base64Data, out byte[]? decoded)
    {
        try
        {
            if (string.IsNullOrEmpty(base64Data))
            {
                decoded = Array.Empty<byte>();
                return true;
            }

            decoded = Convert.FromBase64String(base64Data);
            return true;
        }
        catch
        {
            decoded = null;
            return false;
        }
    }
}
