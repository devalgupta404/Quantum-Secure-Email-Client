using Microsoft.EntityFrameworkCore;
using QuMail.EmailProtocol.Models;

namespace QuMail.EmailProtocol.Data;

public class AuthDbContext : DbContext
{
    public AuthDbContext(DbContextOptions<AuthDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users { get; set; }
    public DbSet<RefreshToken> RefreshTokens { get; set; }
    public DbSet<UserSession> UserSessions { get; set; }
    public DbSet<Email> Emails { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User entity configuration
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Email).IsUnique();
            entity.Property(e => e.Email).IsRequired().HasMaxLength(255);
            entity.Property(e => e.PasswordHash).IsRequired().HasMaxLength(255);
            entity.Property(e => e.Name).IsRequired().HasMaxLength(255);
            entity.Property(e => e.AvatarUrl).HasMaxLength(500);
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
            entity.Property(e => e.UpdatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
        });

        // RefreshToken entity configuration
        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.TokenHash);
            entity.HasIndex(e => e.ExpiresAt);
            entity.Property(e => e.TokenHash).IsRequired().HasMaxLength(255);
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");

            entity.HasOne(e => e.User)
                  .WithMany(u => u.RefreshTokens)
                  .HasForeignKey(e => e.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // UserSession entity configuration
        modelBuilder.Entity<UserSession>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.SessionToken).IsUnique();
            entity.HasIndex(e => e.ExpiresAt);
            entity.Property(e => e.SessionToken).IsRequired().HasMaxLength(255);
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");

            entity.HasOne(e => e.User)
                  .WithMany(u => u.UserSessions)
                  .HasForeignKey(e => e.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

            // Email entity configuration
            modelBuilder.Entity<Email>(entity =>
            {
                entity.ToTable("emails"); // Explicitly set table name to lowercase
                entity.HasKey(e => e.Id);
                entity.HasIndex(e => e.SenderEmail);
                entity.HasIndex(e => e.RecipientEmail);
                entity.HasIndex(e => e.SentAt);
                entity.Property(e => e.SenderEmail).IsRequired().HasMaxLength(255);
                entity.Property(e => e.RecipientEmail).IsRequired().HasMaxLength(255);
                entity.Property(e => e.Subject).IsRequired().HasMaxLength(500);
                entity.Property(e => e.Body).IsRequired();
                entity.Property(e => e.SentAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
                entity.Property(e => e.IsRead).HasDefaultValue(false);

            // Temporarily disable foreign key constraints to fix email sending
            // entity.HasOne(e => e.Sender)
            //       .WithMany()
            //       .HasForeignKey(e => e.SenderEmail)
            //       .HasPrincipalKey(u => u.Email)
            //       .OnDelete(DeleteBehavior.Restrict);

            // entity.HasOne(e => e.Recipient)
            //       .WithMany()
            //       .HasForeignKey(e => e.RecipientEmail)
            //       .HasPrincipalKey(u => u.Email)
            //       .OnDelete(DeleteBehavior.Restrict);
        });
    }

    public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        // Automatically update UpdatedAt for User entities
        var entries = ChangeTracker.Entries<User>()
            .Where(e => e.State == EntityState.Modified);

        foreach (var entry in entries)
        {
            entry.Entity.UpdatedAt = DateTime.UtcNow;
        }

        return await base.SaveChangesAsync(cancellationToken);
    }
}
