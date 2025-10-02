# QuMail Email Protocol Layer

This module provides the email protocol integration for the QuMail quantum-secure email client. It handles SMTP/IMAP communication with standard email providers while applying quantum one-time pad encryption.

## Project Structure

```
QuMail.EmailProtocol/
├── Configuration/        # Email provider settings and defaults
├── Interfaces/          # Core crypto interfaces (from Developer A)
├── Mocks/              # Mock implementations for testing
├── Models/             # Email message and attachment models
├── Services/           # SMTP/IMAP crypto wrappers
└── Examples/           # Usage examples
```

## Key Components

### SMTPCryptoWrapper
- Encrypts email content using quantum keys
- Sends encrypted emails via standard SMTP
- Supports Gmail, Yahoo, and Outlook
- Preserves email compatibility for non-quantum clients

### Mock Implementations
- `MockOneTimePadEngine`: Simple XOR encryption for testing
- `MockQuantumKeyManager`: Generates random keys for testing
- Allows immediate development without waiting for crypto team

### Email Format
Encrypted emails contain:
- Standard email headers (preserved)
- Custom headers: X-QuMail-Encrypted, X-QuMail-KeyId
- Base64-encoded encrypted body
- Encrypted attachments with .qenc extension

## Usage Example

```csharp
// Create wrapper with mock implementations
var cryptoEngine = new MockOneTimePadEngine();
var keyManager = new MockQuantumKeyManager();
var smtpWrapper = new SMTPCryptoWrapper(cryptoEngine, keyManager, logger);

// Send encrypted email
var message = new EmailMessage
{
    To = new List<string> { "recipient@gmail.com" },
    Subject = "Quantum Encrypted Email",
    Body = "Secret message content"
};

var credentials = new EmailAccountCredentials
{
    Email = "sender@gmail.com",
    Password = "app-password",
    Provider = "gmail"
};

await smtpWrapper.SendEncryptedEmailAsync(message, credentials);
```

## Gmail Setup

1. Enable 2-factor authentication
2. Generate an App Password: https://myaccount.google.com/apppasswords
3. Use the app password in credentials

## Testing

Run unit tests:
```bash
dotnet test tests/QuMail.EmailProtocol.Tests
```

## Integration Points

- **Crypto Team (Developer A)**: Swap mock implementations with real `IOneTimePadEngine` and `IQuantumKeyManager`
- **UI Team (Developer C)**: Use `EmailProviderFactory` to create wrappers and send emails

## Next Steps

1. Implement IMAPCryptoWrapper for receiving emails
2. Add OAuth2 support
3. Implement email synchronization
4. Add retry logic and better error handling