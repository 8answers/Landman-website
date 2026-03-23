-- Persist Data Entry default-row template visibility flags in DB.
-- This prevents default Non-Sellable/Amenity rows from reappearing after
-- browser storage is cleared.

alter table public.projects
  add column if not exists hide_default_non_sellable_template boolean not null default false,
  add column if not exists hide_default_amenity_template boolean not null default false;