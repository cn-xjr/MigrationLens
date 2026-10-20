-- A storage move still needs review even when rebuilding concurrently.
SET lock_timeout = '2s';
REINDEX (CONCURRENTLY TRUE, VERBOSE, TABLESPACE fast_indexes) INDEX public.events_id_idx;
