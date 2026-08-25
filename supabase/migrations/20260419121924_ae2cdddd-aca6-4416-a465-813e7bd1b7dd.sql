
-- 1) Add new enum value "Pro" (keep old values for compatibility)
ALTER TYPE public.clinic_plan ADD VALUE IF NOT EXISTS 'Pro';
