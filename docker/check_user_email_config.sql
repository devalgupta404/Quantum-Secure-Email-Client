-- Check user email configuration
SELECT 
    "Email", 
    "ExternalEmail", 
    "EmailProvider", 
    CASE 
        WHEN "AppPasswordHash" IS NOT NULL AND LENGTH("AppPasswordHash") > 0 
        THEN 'YES' 
        ELSE 'NO' 
    END as has_app_password,
    CASE 
        WHEN "OAuth2Token" IS NOT NULL AND LENGTH("OAuth2Token") > 0 
        THEN 'YES' 
        ELSE 'NO' 
    END as has_oauth_token
FROM "Users"
ORDER BY "Email";
