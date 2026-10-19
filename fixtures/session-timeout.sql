-- Authored workflow: dispatch each statement separately.
SET lock_timeout = '3s';
CREATE INDEX CONCURRENTLY events_id_idx ON events (id);
