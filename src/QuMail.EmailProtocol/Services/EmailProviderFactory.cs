using Microsoft.Extensions.Logging;
using QuMail.EmailProtocol.Configuration;
using QuMail.EmailProtocol.Interfaces;

namespace QuMail.EmailProtocol.Services;

public interface IEmailProviderFactory
{
    SMTPCryptoWrapper CreateSmtpWrapper();
    // Future: IMAPCryptoWrapper CreateImapWrapper();
}

public class EmailProviderFactory : IEmailProviderFactory
{
    private readonly IOneTimePadEngine _cryptoEngine;
    private readonly IQuantumKeyManager _keyManager;
    private readonly ILoggerFactory _loggerFactory;
    private readonly EmailProviderSettings _settings;
    
    public EmailProviderFactory(
        IOneTimePadEngine cryptoEngine,
        IQuantumKeyManager keyManager,
        ILoggerFactory loggerFactory,
        EmailProviderSettings? settings = null)
    {
        _cryptoEngine = cryptoEngine ?? throw new ArgumentNullException(nameof(cryptoEngine));
        _keyManager = keyManager ?? throw new ArgumentNullException(nameof(keyManager));
        _loggerFactory = loggerFactory ?? throw new ArgumentNullException(nameof(loggerFactory));
        _settings = settings ?? new EmailProviderSettings 
        { 
            Providers = EmailProviderDefaults.DefaultProviders 
        };
    }
    
    public SMTPCryptoWrapper CreateSmtpWrapper()
    {
        var logger = _loggerFactory.CreateLogger<SMTPCryptoWrapper>();
        return new SMTPCryptoWrapper(_cryptoEngine, _keyManager, logger, _settings);
    }
}