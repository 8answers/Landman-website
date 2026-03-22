-- Allow non-admin members to remove their own access and
-- allow active admin members to delete projects for everyone.

DROP POLICY IF EXISTS "Users can remove own project membership"
ON public.project_members;
CREATE POLICY "Users can remove own project membership"
  ON public.project_members
  FOR DELETE
  USING (project_members.user_id = auth.uid());

DROP POLICY IF EXISTS "Invitees can delete own invites"
ON public.project_access_invites;
CREATE POLICY "Invitees can delete own invites"
  ON public.project_access_invites
  FOR DELETE
  USING (
    lower(project_access_invites.invited_email) =
    lower(coalesce(auth.jwt() ->> 'email', ''))
    OR project_access_invites.accepted_user_id = auth.uid()
  );

DROP POLICY IF EXISTS "Active admins can delete projects they manage"
ON public.projects;
CREATE POLICY "Active admins can delete projects they manage"
  ON public.projects
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.project_members pm
      WHERE pm.project_id = projects.id
        AND pm.user_id = auth.uid()
        AND pm.status = 'active'
        AND pm.role = 'admin'
    )
  );