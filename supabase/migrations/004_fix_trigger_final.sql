-- ============================================================
-- FIX: The profile trigger is blocking user creation.
-- Drop it first, then recreate with error handling so it
-- never blocks auth. Run this in the SQL Editor.
-- ============================================================

-- 1. Drop the broken trigger and function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

-- 2. Recreate with EXCEPTION handler so it never blocks user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (new.id, COALESCE(new.raw_user_meta_data->>'display_name', ''));
  RETURN new;
EXCEPTION WHEN OTHERS THEN
  -- Log warning but do NOT block user creation
  RAISE WARNING 'handle_new_user: could not create profile for %: %', new.id, SQLERRM;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Recreate trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 4. Make sure auth admin can insert profiles (belt + suspenders)
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT INSERT ON profiles TO supabase_auth_admin;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO supabase_auth_admin;

-- 5. Drop any RLS that might block auth_admin
DO $$
BEGIN
  -- Remove old policies and add a clean one
  DROP POLICY IF EXISTS "profiles_own" ON profiles;
  DROP POLICY IF EXISTS "auth_admin_insert_profiles" ON profiles;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 6. Recreate RLS: users see own data, auth_admin can insert
CREATE POLICY "profiles_own" ON profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "auth_admin_insert_profiles" ON profiles
  FOR INSERT
  TO supabase_auth_admin
  WITH CHECK (true);

-- 7. Also allow service_role to manage profiles (for the Python backend)
CREATE POLICY "service_role_all_profiles" ON profiles
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
