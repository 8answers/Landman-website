-- Hardening: close role-escalation paths in project access control.
-- 1) Prevent self-role/status edits on project_members.
-- 2) Restrict invitee membership inserts to role/status derived from invite row.
-- 3) Enforce immutable invite role/project/email for non-admin invite accept flow.

begin;

-- Remove dangerous self-update policy that allowed privilege escalation.
drop policy if exists "Users can update own project_members row" on public.project_members;
drop policy if exists "Invitees can update own membership" on public.project_members;

-- Recreate insert policy with strict role matching against invite row.
drop policy if exists "Owners and accepted invitees can insert project_members" on public.project_members;
create policy "Owners and accepted invitees can insert project_members"
  on public.project_members
  for insert
  with check (
    exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and p.user_id = auth.uid()
    )
    or (
      project_members.user_id = auth.uid()
      and lower(coalesce(project_members.invited_email, '')) =
          lower(coalesce(auth.jwt() ->> 'email', ''))
      and coalesce(project_members.status, 'active') = 'active'
      and exists (
        select 1
        from public.project_access_invites i
        where i.project_id = project_members.project_id
          and lower(i.invited_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
          and i.role = project_members.role
          and i.status in ('requested', 'accepted')
          and (i.accepted_user_id is null or i.accepted_user_id = auth.uid())
      )
    )
  );

create or replace function public.enforce_project_access_invite_update_restrictions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_user_id uuid := auth.uid();
  actor_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  is_project_owner boolean := false;
  is_project_admin_or_pm boolean := false;
begin
  if actor_user_id is not null then
    select exists (
      select 1
      from public.projects p
      where p.id = old.project_id
        and p.user_id = actor_user_id
    ) into is_project_owner;

    select exists (
      select 1
      from public.project_members pm
      where pm.project_id = old.project_id
        and pm.user_id = actor_user_id
        and pm.status = 'active'
        and pm.role in ('admin', 'project_manager')
    ) into is_project_admin_or_pm;
  end if;

  -- Owners/admins/project managers can manage invite rows freely.
  if is_project_owner or is_project_admin_or_pm then
    return new;
  end if;

  -- Invitee update path: only allow acceptance, with immutable role/email/project.
  if actor_user_id is null or actor_email = '' then
    raise exception 'Only authenticated invitees can accept invites.';
  end if;

  if lower(coalesce(old.invited_email, '')) <> actor_email then
    raise exception 'Invite can only be accepted by the invited email.';
  end if;

  if new.project_id is distinct from old.project_id
     or lower(coalesce(new.invited_email, '')) <> lower(coalesce(old.invited_email, ''))
     or new.role is distinct from old.role
     or new.requested_by is distinct from old.requested_by
     or new.requested_at is distinct from old.requested_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Invite acceptance cannot modify invite identity fields.';
  end if;

  if new.status <> 'accepted' then
    raise exception 'Invitee updates may only set status to accepted.';
  end if;

  if old.status not in ('requested', 'accepted') then
    raise exception 'Invite is not in an acceptable state for invitee update.';
  end if;

  if new.accepted_user_id is null then
    new.accepted_user_id := actor_user_id;
  end if;

  if new.accepted_user_id <> actor_user_id then
    raise exception 'Invite acceptance must bind to current authenticated user.';
  end if;

  if new.accepted_at is null then
    new.accepted_at := now();
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_project_access_invite_update_restrictions() from public;
grant execute on function public.enforce_project_access_invite_update_restrictions() to authenticated;

drop trigger if exists trg_enforce_project_access_invite_update on public.project_access_invites;
create trigger trg_enforce_project_access_invite_update
before update on public.project_access_invites
for each row
execute function public.enforce_project_access_invite_update_restrictions();

commit;
