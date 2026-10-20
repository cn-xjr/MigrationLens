-- Authored standalone maintenance after index replacement; review only.
SET lock_timeout = 100;
REINDEX INDEX CONCURRENTLY public.events_id_idx;
VACUUM (ANALYZE, INDEX_CLEANUP ON, TRUNCATE FALSE, SKIP_LOCKED) public.events (id);
