-- Layout image metadata support + folder cleanup
-- Run this in Supabase SQL editor.

begin;

-- 1) Add layout image metadata columns on layouts.
alter table if exists public.layouts
  add column if not exists layout_image_name text,
  add column if not exists layout_image_path text,
  add column if not exists layout_image_doc_id uuid,
  add column if not exists layout_image_extension text;

create index if not exists idx_layouts_layout_image_doc_id
  on public.layouts(layout_image_doc_id);

-- 2) Ensure every project has a root "Layouts" folder.
insert into public.documents (project_id, name, type, parent_id)
select p.id, 'Layouts', 'folder', null
from public.projects p
where not exists (
  select 1
  from public.documents d
  where d.project_id = p.id
    and d.type = 'folder'
    and d.parent_id is null
    and lower(trim(d.name)) = 'layouts'
);

-- 3) Normalize root folder names so UI shows consistent labels.
update public.documents
set name = case
  when lower(trim(name)) = 'layouts' then 'Layouts'
  when lower(trim(name)) = 'expenses' then 'Expenses'
  else name
end
where type = 'folder'
  and parent_id is null
  and lower(trim(name)) in ('layouts', 'expenses');

-- 4) Deduplicate root folders (e.g., Expenses/expenses) by moving children
--    to a single keeper folder per project+name and deleting extras.
with ranked as (
  select
    id,
    project_id,
    lower(trim(name)) as normalized_name,
    row_number() over (
      partition by project_id, lower(trim(name))
      order by id
    ) as rn,
    first_value(id) over (
      partition by project_id, lower(trim(name))
      order by id
    ) as keeper_id
  from public.documents
  where type = 'folder'
    and parent_id is null
    and lower(trim(name)) in ('layouts', 'expenses')
),
to_move as (
  select id as duplicate_id, keeper_id
  from ranked
  where rn > 1
)
update public.documents d
set parent_id = tm.keeper_id
from to_move tm
where d.parent_id = tm.duplicate_id;

with ranked as (
  select
    id,
    row_number() over (
      partition by project_id, lower(trim(name))
      order by id
    ) as rn
  from public.documents
  where type = 'folder'
    and parent_id is null
    and lower(trim(name)) in ('layouts', 'expenses')
)
delete from public.documents d
using ranked r
where d.id = r.id
  and r.rn > 1;

-- 5) Backfill layouts.layout_image_* from existing uploaded docs whose
--    storage path follows: .../layout_<layoutId>/...
with parsed as (
  select
    d.id as doc_id,
    d.name,
    d.extension,
    d.file_url,
    d.created_at,
    substring(d.file_url from '/layout_([^/]+)/') as layout_id_text
  from public.documents d
  where d.type = 'file'
    and d.file_url is not null
    and d.file_url like '%/layout_%/%'
),
latest as (
  select distinct on (layout_id_text)
    layout_id_text,
    doc_id,
    name,
    extension,
    file_url
  from parsed
  where layout_id_text is not null
    and layout_id_text <> ''
  order by layout_id_text, created_at desc nulls last, doc_id desc
)
update public.layouts l
set
  layout_image_doc_id = latest.doc_id,
  layout_image_name = latest.name,
  layout_image_extension = latest.extension,
  layout_image_path = latest.file_url
from latest
where l.id::text = latest.layout_id_text;

commit;
