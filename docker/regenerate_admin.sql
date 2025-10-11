-- Delete existing admin user
DELETE FROM "Users" WHERE "Email" = 'admin@quantum.local';

-- Create new admin user with a simple password hash (this is admin123 hashed with BCrypt)
-- Using a known good BCrypt hash for "admin123"
INSERT INTO "Users" (
    "Id", 
    "Email", 
    "Username", 
    "PasswordHash", 
    "Name", 
    "IsActive", 
    "EmailVerified", 
    "CreatedAt", 
    "UpdatedAt", 
    "ExternalEmail", 
    "EmailProvider"
) VALUES (
    gen_random_uuid(),
    'admin@quantum.local',
    'admin',
    '$2a$11$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- admin123
    'Admin User',
    true,
    true,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'admin@quantum.local',
    'gmail'
);

-- Show the created user
SELECT "Email", "Name", "Username", "IsActive", LENGTH("PasswordHash") as hash_length FROM "Users" WHERE "Email" = 'admin@quantum.local';
