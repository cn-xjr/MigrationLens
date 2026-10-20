-- Authored storage-placement review; no catalog or filesystem is queried.
SET lock_timeout = '2s';
ALTER INDEX IF EXISTS public.events_id_idx SET TABLESPACE pg_default;
REINDEX INDEX CONCURRENTLY public.events_id_idx;
