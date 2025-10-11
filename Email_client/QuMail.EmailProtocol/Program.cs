using QuMail.EmailProtocol.Services;
using QuMail.EmailProtocol.Data;
using QuMail.EmailProtocol.Interfaces;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using Microsoft.OpenApi.Models;
using DotNetEnv;

// Load environment variables from a .env file by searching upwards for repo root
try
{
    static string? FindEnvFile()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 6 && !string.IsNullOrEmpty(dir); i++)
        {
            var envPath = Path.Combine(dir, ".env");
            if (File.Exists(envPath)) return envPath;
            dir = Directory.GetParent(dir)?.FullName ?? string.Empty;
        }
        return null;
    }

    var envFile = FindEnvFile();
    if (!string.IsNullOrEmpty(envFile))
    {
        Env.Load(envFile);
    }
}
catch { /* non-fatal */ }

var builder = WebApplication.CreateBuilder(args);

// Build connection string from environment variables
var connectionString = $"Host={Environment.GetEnvironmentVariable("DB_HOST")};Port={Environment.GetEnvironmentVariable("DB_PORT")};Database={Environment.GetEnvironmentVariable("DB_NAME")};Username={Environment.GetEnvironmentVariable("DB_USERNAME")};Password={Environment.GetEnvironmentVariable("DB_PASSWORD")}";

// Get JWT settings from environment variables
var jwtSecretKey = Environment.GetEnvironmentVariable("JWT_SECRET_KEY");
var jwtIssuer = Environment.GetEnvironmentVariable("JWT_ISSUER");
var jwtAudience = Environment.GetEnvironmentVariable("JWT_AUDIENCE");

// Add services
builder.Services.AddControllers();

// Register Key Manager (IMPORTANT: Required for PQC)
builder.Services.AddSingleton<IQuantumKeyManager, SecureKeyManager>();

// Register Level 3 PQC services (original)
builder.Services.AddSingleton<Level3KyberPQC>();
builder.Services.AddScoped<IOneTimePadEngine, Level1OneTimePadEngine>();
builder.Services.AddScoped<Level3PQCEmailService>();

// Register Enhanced PQC services (Kyber-1024, McEliece, AES-256 hybrid)
builder.Services.AddSingleton<Level3EnhancedPQC>();
builder.Services.AddScoped<Level3HybridEncryption>();

// Add Entity Framework
builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseNpgsql(connectionString));

// Add JWT Authentication
var jwtSettings = builder.Configuration.GetSection("JwtSettings");
var key = Encoding.ASCII.GetBytes(jwtSecretKey);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = false; // Only for development
    options.SaveToken = true;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(key),
        ValidateIssuer = true,
        ValidIssuer = jwtIssuer,
        ValidateAudience = true,
        ValidAudience = jwtAudience,
        ValidateLifetime = true,
        ClockSkew = TimeSpan.Zero
    };
});

// Add Authorization
builder.Services.AddAuthorization();

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("FlutterApp", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

// Add Swagger/OpenAPI
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "QuMail API", Version = "v1" });
    
    // Add JWT authentication to Swagger
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header using the Bearer scheme. Example: \"Authorization: Bearer {token}\"",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });
    
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// Run database migrations
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
    try
    {
        context.Database.Migrate();
        Console.WriteLine("Database migrations applied successfully.");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Error applying database migrations: {ex.Message}");
    }
}

// Configure pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "QuMail API V1");
    });
}

app.UseCors("FlutterApp");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Simple health check
app.MapGet("/api/health", () => "OK");

// Change API port to 5001 to avoid collisions when 5000 is occupied
app.Run("http://0.0.0.0:5001");
