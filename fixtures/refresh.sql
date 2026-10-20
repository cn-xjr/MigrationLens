-- Offline review of an existing populated materialized view after index changes.
-- The UNIQUE index prerequisite is a catalog assumption, not a linter proof.
SET lock_timeout = 100;
REINDEX INDEX CONCURRENTLY order_summary_key;
REFRESH MATERIALIZED VIEW CONCURRENTLY public.order_summary WITH DATA;
ANALYZE public.order_summary;
