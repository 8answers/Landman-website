-- Hardening: documents bucket should not be public.
-- Access should be controlled by storage RLS + short-lived signed URLs.

update storage.buckets
set public = false,
    file_size_limit = 52428800
where id = 'documents';
