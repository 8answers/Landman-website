-- =====================================================
-- Migration: Rename columns in plots table to match new UI column names
-- =====================================================
-- Old column names:
--   Column 4: purchase_rate
--   Column 5: (not stored, was calculated)
-- 
-- New column names:
--   Column 4: all_in_cost_per_sqft (renamed from purchase_rate)
--   Column 5: total_plot_cost (new column to store calculated value)
-- =====================================================

-- Step 1: Rename purchase_rate to all_in_cost_per_sqft
ALTER TABLE plots 
RENAME COLUMN purchase_rate TO all_in_cost_per_sqft;

-- Step 2: Add new column for Total Plot Cost (5th column)
ALTER TABLE plots 
ADD COLUMN total_plot_cost DECIMAL(15, 2) DEFAULT 0.00;

-- Optional: Add a comment to document the change
COMMENT ON COLUMN plots.all_in_cost_per_sqft IS 'All-in Cost per square foot (previously purchase_rate)';
COMMENT ON COLUMN plots.total_plot_cost IS 'Total Plot Cost calculated as area * all_in_cost_per_sqft';
