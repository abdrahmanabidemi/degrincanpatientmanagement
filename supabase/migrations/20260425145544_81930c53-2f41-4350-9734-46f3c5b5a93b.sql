-- Add extra_patient_slots column for admin-controlled silent extensions
ALTER TABLE public.clinics
  ADD COLUMN IF NOT EXISTS extra_patient_slots integer NOT NULL DEFAULT 0;

-- Update plan-limit trigger so the effective patient_limit = base_plan_limit + extra_patient_slots.
-- Admins set extra_patient_slots; the trigger keeps patient_limit in sync on any clinic update.
CREATE OR REPLACE FUNCTION public.enforce_patient_limit_from_plan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_base integer;
  v_extra integer;
BEGIN
  v_extra := COALESCE(NEW.extra_patient_slots, 0);
  IF v_extra < 0 THEN v_extra := 0; END IF;
  NEW.extra_patient_slots := v_extra;

  IF NEW.plan = 'Pro'::public.clinic_plan THEN
    v_base := 100;
  ELSIF NEW.plan = 'Scale'::public.clinic_plan THEN
    v_base := 400;
  ELSIF NEW.plan = 'Basic'::public.clinic_plan THEN
    v_base := 100;
  ELSIF NEW.plan = 'Growth'::public.clinic_plan THEN
    v_base := 400;
  ELSE
    v_base := 5;
  END IF;

  NEW.patient_limit := v_base + v_extra;
  RETURN NEW;
END;
$function$;

-- Update billing self-update guard so non-admins cannot modify extra_patient_slots.
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
       (NEW.plan = 'Pro'::public.clinic_plan   AND NEW.patient_limit = 100 + COALESCE(OLD.extra_patient_slots, 0))
       OR
       (NEW.plan = 'Scale'::public.clinic_plan AND NEW.patient_limit = 400 + COALESCE(OLD.extra_patient_slots, 0))
     )
     AND NEW.status = 'active'::public.clinic_status
     AND (
       NEW.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
       OR NEW.expiry_date = (CURRENT_DATE + INTERVAL '365 days')::date
     )
     AND NEW.extra_patient_slots IS NOT DISTINCT FROM OLD.extra_patient_slots
  THEN
    RETURN NEW;
  END IF;

  IF NEW.plan IS DISTINCT FROM OLD.plan
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.expiry_date IS DISTINCT FROM OLD.expiry_date
     OR NEW.patient_limit IS DISTINCT FROM OLD.patient_limit
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.extra_patient_slots IS DISTINCT FROM OLD.extra_patient_slots THEN
    RAISE EXCEPTION 'Only administrators can modify subscription or billing fields';
  END IF;

  RETURN NEW;
END;
$function$;

-- Backfill: ensure existing clinics have patient_limit = base + extras (extras start at 0, so no change in numbers).
UPDATE public.clinics SET extra_patient_slots = 0 WHERE extra_patient_slots IS NULL;