-- 1) Harden the billing-guard trigger so the self-upgrade branch
--    cannot be abused to set arbitrary status / expiry_date.
CREATE OR REPLACE FUNCTION public.prevent_clinic_billing_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Admins can change anything
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  -- Allow self-upgrade ONLY when ALL of the following match what
  -- upgrade_clinic_plan() sets:
  --   * same owner
  --   * acting as the owner
  --   * (plan, patient_limit) is one of the two paid tiers
  --   * status is exactly 'active'
  --   * expiry_date is exactly CURRENT_DATE + 30 days (no tolerance)
  IF NEW.user_id = OLD.user_id
     AND NEW.user_id = auth.uid()
     AND (
       (NEW.plan = 'Basic'::public.clinic_plan  AND NEW.patient_limit = 150)
       OR
       (NEW.plan = 'Growth'::public.clinic_plan AND NEW.patient_limit = 500)
     )
     AND NEW.status = 'active'::public.clinic_status
     AND NEW.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
  THEN
    RETURN NEW;
  END IF;

  -- For non-admins, billing-related fields must not change otherwise
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

-- 2) Revoke direct client access to upgrade_clinic_plan so it can no
--    longer be called as an authenticated user RPC. Only the service
--    role (used by edge functions) may execute it.
REVOKE ALL ON FUNCTION public.upgrade_clinic_plan(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upgrade_clinic_plan(text) FROM anon;
REVOKE ALL ON FUNCTION public.upgrade_clinic_plan(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.upgrade_clinic_plan(text) TO service_role;

-- 3) Add a service-role-only variant that takes the target user id
--    explicitly. Edge functions (running with the service role) will
--    call this after verifying the caller's identity (and, in the
--    future, payment success).
CREATE OR REPLACE FUNCTION public.admin_upgrade_clinic_plan(_user_id uuid, _plan text)
RETURNS public.clinics
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

REVOKE ALL ON FUNCTION public.admin_upgrade_clinic_plan(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_upgrade_clinic_plan(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_upgrade_clinic_plan(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upgrade_clinic_plan(uuid, text) TO service_role;