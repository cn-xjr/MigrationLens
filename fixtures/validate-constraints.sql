-- Finish constraints installed as NOT VALID by a previously reviewed migration.
-- Existing rows must satisfy both constraints; this offline fixture does not
-- create constraints or assert that the catalog/data prerequisites hold.
SET lock_timeout = 100;
ALTER TABLE public.events
  VALIDATE CONSTRAINT events_positive_id,
  VALIDATE CONSTRAINT events_account_fk;
REINDEX INDEX CONCURRENTLY events_account_idx;
