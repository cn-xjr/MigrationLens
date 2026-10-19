-- Separately dispatch the session setting and rebuild to avoid an implicit block.
SET lock_timeout = '2s';
REINDEX INDEX CONCURRENTLY public.events_id_idx;
