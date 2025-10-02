namespace QuMail.EmailProtocol.Configuration;

public class EmailProviderSettings
{
    public Dictionary<string, EmailProvider> Providers { get; set; } = new();
}

public class EmailProvider
{
    public string Name { get; set; } = string.Empty;
    public SmtpSettings Smtp { get; set; } = new();
    public ImapSettings Imap { get; set; } = new();
}

public class SmtpSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public bool EnableSsl { get; set; } = true;
    public AuthenticationType AuthType { get; set; } = AuthenticationType.Password;
}

public class ImapSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public bool EnableSsl { get; set; } = true;
    public AuthenticationType AuthType { get; set; } = AuthenticationType.Password;
}

public enum AuthenticationType
{
    Password,
    OAuth2,
    AppPassword
}

public class EmailAccountCredentials
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string? OAuth2Token { get; set; }
    public string Provider { get; set; } = "gmail";
}

// Pre-configured providers
public static class EmailProviderDefaults
{
    public static readonly Dictionary<string, EmailProvider> DefaultProviders = new()
    {
        ["gmail"] = new EmailProvider
        {
            Name = "Gmail",
            Smtp = new SmtpSettings
            {
                Host = "smtp.gmail.com",
                Port = 587,
                EnableSsl = true,
                AuthType = AuthenticationType.AppPassword
            },
            Imap = new ImapSettings
            {
                Host = "imap.gmail.com",
                Port = 993,
                EnableSsl = true,
                AuthType = AuthenticationType.AppPassword
            }
        },
        ["yahoo"] = new EmailProvider
        {
            Name = "Yahoo",
            Smtp = new SmtpSettings
            {
                Host = "smtp.mail.yahoo.com",
                Port = 587,
                EnableSsl = true,
                AuthType = AuthenticationType.AppPassword
            },
            Imap = new ImapSettings
            {
                Host = "imap.mail.yahoo.com",
                Port = 993,
                EnableSsl = true,
                AuthType = AuthenticationType.AppPassword
            }
        },
        ["outlook"] = new EmailProvider
        {
            Name = "Outlook",
            Smtp = new SmtpSettings
            {
                Host = "smtp-mail.outlook.com",
                Port = 587,
                EnableSsl = true,
                AuthType = AuthenticationType.Password
            },
            Imap = new ImapSettings
            {
                Host = "outlook.office365.com",
                Port = 993,
                EnableSsl = true,
                AuthType = AuthenticationType.Password
            }
        }
    };
}