-- Offline review: reorder an existing table, then refresh planner statistics.
-- Assumes events_id already indexes public.events; catalog checks are required.
SET lock_timeout = 100;
CLUSTER (VERBOSE FALSE) public.events USING events_id;
ANALYZE public.events;
