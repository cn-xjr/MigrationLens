-- Authored index-maintenance workflow; review only, not executed by the CLI.
BEGIN ISOLATION LEVEL READ COMMITTED, READ WRITE, NOT DEFERRABLE;
SET LOCAL lock_timeout = 100;
ALTER INDEX public.events_id_idx RENAME TO events_id_new_idx;
COMMIT;
CREATE INDEX CONCURRENTLY events_time_idx ON events (created_at);
