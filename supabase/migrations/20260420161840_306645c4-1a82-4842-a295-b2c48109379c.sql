
-- Allow the clinic billing self-update guard to accept either a monthly (+30d)
-- or yearly (+365d) expiry when the user-triggered Paystack upgrade path runs.
CREATE OR REPLACE FUNCTION public.prevent_clinic_billing_self_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id = OLD.user_id
     AND NEW.user_id = auth.uid()
     AND (
       (NEW.plan = 'Pro'::public.clinic_plan   AND NEW.patient_limit = 100)
       OR
       (NEW.plan = 'Scale'::public.clinic_plan AND NEW.patient_limit = 400)
     )
     AND NEW.status = 'active'::public.clinic_status
     AND (
       NEW.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
       OR NEW.expiry_date = (CURRENT_DATE + INTERVAL '365 days')::date
     )
  THEN
    RETURN NEW;
  END IF;

  IF NEW.plan IS DISTINCT FROM OLD.plan
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.expiry_date IS DISTINCT FROM OLD.expiry_date
     OR NEW.patient_limit IS DISTINCT FROM OLD.patient_limit
     OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Only administrators can modify subscription or billing fields';
  END IF;

  RETURN NEW;
END;
$function$;

-- Extend the admin upgrade RPC to accept an optional billing period.
CREATE OR REPLACE FUNCTION public.admin_upgrade_clinic_plan(_user_id uuid, _plan text, _billing text DEFAULT 'monthly')
 RETURNS clinics
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_limit integer;
  v_plan  public.clinic_plan;
  v_row   public.clinics;
  v_days  integer;
BEGIN
  IF _user_id IS NULL THEN
    RAISE EXCEPTION 'Missing user id';
  END IF;

  IF _plan IN ('Pro', 'Basic') THEN
    v_plan := 'Pro'::public.clinic_plan;
    v_limit := 100;
  ELSIF _plan IN ('Scale', 'Growth') THEN
    v_plan := 'Scale'::public.clinic_plan;
    v_limit := 400;
  ELSE
    RAISE EXCEPTION 'Invalid plan';
  END IF;

  IF _billing = 'yearly' THEN
    v_days := 365;
  ELSE
    v_days := 30;
  END IF;

  UPDATE public.clinics
     SET plan = v_plan,
         patient_limit = v_limit,
         status = 'active'::public.clinic_status,
         expiry_date = (CURRENT_DATE + (v_days || ' days')::interval)::date,
         updated_at = now()
   WHERE user_id = _user_id
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'No clinic found for user';
  END IF;

  RETURN v_row;
END;
$function$;

-- Keep the self-serve RPC in sync (used by admins-as-self / legacy callers).
CREATE OR REPLACE FUNCTION public.upgrade_clinic_plan(_plan text, _billing text DEFAULT 'monthly')
 RETURNS clinics
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer;
  v_plan public.clinic_plan;
  v_row public.clinics;
  v_days integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF _plan IN ('Pro', 'Basic') THEN
    v_plan := 'Pro'::public.clinic_plan;
    v_limit := 100;
  ELSIF _plan IN ('Scale', 'Growth') THEN
    v_plan := 'Scale'::public.clinic_plan;
    v_limit := 400;
  ELSE
    RAISE EXCEPTION 'Invalid plan';
  END IF;

  IF _billing = 'yearly' THEN
    v_days := 365;
  ELSE
    v_days := 30;
  END IF;

  UPDATE public.clinics
     SET plan = v_plan,
         patient_limit = v_limit,
         status = 'active'::public.clinic_status,
         expiry_date = (CURRENT_DATE + (v_days || ' days')::interval)::date,
         updated_at = now()
   WHERE user_id = v_uid
   RETURNING * INTO v_row;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No clinic found for current user';
  END IF;

  RETURN v_row;
END;
$function$;
