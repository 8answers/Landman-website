-- Migration: Persist Account Report Identity Settings
-- Stores name, organization, role, and uploaded logo for each authenticated user.

CREATE TABLE IF NOT EXISTS account_report_identity_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    organization TEXT,
    role TEXT,
    logo_svg TEXT,
    logo_base64 TEXT,
    logo_file_name TEXT,
    logo_storage_path TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE account_report_identity_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own report identity settings"
    ON account_report_identity_settings;
CREATE POLICY "Users can read own report identity settings"
    ON account_report_identity_settings
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own report identity settings"
    ON account_report_identity_settings;
CREATE POLICY "Users can insert own report identity settings"
    ON account_report_identity_settings
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own report identity settings"
    ON account_report_identity_settings;
CREATE POLICY "Users can update own report identity settings"
    ON account_report_identity_settings
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own report identity settings"
    ON account_report_identity_settings;
CREATE POLICY "Users can delete own report identity settings"
    ON account_report_identity_settings
    FOR DELETE
    USING (auth.uid() = user_id);
