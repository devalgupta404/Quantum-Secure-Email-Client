using System.ComponentModel.DataAnnotations;

namespace QuMail.EmailProtocol.Models;

public class LoginRequest
{
    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MinLength(6)]
    public string Password { get; set; } = string.Empty;
}

public class RegisterRequest
{
    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MinLength(6)]
    public string Password { get; set; } = string.Empty;

    [Required]
    [StringLength(255, MinimumLength = 2)]
    public string Name { get; set; } = string.Empty;

    // App username for our platform (optional; will be derived from email if missing)
    [StringLength(255, MinimumLength = 3)]
    public string? Username { get; set; }

    // External email mapping (optional at signup)
    [EmailAddress]
    public string? ExternalEmail { get; set; }

    // Preferred provider key: gmail | yahoo | outlook
    [StringLength(50)]
    public string? EmailProvider { get; set; }

    // Exactly 16 chars if provided (store hash server-side)
    [StringLength(16, MinimumLength = 16)]
    public string? AppPassword { get; set; }

    // Alternative to AppPassword
    [StringLength(2048)]
    public string? OAuth2Token { get; set; }
}

public class AuthResponse
{
    public string Token { get; set; } = string.Empty;
    public UserDto User { get; set; } = new UserDto();
}

public class UserDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string? AvatarUrl { get; set; }
}
