-- Add nullable logo_url column (safe for existing users)
ALTER TABLE public.clinics ADD COLUMN IF NOT EXISTS logo_url text;

-- Create a public bucket for clinic logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('clinic-logos', 'clinic-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Public read
CREATE POLICY "Clinic logos are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'clinic-logos');

-- Owner-only write within their own user_id folder
CREATE POLICY "Users can upload their own clinic logo"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'clinic-logos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can update their own clinic logo"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'clinic-logos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can delete their own clinic logo"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'clinic-logos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);