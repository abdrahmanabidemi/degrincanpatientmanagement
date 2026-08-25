-- Roles enum + table
CREATE TYPE public.app_role AS ENUM ('admin', 'clinic');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE POLICY "Users read own roles" ON public.user_roles
  FOR SELECT USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage roles" ON public.user_roles
  FOR ALL USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Plan / status enums
CREATE TYPE public.clinic_plan AS ENUM ('Basic', 'Growth', 'Scale');
CREATE TYPE public.clinic_status AS ENUM ('trial', 'active', 'expired');
CREATE TYPE public.contact_method AS ENUM ('WhatsApp', 'Call');
CREATE TYPE public.followup_type AS ENUM ('checkup', 'medication', 'feedback', 'custom');
CREATE TYPE public.patient_status AS ENUM ('active', 'completed', 'lost');

-- Clinics
CREATE TABLE public.clinics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  clinic_name text NOT NULL,
  email text NOT NULL,
  plan clinic_plan NOT NULL DEFAULT 'Basic',
  status clinic_status NOT NULL DEFAULT 'trial',
  expiry_date date NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '7 days'),
  patient_limit int NOT NULL DEFAULT 25,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clinic reads own" ON public.clinics
  FOR SELECT USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Clinic updates own basic" ON public.clinics
  FOR UPDATE USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'))
  WITH CHECK (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admin inserts clinics" ON public.clinics
  FOR INSERT WITH CHECK (public.has_role(auth.uid(), 'admin') OR auth.uid() = user_id);
CREATE POLICY "Admin deletes clinics" ON public.clinics
  FOR DELETE USING (public.has_role(auth.uid(), 'admin'));

-- Patients
CREATE TABLE public.patients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id uuid NOT NULL REFERENCES public.clinics(id) ON DELETE CASCADE,
  name text NOT NULL,
  phone_number text NOT NULL,
  contact_method contact_method NOT NULL DEFAULT 'WhatsApp',
  diagnosis text NOT NULL,
  treatment_duration text NOT NULL,
  treatment_notes text,
  follow_up_type followup_type NOT NULL DEFAULT 'checkup',
  next_follow_up_date date NOT NULL,
  status patient_status NOT NULL DEFAULT 'active',
  total_cost numeric(10,2) NOT NULL DEFAULT 0,
  amount_paid numeric(10,2) NOT NULL DEFAULT 0,
  balance numeric(10,2) GENERATED ALWAYS AS (total_cost - amount_paid) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_patients_clinic ON public.patients(clinic_id);
CREATE INDEX idx_patients_followup ON public.patients(next_follow_up_date);

CREATE OR REPLACE FUNCTION public.user_owns_clinic(_clinic_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.clinics WHERE id = _clinic_id AND user_id = auth.uid())
$$;

CREATE POLICY "Clinic reads own patients" ON public.patients
  FOR SELECT USING (public.user_owns_clinic(clinic_id) OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Clinic inserts own patients" ON public.patients
  FOR INSERT WITH CHECK (public.user_owns_clinic(clinic_id));
CREATE POLICY "Clinic updates own patients" ON public.patients
  FOR UPDATE USING (public.user_owns_clinic(clinic_id)) WITH CHECK (public.user_owns_clinic(clinic_id));
CREATE POLICY "Clinic deletes own patients" ON public.patients
  FOR DELETE USING (public.user_owns_clinic(clinic_id));

-- Timestamp trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_clinics_updated BEFORE UPDATE ON public.clinics
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER trg_patients_updated BEFORE UPDATE ON public.patients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create clinic + clinic role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.clinics (user_id, clinic_name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'clinic_name', 'My Clinic'),
    NEW.email
  );
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'clinic');
  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();