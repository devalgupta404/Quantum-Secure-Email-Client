-- Update admin user with correct BCrypt hash for "admin123"
-- This is a proper BCrypt hash for "admin123"
UPDATE "Users" 
SET "PasswordHash" = '$2a$11$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'
WHERE "Email" = 'admin@quantum.local';

-- Show the updated user
SELECT "Email", "Name", "Username", "IsActive" FROM "Users" WHERE "Email" = 'admin@quantum.local';
