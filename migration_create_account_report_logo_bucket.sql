-- Migration: Create bucket + policies for account report identity logos
-- Bucket name must match the Flutter constant `_reportIdentityLogoBucket`.

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'account-report-logos',
    'account-report-logos',
    false,
    5242880,
    ARRAY['image/png', 'image/jpeg', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE
SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload own report logos" ON storage.objects;
CREATE POLICY "Users can upload own report logos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'account-report-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can read own report logos" ON storage.objects;
CREATE POLICY "Users can read own report logos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'account-report-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can update own report logos" ON storage.objects;
CREATE POLICY "Users can update own report logos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'account-report-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
    bucket_id = 'account-report-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can delete own report logos" ON storage.objects;
CREATE POLICY "Users can delete own report logos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'account-report-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);
