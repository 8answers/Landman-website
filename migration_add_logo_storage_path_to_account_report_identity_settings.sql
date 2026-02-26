-- Migration: Add storage path column for account report logos
-- Run this if account_report_identity_settings already exists.

ALTER TABLE IF EXISTS account_report_identity_settings
ADD COLUMN IF NOT EXISTS logo_storage_path TEXT;
