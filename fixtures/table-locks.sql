-- Authored index-maintenance workflow; offline review does not execute SQL.
BEGIN;
SET LOCAL lock_timeout = '2s';
LOCK TABLE ONLY public.events IN SHARE MODE NOWAIT;
CREATE INDEX events_created_at_idx ON public.events (created_at);
COMMIT;
CREATE INDEX CONCURRENTLY events_id_idx ON public.events (id);
