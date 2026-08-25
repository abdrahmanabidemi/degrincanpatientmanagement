-- 1. Add new enum value for the free tier
ALTER TYPE public.clinic_plan ADD VALUE IF NOT EXISTS 'basic_free';

-- 2. Change default plan and patient_limit for new clinics
ALTER TABLE public.clinics ALTER COLUMN patient_limit SET DEFAULT 5;

-- 3. Update handle_new_user so new signups start on basic_free with 5 patients
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.clinics (user_id, clinic_name, email, plan, patient_limit, status, expiry_date)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'clinic_name', 'My Clinic'),
    NEW.email,
    'basic_free',
    5,
    'active',
    (CURRENT_DATE + INTERVAL '3650 days')
  );
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'clinic');
  RETURN NEW;
END;
$function$;
