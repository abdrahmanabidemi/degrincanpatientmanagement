-- 1) Force default patient_limit to 5 at column level
ALTER TABLE public.clinics ALTER COLUMN patient_limit SET DEFAULT 5;

-- 2) Trigger: normalize patient_limit based on plan, every insert/update.
-- Non-paid plans (basic_free) and any unknown plan => 5
-- Basic => 150, Growth => 500, Scale => existing or 500 fallback
CREATE OR REPLACE FUNCTION public.enforce_patient_limit_from_plan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Null/missing => default 5
  IF NEW.patient_limit IS NULL THEN
    NEW.patient_limit := 5;
  END IF;

  -- Always derive limit from plan (ignores any client-supplied value)
  IF NEW.plan = 'Basic'::public.clinic_plan THEN
    NEW.patient_limit := 150;
  ELSIF NEW.plan = 'Growth'::public.clinic_plan THEN
    NEW.patient_limit := 500;
  ELSIF NEW.plan = 'Scale'::public.clinic_plan THEN
    -- keep generous limit for Scale; default to 500 if not otherwise set
    IF NEW.patient_limit < 500 THEN
      NEW.patient_limit := 500;
    END IF;
  ELSE
    -- basic_free or anything else
    NEW.patient_limit := 5;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_patient_limit_from_plan ON public.clinics;
CREATE TRIGGER trg_enforce_patient_limit_from_plan
BEFORE INSERT OR UPDATE ON public.clinics
FOR EACH ROW
EXECUTE FUNCTION public.enforce_patient_limit_from_plan();

-- 3) Backfill: reset all non-paid clinics to 5
UPDATE public.clinics
   SET patient_limit = 5
 WHERE plan NOT IN ('Basic'::public.clinic_plan, 'Growth'::public.clinic_plan, 'Scale'::public.clinic_plan);

-- 4) Fail-safe: enforce patient count <= patient_limit at insert time
CREATE OR REPLACE FUNCTION public.enforce_patient_limit_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
  v_limit integer;
BEGIN
  SELECT patient_limit INTO v_limit FROM public.clinics WHERE id = NEW.clinic_id;
  IF v_limit IS NULL THEN
    v_limit := 5;
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.patients WHERE clinic_id = NEW.clinic_id;

  IF v_count >= v_limit THEN
    RAISE EXCEPTION 'PATIENT_LIMIT_REACHED: You have reached your patient limit (%). Upgrade your plan to add more patients.', v_limit
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_patient_limit_on_insert ON public.patients;
CREATE TRIGGER trg_enforce_patient_limit_on_insert
BEFORE INSERT ON public.patients
FOR EACH ROW
EXECUTE FUNCTION public.enforce_patient_limit_on_insert();