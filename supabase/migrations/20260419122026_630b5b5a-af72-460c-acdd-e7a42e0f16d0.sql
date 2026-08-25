
-- Backfill existing rows safely by temporarily disabling the billing-guard trigger.
ALTER TABLE public.clinics DISABLE TRIGGER prevent_clinic_billing_self_update_trg;

UPDATE public.clinics SET plan = 'Pro'::public.clinic_plan, patient_limit = 100
  WHERE plan = 'Basic'::public.clinic_plan;
UPDATE public.clinics SET plan = 'Scale'::public.clinic_plan, patient_limit = 400
  WHERE plan = 'Growth'::public.clinic_plan;
UPDATE public.clinics SET patient_limit = 400
  WHERE plan = 'Scale'::public.clinic_plan AND patient_limit <> 400;

ALTER TABLE public.clinics ENABLE TRIGGER prevent_clinic_billing_self_update_trg;

-- Update the trigger that derives patient_limit from plan
CREATE OR REPLACE FUNCTION public.enforce_patient_limit_from_plan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.patient_limit IS NULL THEN
    NEW.patient_limit := 5;
  END IF;

  IF NEW.plan = 'Pro'::public.clinic_plan THEN
    NEW.patient_limit := 100;
  ELSIF NEW.plan = 'Scale'::public.clinic_plan THEN
    NEW.patient_limit := 400;
  ELSIF NEW.plan = 'Basic'::public.clinic_plan THEN
    NEW.patient_limit := 100;
  ELSIF NEW.plan = 'Growth'::public.clinic_plan THEN
    NEW.patient_limit := 400;
  ELSE
    NEW.patient_limit := 5;
  END IF;

  RETURN NEW;
END;
$function$;

-- Update self-upgrade guard to accept the new (plan, patient_limit) pairs
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
     AND NEW.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
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

-- Update upgrade_clinic_plan to accept Pro/Scale (legacy aliases retained)
CREATE OR REPLACE FUNCTION public.upgrade_clinic_plan(_plan text)
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

  UPDATE public.clinics
     SET plan = v_plan,
         patient_limit = v_limit,
         status = 'active'::public.clinic_status,
         expiry_date = CURRENT_DATE + INTERVAL '30 days',
         updated_at = now()
   WHERE user_id = v_uid
   RETURNING * INTO v_row;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No clinic found for current user';
  END IF;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upgrade_clinic_plan(_user_id uuid, _plan text)
 RETURNS clinics
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_limit integer;
  v_plan  public.clinic_plan;
  v_row   public.clinics;
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

  UPDATE public.clinics
     SET plan = v_plan,
         patient_limit = v_limit,
         status = 'active'::public.clinic_status,
         expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date,
         updated_at = now()
   WHERE user_id = _user_id
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'No clinic found for user';
  END IF;

  RETURN v_row;
END;
$function$;
