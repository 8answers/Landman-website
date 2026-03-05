-- Migration: Create "documents" storage bucket + RLS policies
-- Needed for expense/layout document uploads from Project Details and Documents pages.

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'documents',
    'documents',
    true,
    52428800, -- 50 MB
    NULL      -- allow all mime types used by docs/images
)
ON CONFLICT (id) DO UPDATE
SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload project documents" ON storage.objects;
CREATE POLICY "Users can upload project documents"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'documents'
    AND EXISTS (
        SELECT 1
        FROM public.projects p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND p.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Users can read project documents" ON storage.objects;
CREATE POLICY "Users can read project documents"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'documents'
    AND EXISTS (
        SELECT 1
        FROM public.projects p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND p.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Users can update project documents" ON storage.objects;
CREATE POLICY "Users can update project documents"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'documents'
    AND EXISTS (
        SELECT 1
        FROM public.projects p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND p.user_id = auth.uid()
    )
)
WITH CHECK (
    bucket_id = 'documents'
    AND EXISTS (
        SELECT 1
        FROM public.projects p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND p.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Users can delete project documents" ON storage.objects;
CREATE POLICY "Users can delete project documents"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'documents'
    AND EXISTS (
        SELECT 1
        FROM public.projects p
        WHERE p.id::text = (storage.foldername(name))[1]
          AND p.user_id = auth.uid()
    )
);

