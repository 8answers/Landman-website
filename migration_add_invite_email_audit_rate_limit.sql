-- Hardening: invite email send audit + rate-limiting support for edge function.

create table if not exists public.invite_email_audit (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  invited_email text not null,
  role varchar(32) not null check (role in ('partner', 'project_manager', 'agent', 'admin')),
  sent_at timestamptz not null default now()
);

create index if not exists idx_invite_email_audit_user_sent_at
  on public.invite_email_audit(user_id, sent_at desc);

create index if not exists idx_invite_email_audit_project_sent_at
  on public.invite_email_audit(project_id, sent_at desc);

alter table public.invite_email_audit enable row level security;

-- Intentionally no authenticated client policies.
-- Table is written/read by edge function using service role.
