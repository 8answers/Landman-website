-- Migration: Add amenity status/sales detail columns to amenity_areas
-- Run this in Supabase SQL Editor.

begin;

alter table public.amenity_areas
  add column if not exists status varchar(20) not null default 'available',
  add column if not exists sale_price numeric(15, 2),
  add column if not exists sale_value numeric(15, 2),
  add column if not exists buyer_name varchar(255),
  add column if not exists payment text,
  add column if not exists agent_name varchar(255),
  add column if not exists sale_date date;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'amenity_areas_status_check'
      and conrelid = 'public.amenity_areas'::regclass
  ) then
    alter table public.amenity_areas
      add constraint amenity_areas_status_check
      check (status in ('available', 'sold', 'reserved'));
  end if;
end $$;

create index if not exists idx_amenity_areas_status
  on public.amenity_areas(status);

commit;
