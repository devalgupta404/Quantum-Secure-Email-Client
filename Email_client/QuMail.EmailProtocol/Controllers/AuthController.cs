using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using QuMail.EmailProtocol.Models;
using QuMail.EmailProtocol.Data;
using QuMail.EmailProtocol.Services;
using QuMail.EmailProtocol.Configuration;
using System.Net.Mail;
using System.Net;

namespace QuMail.EmailProtocol.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<AuthController> _logger;

    public AuthController(AuthDbContext context, IConfiguration configuration, ILogger<AuthController> logger)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest request)
    {
        try
        {
            // Use original email as the primary app email; prevent duplicates by original email
            var originalEmail = request.ExternalEmail ?? request.Email;
            if (await _context.Users.AnyAsync(u => u.Email == originalEmail || u.ExternalEmail == originalEmail))
                return BadRequest(new { message = "User with this email already exists" });
            // Derive username when not provided
            var requestedUsername = request.Username;
            if (string.IsNullOrWhiteSpace(requestedUsername))
            {
                var localPartSource = originalEmail;
                var localPart = localPartSource.Split('@')[0];
                requestedUsername = localPart.Length >= 3 ? localPart : ($"user_{Guid.NewGuid().ToString("N").Substring(0,8)}");
            }
            // Ensure uniqueness; append suffix if needed
            var candidate = requestedUsername;
            int suffix = 0;
            while (await _context.Users.AnyAsync(u => u.Username == candidate))
            {
                suffix++;
                candidate = $"{requestedUsername}{suffix}";
            }
            requestedUsername = candidate;

            var passwordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);
            var user = new User
            {
                Id = Guid.NewGuid(),
                Email = originalEmail,
                Username = requestedUsername,
                PasswordHash = passwordHash,
                Name = request.Name,
                IsActive = true,
                EmailVerified = false,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            // Required external mapping and provider
            user.ExternalEmail = originalEmail;
            user.EmailProvider = request.EmailProvider;

            // Validate and store app password (required, exactly 16 chars)
            try
            {
                var isValid = await ValidateAppPasswordAsync(request.ExternalEmail!, request.AppPassword!, request.EmailProvider!);
                if (!isValid)
                {
                    return BadRequest(new { message = "Invalid app password for the specified email provider" });
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "SMTP validation failed, proceeding without validation");
                // Proceed even if SMTP check fails (network issues etc.)
            }
            // Store encrypted app password for SMTP use (not hash, needs reversal)
            user.AppPasswordHash = SecretProtector.Encrypt(request.AppPassword!);
            if (!string.IsNullOrWhiteSpace(request.OAuth2Token))
            {
                user.OAuth2Token = request.OAuth2Token;
            }

            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            var token = GenerateJwtToken(user);
            user.LastLoginAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return Ok(new AuthResponse
            {
                Token = token,
                User = new UserDto
                {
                    Id = user.Id,
                    Email = user.Email,
                    Name = user.Name,
                    Username = user.Username,
                    AvatarUrl = user.AvatarUrl
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during user registration");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request)
    {
        try
        {
            // Login using primary app email or original external email
            var user = await _context.Users.FirstOrDefaultAsync(u => (u.Email == request.Email || u.ExternalEmail == request.Email) && u.IsActive);

            if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
                return Unauthorized(new { message = "Invalid email or password" });

            var token = GenerateJwtToken(user);
            user.LastLoginAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return Ok(new AuthResponse
            {
                Token = token,
                User = new UserDto
                {
                    Id = user.Id,
                    Email = user.Email,
                    ExternalEmail = user.ExternalEmail,
                    EmailProvider = user.EmailProvider,
                    Name = user.Name,
                    Username = user.Username,
                    AvatarUrl = user.AvatarUrl
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during user login");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> RefreshToken()
    {
        try
        {
            var token = Request.Headers["Authorization"].FirstOrDefault()?.Split(" ").Last();
            if (string.IsNullOrEmpty(token))
                return Unauthorized(new { message = "Token is required" });

            var userId = ValidateJwtToken(token);
            if (userId == null)
                return Unauthorized(new { message = "Invalid token" });

            var user = await _context.Users.FindAsync(userId);
            if (user == null || !user.IsActive)
                return Unauthorized(new { message = "User not found or inactive" });

            var newToken = GenerateJwtToken(user);

            return Ok(new AuthResponse
            {
                Token = newToken,
                User = new UserDto
                {
                    Id = user.Id,
                    Email = user.Email,
                    ExternalEmail = user.ExternalEmail,
                    EmailProvider = user.EmailProvider,
                    Name = user.Name,
                    Username = user.Username,
                    AvatarUrl = user.AvatarUrl
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during token refresh");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        try
        {
            return Ok(new { message = "Logged out successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during logout");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpDelete("delete-account")]
    [Authorize]
    public async Task<IActionResult> DeleteAccount()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "Invalid token" });

            var user = await _context.Users.FindAsync(Guid.Parse(userId));
            if (user == null)
                return NotFound(new { message = "User not found" });

            // Delete all user-related data
            var userEmails = await _context.Emails
                .Where(e => e.SenderEmail == user.Email || e.RecipientEmail == user.Email)
                .ToListAsync();
            
            _context.Emails.RemoveRange(userEmails);
            
            // Remove refresh tokens and sessions
            var refreshTokens = await _context.RefreshTokens
                .Where(rt => rt.UserId == user.Id)
                .ToListAsync();
            _context.RefreshTokens.RemoveRange(refreshTokens);
            
            var userSessions = await _context.UserSessions
                .Where(us => us.UserId == user.Id)
                .ToListAsync();
            _context.UserSessions.RemoveRange(userSessions);
            
            // Finally, delete the user
            _context.Users.Remove(user);
            
            await _context.SaveChangesAsync();

            _logger.LogInformation($"User account deleted: {user.Email} (ID: {user.Id})");
            
            return Ok(new { message = "Account deleted successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during account deletion");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<ActionResult<UserDto>> GetCurrentUser()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "Invalid token" });

            var user = await _context.Users.FindAsync(Guid.Parse(userId));
            if (user == null || !user.IsActive)
                return Unauthorized(new { message = "User not found or inactive" });

            return Ok(new UserDto
            {
                Id = user.Id,
                Email = user.Email,
                ExternalEmail = user.ExternalEmail,
                EmailProvider = user.EmailProvider,
                Name = user.Name,
                AvatarUrl = user.AvatarUrl
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting current user");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    private string GenerateJwtToken(User user)
    {
        var jwtSettings = _configuration.GetSection("JwtSettings");
        var secret = Environment.GetEnvironmentVariable("JWT_SECRET_KEY") ?? jwtSettings["SecretKey"];
        if (string.IsNullOrWhiteSpace(secret))
            throw new InvalidOperationException("JWT secret key is not configured");

        var expiresEnv = Environment.GetEnvironmentVariable("JWT_EXPIRES_MINUTES");
        int expiresInMinutes;
        if (!int.TryParse(expiresEnv, out expiresInMinutes))
        {
            if (!int.TryParse(jwtSettings["ExpiresInMinutes"], out expiresInMinutes))
            {
                expiresInMinutes = 60; // sensible default
            }
        }

        var key = Encoding.ASCII.GetBytes(secret);
        var issuer = Environment.GetEnvironmentVariable("JWT_ISSUER") ?? jwtSettings["Issuer"];
        var audience = Environment.GetEnvironmentVariable("JWT_AUDIENCE") ?? jwtSettings["Audience"];

        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(new[]
            {
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Email, user.Email),
                new Claim(ClaimTypes.Name, user.Name),
                new Claim("username", user.Username),
                new Claim("email_verified", user.EmailVerified.ToString().ToLower())
            }),
            Expires = DateTime.UtcNow.AddMinutes(expiresInMinutes),
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature),
            Issuer = issuer,
            Audience = audience
        };

        var tokenHandler = new JwtSecurityTokenHandler();
        var token = tokenHandler.CreateToken(tokenDescriptor);
        return tokenHandler.WriteToken(token);
    }

    private Guid? ValidateJwtToken(string token)
    {
        try
        {
            var jwtSettings = _configuration.GetSection("JwtSettings");
            var key = Encoding.ASCII.GetBytes(jwtSettings["SecretKey"]!);

            var tokenHandler = new JwtSecurityTokenHandler();
            tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = jwtSettings["Issuer"],
                ValidateAudience = true,
                ValidAudience = jwtSettings["Audience"],
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            }, out SecurityToken validatedToken);

            var jwtToken = (JwtSecurityToken)validatedToken;
            var userId = jwtToken.Claims.First(x => x.Type == ClaimTypes.NameIdentifier).Value;
            return Guid.Parse(userId);
        }
        catch
        {
            return null;
        }
    }

    private async Task<bool> ValidateAppPasswordAsync(string email, string appPassword, string provider)
    {
        try
        {
            // Get provider settings
            if (!EmailProviderDefaults.DefaultProviders.TryGetValue(provider, out var emailProvider))
            {
                return false;
            }

            var smtp = emailProvider.Smtp;
            
            // Create SMTP client with provider settings
            using var client = new SmtpClient(smtp.Host, smtp.Port)
            {
                EnableSsl = smtp.EnableSsl,
                DeliveryMethod = SmtpDeliveryMethod.Network,
                UseDefaultCredentials = false,
                Credentials = new NetworkCredential(email, appPassword),
                Timeout = 10000 // 10 second timeout
            };

            // Test connection by attempting to send a test message (but don't actually send)
            // We'll use a simple connection test instead
            await client.SendMailAsync(new MailMessage
            {
                From = new MailAddress(email),
                To = { new MailAddress(email) }, // Send to self
                Subject = "QuMail App Password Test",
                Body = "This is a test message to verify your app password.",
                IsBodyHtml = false
            });

            return true;
        }
        catch (SmtpException ex) when (ex.StatusCode == SmtpStatusCode.MustIssueStartTlsFirst || 
                                       ex.StatusCode == SmtpStatusCode.GeneralFailure ||
                                       ex.Message.Contains("authentication") ||
                                       ex.Message.Contains("credentials"))
        {
            // Invalid credentials
            return false;
        }
        catch (Exception)
        {
            // Other errors (network, etc.) - we'll be conservative and return false
            return false;
        }
    }

    [HttpGet("pqc-keys")]
    [Authorize]
    public async Task<IActionResult> GetPqcKeys()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "Invalid token" });

            var user = await _context.Users.FindAsync(Guid.Parse(userId));
            if (user == null)
                return NotFound(new { message = "User not found" });

            if (string.IsNullOrEmpty(user.PqcPublicKey) || string.IsNullOrEmpty(user.PqcPrivateKey))
                return NotFound(new { message = "No PQC keys found for user" });

            return Ok(new
            {
                success = true,
                data = new
                {
                    publicKey = user.PqcPublicKey,
                    privateKey = user.PqcPrivateKey,
                    keyGeneratedAt = user.PqcKeyGeneratedAt
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving PQC keys");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    [HttpPost("pqc-keys")]
    [Authorize]
    public async Task<IActionResult> SavePqcKeys([FromBody] SavePqcKeysRequest request)
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "Invalid token" });

            var user = await _context.Users.FindAsync(Guid.Parse(userId));
            if (user == null)
                return NotFound(new { message = "User not found" });

            if (string.IsNullOrEmpty(request.PublicKey) || string.IsNullOrEmpty(request.PrivateKey))
                return BadRequest(new { message = "Public key and private key are required" });

            user.PqcPublicKey = request.PublicKey;
            user.PqcPrivateKey = request.PrivateKey;
            user.PqcKeyGeneratedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            _logger.LogInformation($"PQC keys saved for user: {user.Email}");

            return Ok(new { success = true, message = "PQC keys saved successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving PQC keys");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }
}

public class SavePqcKeysRequest
{
    public string PublicKey { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
}
