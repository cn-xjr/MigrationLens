-- This offline example reviews a replacement without inferring catalog facts.
SET lock_timeout = '2s';
CREATE INDEX CONCURRENTLY events_id_replacement ON events (id);
DROP INDEX CONCURRENTLY events_id_idx;
ALTER INDEX events_id_replacement RENAME TO events_id_idx;
