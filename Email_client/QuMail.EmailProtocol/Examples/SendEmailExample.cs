using Microsoft.Extensions.Logging;
using QuMail.EmailProtocol.Configuration;
using QuMail.EmailProtocol.Mocks;
using QuMail.EmailProtocol.Models;
using QuMail.EmailProtocol.Services;

namespace QuMail.EmailProtocol.Examples;

public class SendEmailExample
{
    public static async Task RunExample()
    {
        // Setup real implementations
        var cryptoEngine = new Level1OneTimePadEngine();
        var keyManager = new MockQuantumKeyManager();
        var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
        var logger = loggerFactory.CreateLogger<SMTPCryptoWrapper>();
        
        // Create SMTP wrapper
        var smtpWrapper = new SMTPCryptoWrapper(cryptoEngine, keyManager, logger);
        
        // Create email message
        var message = new EmailMessage
        {
            From = "sender@gmail.com",
            To = new List<string> { "recipient@gmail.com" },
            Subject = "Quantum Encrypted Test Email",
            Body = "This is a test email encrypted with quantum one-time pad encryption.",
            IsHtml = false,
            Attachments = new List<EmailAttachment>
            {
                new EmailAttachment
                {
                    FileName = "test-document.txt",
                    Content = System.Text.Encoding.UTF8.GetBytes("Secret document content"),
                    ContentType = "text/plain"
                }
            }
        };
        
        // Create credentials (use app password for Gmail)
        var credentials = new EmailAccountCredentials
        {
            Email = "your-email@gmail.com",
            Password = "your-app-password", // Use Gmail App Password
            Provider = "gmail"
        };
        
        try
        {
            // Send encrypted email
            var success = await smtpWrapper.SendEncryptedEmailAsync(message, credentials);
            
            if (success)
            {
                Console.WriteLine("Email sent successfully!");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Failed to send email: {ex.Message}");
        }
    }
}