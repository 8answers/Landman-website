-- Migration: Add amenity_areas table (Amenity Area + details)
-- Run this in Supabase SQL Editor.

begin;

-- 1) Table
create table if not exists public.amenity_areas (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references public.projects(id) on delete cascade,
  name varchar(255) not null,
  area numeric(15, 3) not null default 0,
  all_in_cost numeric(15, 2) not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Backward/forward-safe column adds if table existed already
alter table public.amenity_areas
  add column if not exists area numeric(15, 3) not null default 0,
  add column if not exists all_in_cost numeric(15, 2) not null default 0,
  add column if not exists sort_order integer not null default 0,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- 3) Helpful indexes
create index if not exists idx_amenity_areas_project_id
  on public.amenity_areas(project_id);

create index if not exists idx_amenity_areas_project_sort
  on public.amenity_areas(project_id, sort_order, created_at);

-- 4) RLS
alter table public.amenity_areas enable row level security;

drop policy if exists "Users can manage amenity areas for their projects"
  on public.amenity_areas;

create policy "Users can manage amenity areas for their projects"
on public.amenity_areas
for all
using (
  exists (
    select 1
    from public.projects p
    where p.id = amenity_areas.project_id
      and p.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.projects p
    where p.id = amenity_areas.project_id
      and p.user_id = auth.uid()
  )
);

-- 5) updated_at trigger
create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists update_amenity_areas_updated_at on public.amenity_areas;

create trigger update_amenity_areas_updated_at
before update on public.amenity_areas
for each row
execute function public.update_updated_at_column();

commit;

