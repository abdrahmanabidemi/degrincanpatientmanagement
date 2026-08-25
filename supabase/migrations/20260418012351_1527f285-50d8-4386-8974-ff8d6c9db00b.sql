-- Trigger to prevent non-admin users from changing billing-sensitive fields on clinics
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

DROP TRIGGER IF EXISTS prevent_clinic_billing_self_update_trg ON public.clinics;
CREATE TRIGGER prevent_clinic_billing_self_update_trg
BEFORE UPDATE ON public.clinics
FOR EACH ROW
EXECUTE FUNCTION public.prevent_clinic_billing_self_update();