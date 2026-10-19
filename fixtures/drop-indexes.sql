-- A concurrent cleanup must not combine names or use CASCADE.
DROP INDEX CONCURRENTLY IF EXISTS public.events_old_idx, public.events_legacy_idx;
