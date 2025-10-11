-- Check recent emails in the database
SELECT 
    "Id", 
    "SenderEmail", 
    "RecipientEmail", 
    "Subject", 
    "EncryptionMethod", 
    "SentAt"
FROM emails 
ORDER BY "SentAt" DESC 
LIMIT 3;
