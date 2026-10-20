-- Add uniqueness in two phases on an existing orders table.
-- This offline review does not establish index eligibility or data uniqueness.
SET lock_timeout = 100;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_key_idx ON public.orders(external_key);
ALTER TABLE public.orders
  ADD CONSTRAINT orders_external_key UNIQUE USING INDEX orders_external_key_idx;
