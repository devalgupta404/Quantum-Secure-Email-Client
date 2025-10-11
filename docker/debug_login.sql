-- Check if admin user exists and get details
SELECT 
    "Email", 
    "Username", 
    "IsActive", 
    "EmailVerified",
    LENGTH("PasswordHash") as hash_length,
    SUBSTRING("PasswordHash", 1, 20) as hash_start
FROM "Users" 
WHERE "Email" = 'admin@quantum.local';

-- Count total users
SELECT COUNT(*) as total_users FROM "Users";
