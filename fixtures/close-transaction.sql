-- Authored regression: dispatch matters after ending the caller transaction.
COMMIT;
CREATE INDEX CONCURRENTLY events_id_idx ON events (id);
