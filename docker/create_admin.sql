-- Create admin user with hashed password (admin123)
INSERT INTO "Users" ("Id", "Email", "Username", "PasswordHash", "Name", "IsActive", "EmailVerified", "CreatedAt", "UpdatedAt", "ExternalEmail", "EmailProvider")
VALUES (
    gen_random_uuid(),
    'admin@quantum.local',
    'admin',
    '$2a$11$rQZ8K9vM7N2pL3xW1sT4eO5qR6yU8iA0bC2dE4fG6hI9jK1lM3nP5rS7tV9wX', -- admin123
    'Admin User',
    true,
    true,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'admin@quantum.local',
    'gmail'
);

-- Show all users
SELECT "Email", "Name", "Username", "IsActive" FROM "Users";
