-- Install an FK without scanning historical rows in the installation phase.
-- Run the later validation phase only after independently checking/repairing data.
SET lock_timeout = 100;
ALTER TABLE public.orders ADD CONSTRAINT orders_account_fk
  FOREIGN KEY (account_id) REFERENCES public.accounts(id) NOT VALID;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_account_fk;
CREATE INDEX CONCURRENTLY orders_account_idx ON public.orders(account_id);
