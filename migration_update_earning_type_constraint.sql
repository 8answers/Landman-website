-- =====================================================
-- Migration: Update earning_type constraint to support 
--            "Profit Per Plot" and "Selling Price Per Plot"
-- =====================================================
-- This migration updates the CHECK constraint on earning_type
-- columns in both project_managers and agents tables to allow
-- more specific values for percentage-based compensation.
-- =====================================================

-- Step 1: Drop existing constraint on project_managers table
ALTER TABLE project_managers 
DROP CONSTRAINT IF EXISTS project_managers_earning_type_check;

-- Step 2: Add new constraint on project_managers table with expanded values
ALTER TABLE project_managers 
ADD CONSTRAINT project_managers_earning_type_check 
CHECK (earning_type IS NULL OR earning_type IN (
  'Per Plot',
  'Per Square Foot', 
  'Lump Sum',
  'Profit Per Plot',
  'Selling Price Per Plot'
));

-- Step 3: Drop existing constraint on agents table
ALTER TABLE agents 
DROP CONSTRAINT IF EXISTS agents_earning_type_check;

-- Step 4: Add new constraint on agents table with expanded values
ALTER TABLE agents 
ADD CONSTRAINT agents_earning_type_check 
CHECK (earning_type IS NULL OR earning_type IN (
  'Per Plot',
  'Per Square Foot', 
  'Lump Sum',
  'Profit Per Plot',
  'Selling Price Per Plot'
));

-- Optional: Add comments to document the change
COMMENT ON COLUMN project_managers.earning_type IS 'Earning type for percentage bonus: Per Plot (legacy), Profit Per Plot (percentage of profit), Selling Price Per Plot (percentage of sale price), Per Square Foot, or Lump Sum';
COMMENT ON COLUMN agents.earning_type IS 'Earning type for percentage bonus: Per Plot (legacy), Profit Per Plot (percentage of profit), Selling Price Per Plot (percentage of sale price), Per Square Foot, or Lump Sum';
