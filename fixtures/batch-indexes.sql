-- Authored regression case: compare separate dispatch with a single query.
CREATE INDEX CONCURRENTLY first_idx ON events (id);
CREATE INDEX CONCURRENTLY second_idx ON events (id);
