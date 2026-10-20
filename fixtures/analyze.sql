-- Authored post-index statistics refresh; the CLI reviews without database I/O.
SET lock_timeout = 100;
CREATE INDEX CONCURRENTLY events_time_idx ON events (created_at);
ANALYZE (VERBOSE FALSE, SKIP_LOCKED TRUE) public.events (created_at);
