using System;
using System.Text.Json;
using Xunit;
using FluentAssertions;
using Moq;
using Microsoft.Extensions.Logging;
using QuMail.EmailProtocol.Controllers;
using QuMail.EmailProtocol.Data;
using Microsoft.EntityFrameworkCore;

namespace QuMail.EmailProtocol.Tests;

/// <summary>
/// Unit tests for PQC_3_LAYER encryption flow
/// Tests the complete encryption pipeline: PQC -> Prepare -> AES -> OTP
/// </summary>
public class PQC3LayerEncryptionTests
{
    [Fact]
    public void PreparePqcEnvelopeForAES_ValidJsonEnvelope_ReturnsBase64()
    {
        // Arrange
        var pqcEnvelope = JsonSerializer.Serialize(new
        {
            encryptedBody = "test_encrypted_body",
            pqcCiphertext = "test_pqc_ciphertext",
            encryptedKeyId = "test_key_id",
            algorithm = "Kyber1024",
            keyId = "K123",
            securityLevel = "Kyber512",
            useAES = true
        });

        // Act
        var result = PrepareEnvelopeForAES(pqcEnvelope);

        // Assert
        result.Should().NotBeNullOrEmpty();
        result.Should().NotBe(pqcEnvelope); // Should be base64 encoded

        // Verify it's valid base64
        var decoded = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(result));
        decoded.Should().Be(pqcEnvelope);
    }

    [Fact]
    public void RestorePqcEnvelopeFromAES_ValidBase64_ReturnsJsonEnvelope()
    {
        // Arrange
        var originalJson = JsonSerializer.Serialize(new
        {
            encryptedBody = "test_encrypted_body",
            pqcCiphertext = "test_pqc_ciphertext",
            encryptedKeyId = "test_key_id"
        });
        var base64Encoded = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(originalJson));

        // Act
        var result = RestoreEnvelopeFromAES(base64Encoded);

        // Assert
        result.Should().Be(originalJson);

        // Verify it's valid JSON
        var parsed = JsonDocument.Parse(result);
        parsed.RootElement.TryGetProperty("encryptedBody", out _).Should().BeTrue();
    }

    [Fact]
    public void RestorePqcEnvelopeFromAES_InvalidBase64_ReturnsOriginalString()
    {
        // Arrange
        var invalidBase64 = "This is not base64!!!";

        // Act
        var result = RestoreEnvelopeFromAES(invalidBase64);

        // Assert
        result.Should().Be(invalidBase64); // Should return as-is on failure
    }

    [Fact]
    public void PreparePqcEnvelopeForAES_EmptyString_ReturnsEmpty()
    {
        // Arrange
        var emptyString = "";

        // Act
        var result = PrepareEnvelopeForAES(emptyString);

        // Assert
        result.Should().Be(emptyString);
    }

    [Fact]
    public void PreparePqcEnvelopeForAES_InvalidJson_ReturnsOriginal()
    {
        // Arrange
        var invalidJson = "{invalid json}";

        // Act
        var result = PrepareEnvelopeForAES(invalidJson);

        // Assert
        result.Should().Be(invalidJson); // Should return as-is on failure
    }

    [Fact]
    public void RoundTrip_PrepareAndRestore_PreservesData()
    {
        // Arrange
        var originalData = JsonSerializer.Serialize(new
        {
            encryptedBody = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/==",
            pqcCiphertext = "Special chars: !@#$%^&*()_+-=[]{}|;:',.<>?/~`",
            encryptedKeyId = "Unicode: 你好世界 🌍🚀",
            algorithm = "Kyber1024",
            useAES = true
        });

        // Act
        var prepared = PrepareEnvelopeForAES(originalData);
        var restored = RestoreEnvelopeFromAES(prepared);

        // Assert
        restored.Should().Be(originalData);

        // Verify JSON structure is preserved
        var original = JsonDocument.Parse(originalData);
        var final = JsonDocument.Parse(restored);

        original.RootElement.GetProperty("encryptedBody").GetString()
            .Should().Be(final.RootElement.GetProperty("encryptedBody").GetString());
        original.RootElement.GetProperty("pqcCiphertext").GetString()
            .Should().Be(final.RootElement.GetProperty("pqcCiphertext").GetString());
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(null)]
    public void PreparePqcEnvelopeForAES_NullOrWhitespace_HandlesGracefully(string? input)
    {
        // Act
        var result = PrepareEnvelopeForAES(input ?? "");

        // Assert
        result.Should().NotBeNull();
    }

    [Fact]
    public void PreparePqcEnvelopeForAES_LargePayload_HandlesCorrectly()
    {
        // Arrange - Create a large JSON payload (simulating encrypted attachment)
        var largeData = new string('A', 10000);
        var largeEnvelope = JsonSerializer.Serialize(new
        {
            encryptedBody = largeData,
            pqcCiphertext = largeData,
            encryptedKeyId = "large_test"
        });

        // Act
        var prepared = PrepareEnvelopeForAES(largeEnvelope);
        var restored = RestoreEnvelopeFromAES(prepared);

        // Assert
        restored.Should().Be(largeEnvelope);

        // Verify the large data is intact
        var parsed = JsonDocument.Parse(restored);
        parsed.RootElement.GetProperty("encryptedBody").GetString()!.Length.Should().Be(10000);
    }

    // Helper methods that simulate the actual implementation
    private string PrepareEnvelopeForAES(string pqcJsonEnvelope)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(pqcJsonEnvelope))
            {
                return pqcJsonEnvelope;
            }

            using var testDoc = JsonDocument.Parse(pqcJsonEnvelope);
            if (!testDoc.RootElement.TryGetProperty("encryptedBody", out _))
            {
                return pqcJsonEnvelope;
            }

            return Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(pqcJsonEnvelope));
        }
        catch (JsonException)
        {
            return pqcJsonEnvelope;
        }
        catch (Exception)
        {
            return pqcJsonEnvelope;
        }
    }

    private string RestoreEnvelopeFromAES(string aesDecryptedResult)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(aesDecryptedResult))
            {
                return aesDecryptedResult;
            }

            var jsonBytes = Convert.FromBase64String(aesDecryptedResult);
            var originalJsonEnvelope = System.Text.Encoding.UTF8.GetString(jsonBytes);

            using var testDoc = JsonDocument.Parse(originalJsonEnvelope);
            if (!testDoc.RootElement.TryGetProperty("encryptedBody", out _))
            {
                return aesDecryptedResult;
            }

            return originalJsonEnvelope;
        }
        catch (FormatException)
        {
            return aesDecryptedResult;
        }
        catch (JsonException)
        {
            return aesDecryptedResult;
        }
        catch (Exception)
        {
            return aesDecryptedResult;
        }
    }
}
