using System.ComponentModel.DataAnnotations;

namespace QuMail.EmailProtocol.Models;

public class Email
{
    public Guid Id { get; set; }
    
    [Required]
    [MaxLength(255)]
    public string SenderEmail { get; set; } = string.Empty;
    
    [Required]
    [MaxLength(255)]
    public string RecipientEmail { get; set; } = string.Empty;
    
    [Required]
    [MaxLength(500)]
    public string Subject { get; set; } = string.Empty;
    
    [Required]
    public string Body { get; set; } = string.Empty;
    
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    
    public bool IsRead { get; set; } = false;
    
    // Navigation properties removed to avoid foreign key constraints
    // public User? Sender { get; set; }
    // public User? Recipient { get; set; }
}
