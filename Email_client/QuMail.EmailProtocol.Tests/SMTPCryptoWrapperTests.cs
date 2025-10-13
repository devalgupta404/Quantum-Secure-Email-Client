using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using FluentAssertions;
using Microsoft.Extensions.Logging;
using Moq;
using QuMail.EmailProtocol.Configuration;
using QuMail.EmailProtocol.Interfaces;
using QuMail.EmailProtocol.Mocks;
using QuMail.EmailProtocol.Models;
using QuMail.EmailProtocol.Services;
using Xunit;

namespace QuMail.EmailProtocol.Tests;

public class SMTPCryptoWrapperTests
{
    private readonly Mock<ILogger<SMTPCryptoWrapper>> _loggerMock;
    private readonly MockOneTimePadEngine _mockCryptoEngine;
    private readonly MockQuantumKeyManager _mockKeyManager;
    
    public SMTPCryptoWrapperTests()
    {
        _loggerMock = new Mock<ILogger<SMTPCryptoWrapper>>();
        _mockCryptoEngine = new MockOneTimePadEngine();
        _mockKeyManager = new MockQuantumKeyManager();
    }
    
    [Fact]
    public async Task EncryptEmailContent_ShouldEncryptBodyAndAttachments()
    {
        // Arrange
        var wrapper = new SMTPCryptoWrapper(_mockCryptoEngine, _mockKeyManager, _loggerMock.Object);
        var message = new EmailMessage
        {
            From = "sender@example.com",
            To = new List<string> { "recipient@example.com" },
            Subject = "Test Email",
            Body = "This is a test email body",
            Attachments = new List<EmailAttachment>
            {
                new EmailAttachment
                {
                    FileName = "test.txt",
                    Content = Encoding.UTF8.GetBytes("Test attachment content"),
                    ContentType = "text/plain"
                }
            }
        };
        
        // Act - Use reflection to test private method
        var encryptMethod = typeof(SMTPCryptoWrapper)
            .GetMethod("EncryptEmailContentAsync", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        
        var keyId = "test-key-123";
        var encryptedContent = await (Task<EncryptedEmailContent>)encryptMethod!.Invoke(
            wrapper, new object[] { message, keyId })!;
        
        // Assert
        encryptedContent.Should().NotBeNull();
        encryptedContent.KeyId.Should().Be(keyId);
        encryptedContent.EncryptedBody.Should().NotBeNullOrEmpty();
        encryptedContent.EncryptedAttachments.Should().HaveCount(1);
        encryptedContent.EncryptedAttachments[0].FileName.Should().Be("test.txt");
        encryptedContent.EncryptionVersion.Should().Be("1.0");
    }
    
    [Fact]
    public void MockCryptoEngine_ShouldEncryptAndDecryptCorrectly()
    {
        // Arrange
        var plaintext = Encoding.UTF8.GetBytes("Hello, Quantum World!");
        var key = new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 };
        var keyId = "test-key";
        
        // Act
        var encryptionResult = _mockCryptoEngine.Encrypt(plaintext, key, keyId);
        var decrypted = _mockCryptoEngine.Decrypt(encryptionResult.EncryptedData, key);
        var decryptedText = Encoding.UTF8.GetString(decrypted);
        
        // Assert
        encryptionResult.Should().NotBeNull();
        encryptionResult.KeyId.Should().Be(keyId);
        encryptionResult.BytesUsed.Should().Be(plaintext.Length);
        decryptedText.Should().Be("Hello, Quantum World!");
    }
    
    [Fact]
    public async Task MockKeyManager_ShouldGenerateAndRetrieveKeys()
    {
        // Arrange
        var keyId = "quantum-key-001";
        var requiredBytes = 256;
        
        // Act
        var key1 = await _mockKeyManager.GetKeyAsync(keyId, requiredBytes);
        var key2 = await _mockKeyManager.GetKeyAsync(keyId, requiredBytes);
        await _mockKeyManager.MarkKeyAsUsedAsync(keyId, requiredBytes);
        
        // Assert
        key1.Should().NotBeNull();
        key1.Id.Should().Be(keyId);
        key1.Data.Should().HaveCount(requiredBytes);
        key1.Size.Should().Be(requiredBytes);
        
        // Same key ID should return consistent data
        key2.Data.Should().BeEquivalentTo(key1.Data);
    }
    
    [Fact]
    public void EmailProviderDefaults_ShouldContainGmailSettings()
    {
        // Arrange & Act
        var gmailProvider = EmailProviderDefaults.DefaultProviders["gmail"];
        
        // Assert
        gmailProvider.Should().NotBeNull();
        gmailProvider.Name.Should().Be("Gmail");
        gmailProvider.Smtp.Host.Should().Be("smtp.gmail.com");
        gmailProvider.Smtp.Port.Should().Be(587);
        gmailProvider.Smtp.EnableSsl.Should().BeTrue();
        gmailProvider.Imap.Host.Should().Be("imap.gmail.com");
        gmailProvider.Imap.Port.Should().Be(993);
    }
    
    [Fact]
    public void EmailMessage_ShouldInitializeWithDefaults()
    {
        // Arrange & Act
        var message = new EmailMessage();
        
        // Assert
        message.Id.Should().NotBeNullOrEmpty();
        message.To.Should().BeEmpty();
        message.Cc.Should().BeEmpty();
        message.Bcc.Should().BeEmpty();
        message.Attachments.Should().BeEmpty();
        message.IsEncrypted.Should().BeFalse();
        message.EncryptionVersion.Should().Be("1.0");
    }
}