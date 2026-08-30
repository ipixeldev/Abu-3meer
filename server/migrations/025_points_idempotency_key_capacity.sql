-- 025_points_idempotency_key_capacity.sql
-- Challenge IDs may be up to 100 characters. Their deterministic award key
-- also includes a prefix and Firebase/PostgreSQL user identifier, so retain
-- enough room for the complete key instead of rejecting a valid answer.

ALTER TABLE point_transactions
    ALTER COLUMN idempotency_key TYPE VARCHAR(255);
