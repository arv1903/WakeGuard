-- ============================================================
-- Fix: Allow supabase_auth_admin to insert into profiles
-- during user registration. Run this in the SQL Editor.
-- ============================================================

-- 1. Grant INSERT permission on profiles to the auth admin role
GRANT INSERT ON profiles TO supabase_auth_admin;

-- 2. Create a policy that allows the auth admin role to insert profiles
--    (this bypasses the RLS "profiles_own" policy that blocks the auth server)
DROP POLICY IF EXISTS "auth_admin_insert_profiles" ON profiles;
CREATE POLICY "auth_admin_insert_profiles" ON profiles
  FOR INSERT
  TO supabase_auth_admin
  WITH CHECK (true);

-- 3. Verify: check that the policy exists
SELECT policyname, roles, cmd
FROM pg_policies
WHERE tablename = 'profiles';
