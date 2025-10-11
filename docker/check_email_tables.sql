-- Check all tables in the database
\dt

-- Check emails table structure
\d emails

-- Check Users table structure  
\d Users

-- Check if there are any emails in the database
SELECT COUNT(*) as total_emails FROM emails;

-- Check email-related fields in Users table
SELECT 
    "Email", 
    "ExternalEmail", 
    "EmailProvider", 
    "AppPasswordHash",
    "OAuth2Token",
    "IsActive"
FROM "Users" 
LIMIT 5;
