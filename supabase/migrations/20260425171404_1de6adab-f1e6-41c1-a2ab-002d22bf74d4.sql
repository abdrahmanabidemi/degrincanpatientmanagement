-- Engagement events: append-only log of key clinic actions
CREATE TYPE public.engagement_action AS ENUM ('whatsapp', 'call', 'completed', 'patient_added');

CREATE TABLE public.engagement_events (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  clinic_id uuid NOT NULL,
  patient_id uuid,
  action_type public.engagement_action NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX idx_engagement_events_clinic_created
  ON public.engagement_events (clinic_id, created_at DESC);
CREATE INDEX idx_engagement_events_created
  ON public.engagement_events (created_at DESC);
CREATE INDEX idx_engagement_events_action
  ON public.engagement_events (action_type);

ALTER TABLE public.engagement_events ENABLE ROW LEVEL SECURITY;

-- Clinics can insert events for their own clinic
CREATE POLICY "Clinic inserts own engagement events"
ON public.engagement_events
FOR INSERT
WITH CHECK (public.user_owns_clinic(clinic_id));

-- Clinics read own events; admins read all
CREATE POLICY "Clinic reads own engagement events"
ON public.engagement_events
FOR SELECT
USING (public.user_owns_clinic(clinic_id) OR public.has_role(auth.uid(), 'admin'::public.app_role));
