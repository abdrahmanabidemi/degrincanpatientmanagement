
-- Idempotency table for Paystack payment references.
-- Both the verify endpoint and the webhook insert into this table BEFORE
-- applying an upgrade. The UNIQUE constraint on `reference` guarantees a
-- given Paystack transaction can only ever upgrade a clinic once, regardless
-- of how many times the verify endpoint and the webhook fire for it.

CREATE TABLE IF NOT EXISTS public.payment_references (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  user_id uuid NOT NULL,
  plan text NOT NULL,
  billing text NOT NULL,
  amount_kobo integer NOT NULL,
  source text NOT NULL,                  -- 'verify' or 'webhook'
  processed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_references_user_id_idx
  ON public.payment_references (user_id);

ALTER TABLE public.payment_references ENABLE ROW LEVEL SECURITY;

-- Only service role writes to this table from edge functions; clients can
-- read their own references for support / debugging if ever needed, but no
-- one can insert/update/delete from the client.
CREATE POLICY "Users read own payment references"
  ON public.payment_references
  FOR SELECT
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::public.app_role));
