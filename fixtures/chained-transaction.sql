-- The new transaction discards the previous SET LOCAL override.
SET lock_timeout = '2s';
BEGIN;
SET LOCAL lock_timeout = 0;
COMMIT AND CHAIN;
COMMIT;
CREATE INDEX CONCURRENTLY events_id_idx ON events (id);
