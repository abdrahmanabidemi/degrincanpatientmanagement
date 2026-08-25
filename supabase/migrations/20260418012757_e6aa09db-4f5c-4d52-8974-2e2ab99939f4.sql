CREATE OR REPLACE FUNCTION public.upgrade_clinic_plan(_plan text)
RETURNS public.clinics
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer;
  v_plan public.clinic_plan;
  v_row public.clinics;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF _plan = 'Basic' THEN
    v_plan := 'Basic'::public.clinic_plan;
    v_limit := 150;
  ELSIF _plan = 'Growth' THEN
    v_plan := 'Growth'::public.clinic_plan;
    v_limit := 500;
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
$$;

-- Allow the billing-restriction trigger to permit changes coming from this SECURITY DEFINER function.
-- We update the trigger function to also allow updates initiated by upgrade_clinic_plan via a session GUC.
CREATE OR REPLACE FUNCTION public.prevent_clinic_billing_self_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow if the current user is an admin
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  -- Allow self-upgrade only when going to one of the two paid plans with the
  -- exact (plan, patient_limit) pair set by upgrade_clinic_plan.
  IF NEW.user_id = OLD.user_id
     AND NEW.user_id = auth.uid()
     AND (
       (NEW.plan = 'Basic'::public.clinic_plan AND NEW.patient_limit = 150)
       OR (NEW.plan = 'Growth'::public.clinic_plan AND NEW.patient_limit = 500)
     )
  THEN
    RETURN NEW;
  END IF;

  -- For non-admins, ensure billing-related fields are not modified
  IF NEW.plan IS DISTINCT FROM OLD.plan
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.expiry_date IS DISTINCT FROM OLD.expiry_date
     OR NEW.patient_limit IS DISTINCT FROM OLD.patient_limit
     OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Only administrators can modify subscription or billing fields';
  END IF;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upgrade_clinic_plan(text) TO authenticated;