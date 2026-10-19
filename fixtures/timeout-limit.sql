-- Finite is not enough when the migration policy allows at most two seconds.
SET lock_timeout = '10s';
CREATE INDEX CONCURRENTLY events_id_idx ON events (id);
