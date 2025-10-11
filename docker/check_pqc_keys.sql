-- Check PQC public keys for users
SELECT 
    "Email", 
    CASE 
        WHEN "PqcPublicKey" IS NOT NULL AND LENGTH("PqcPublicKey") > 0 
        THEN 'YES' 
        ELSE 'NO' 
    END as has_pqc_key,
    CASE 
        WHEN "PqcKeyGeneratedAt" IS NOT NULL 
        THEN "PqcKeyGeneratedAt"::text
        ELSE 'NULL'
    END as key_generated_at
FROM "Users"
ORDER BY "Email";
