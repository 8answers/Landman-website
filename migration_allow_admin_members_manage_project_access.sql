-- Allow active ADMIN members (not only project owner) to manage project access.
-- This fixes invite rows not persisting for admin users after refresh.

CREATE OR REPLACE FUNCTION public.is_active_project_admin(target_project_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.project_members pm
    WHERE pm.project_id = target_project_id
      AND pm.user_id = auth.uid()
      AND pm.status = 'active'
      AND pm.role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_project_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_project_admin(uuid) TO authenticated;

DROP POLICY IF EXISTS "Active admins can insert invites for their projects"
ON public.project_access_invites;
CREATE POLICY "Active admins can insert invites for their projects"
  ON public.project_access_invites
  FOR INSERT
  WITH CHECK (public.is_active_project_admin(project_id));

DROP POLICY IF EXISTS "Active admins can update invites for their projects"
ON public.project_access_invites;
CREATE POLICY "Active admins can update invites for their projects"
  ON public.project_access_invites
  FOR UPDATE
  USING (public.is_active_project_admin(project_id))
  WITH CHECK (public.is_active_project_admin(project_id));

DROP POLICY IF EXISTS "Active admins can delete invites for their projects"
ON public.project_access_invites;
CREATE POLICY "Active admins can delete invites for their projects"
  ON public.project_access_invites
  FOR DELETE
  USING (public.is_active_project_admin(project_id));

DROP POLICY IF EXISTS "Active admins can insert project_members for their projects"
ON public.project_members;
CREATE POLICY "Active admins can insert project_members for their projects"
  ON public.project_members
  FOR INSERT
  WITH CHECK (public.is_active_project_admin(project_id));

DROP POLICY IF EXISTS "Active admins can update project_members for their projects"
ON public.project_members;
CREATE POLICY "Active admins can update project_members for their projects"
  ON public.project_members
  FOR UPDATE
  USING (public.is_active_project_admin(project_id))
  WITH CHECK (public.is_active_project_admin(project_id));

DROP POLICY IF EXISTS "Active admins can delete project_members for their projects"
ON public.project_members;
CREATE POLICY "Active admins can delete project_members for their projects"
  ON public.project_members
  FOR DELETE
  USING (public.is_active_project_admin(project_id));
