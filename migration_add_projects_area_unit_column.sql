-- Add project base area unit persistence for Settings page dropdown
alter table if exists public.projects
add column if not exists area_unit text not null default 'Square Feet (sqft)';