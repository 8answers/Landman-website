-- Safe/idempotent migration for expense date + document metadata
begin;

alter table public.expenses
  add column if not exists expense_date date,
  add column if not exists doc text,
  add column if not exists doc_path text,
  add column if not exists doc_extension text,
  add column if not exists doc_id uuid;

create index if not exists idx_expenses_project_id on public.expenses(project_id);
create index if not exists idx_expenses_doc_id on public.expenses(doc_id);
create index if not exists idx_expenses_expense_date on public.expenses(expense_date);

-- Add FK only if documents table and compatible id column exist, and FK is not already present.
do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'documents'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'documents'
      and column_name = 'id'
      and data_type = 'uuid'
  )
  and not exists (
    select 1
    from pg_constraint
    where conname = 'expenses_doc_id_fkey'
      and conrelid = 'public.expenses'::regclass
  ) then
    alter table public.expenses
      add constraint expenses_doc_id_fkey
      foreign key (doc_id)
      references public.documents(id)
      on delete set null;
  end if;
end $$;

commit;
