-- Finish an existing CHECK-based non-null rollout before adding uniqueness.
-- Assumes orders_key_nn is an enforced, previously installed CHECK that proves
-- external_key IS NOT NULL. Data repair and proof eligibility are not inferred.
SET lock_timeout = 100;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_key_nn;
ALTER TABLE public.orders ALTER COLUMN external_key SET NOT NULL;
CREATE UNIQUE INDEX CONCURRENTLY orders_key_idx ON public.orders(external_key);
ALTER TABLE public.orders ADD CONSTRAINT orders_key UNIQUE USING INDEX orders_key_idx;
