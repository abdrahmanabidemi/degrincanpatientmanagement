-- Replace broad SELECT policy on clinic-logos with owner-scoped listing.
-- Public file URLs still work because the bucket is public (direct CDN reads bypass RLS).
DROP POLICY IF EXISTS "Clinic logos are publicly viewable" ON storage.objects;

CREATE POLICY "Users can list their own clinic logos"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'clinic-logos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);