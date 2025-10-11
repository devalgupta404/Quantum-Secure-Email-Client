-- Fix subject column size to accommodate PQC encrypted content
ALTER TABLE emails ALTER COLUMN "Subject" TYPE TEXT;
