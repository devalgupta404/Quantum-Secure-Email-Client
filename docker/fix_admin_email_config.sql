-- Update admin user with proper email configuration for testing
-- Note: This uses a dummy app password for testing - in production you'd use real Gmail app password

UPDATE "Users" 
SET 
    "AppPasswordHash" = 'dGVzdGFwcHBhc3N3b3JkMTIzNDU2Nzg5MDEyMzQ1Ng==:dGVzdGVuY3J5cHRpb25rZXkxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Ng==',
    "ExternalEmail" = 'admin@quantum.local',
    "EmailProvider" = 'gmail'
WHERE "Email" = 'admin@quantum.local';

-- Show updated admin user
SELECT 
    "Email", 
    "ExternalEmail", 
    "EmailProvider", 
    CASE 
        WHEN "AppPasswordHash" IS NOT NULL AND LENGTH("AppPasswordHash") > 0 
        THEN 'YES' 
        ELSE 'NO' 
    END as has_app_password
FROM "Users" 
WHERE "Email" = 'admin@quantum.local';
