-- =====================================================
-- Migration: Add payments column to plots table
-- =====================================================
-- This migration adds the payments JSONB column to store
-- payment method details including payment method, amount,
-- bank name, dates, transaction IDs, etc.
-- =====================================================

-- Add payments column if it doesn't exist
ALTER TABLE plots
ADD COLUMN IF NOT EXISTS payments JSONB DEFAULT '[]'::jsonb;

-- Add a comment to document the column
COMMENT ON COLUMN plots.payments IS 'JSON array storing payment details including paymentMethod, amount, date, bankName, transactionId, etc.';
