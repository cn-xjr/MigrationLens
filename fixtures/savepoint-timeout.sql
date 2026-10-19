-- Authored regression: rollback cancels the finite local timeout.
BEGIN;
SET LOCAL lock_timeout = 0;
SAVEPOINT before_timeout;
SET LOCAL lock_timeout = '3s';
ROLLBACK TO before_timeout;
CREATE INDEX events_id_idx ON events (id);
COMMIT;
