-- Releasing a savepoint keeps the session change: timeout remains disabled.
-- Expected review: ML201 at the separately dispatched concurrent index.
SET lock_timeout = 100;
BEGIN;
SAVEPOINT budget;
SET SESSION lock_timeout = 0;
RELEASE SAVEPOINT budget;
COMMIT;
CREATE INDEX CONCURRENTLY events_release_idx ON public.events(id);
