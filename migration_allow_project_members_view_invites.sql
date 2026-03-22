-- Allow active project members to read project invite rows.
-- This enables non-owner members (e.g. partners) to view all invited partners
-- in the Settings > Partners section.

DROP POLICY IF EXISTS "Members can view invites for their project"
ON public.project_access_invites;

CREATE POLICY "Members can view invites for their project"
  ON public.project_access_invites
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.project_members pm
      WHERE pm.project_id = project_access_invites.project_id
        AND pm.user_id = auth.uid()
        AND pm.status = 'active'
    )
  );

  Also the empty plot status page second line and the button need not be visible for the agent view and the partner view