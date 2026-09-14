-- ============================================================
-- Diagnose + fix the "Database error creating new user" issue
-- Run each section in order in the Supabase SQL Editor
-- ============================================================

-- 1. Check that the profiles table exists with the right columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles';

-- 2. Check that the trigger function exists and is valid
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'handle_new_user';

-- 3. Test the trigger function directly (simulate a user insert)
-- This will show the actual error if something is wrong
DO $$
DECLARE
  test_id UUID := gen_random_uuid();
BEGIN
  -- Temporarily bypass RLS for this test
  PERFORM set_config('role', 'supabase_admin', true);
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  VALUES (test_id, 'test-trigger-debug@example.com', crypt('testpass', gen_salt('bf')), now(), now(), now(), '{"display_name":"Test"}'::jsonb);
  RAISE NOTICE 'SUCCESS: trigger worked, user % created', test_id;
  -- Clean up
  DELETE FROM auth.users WHERE id = test_id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'TRIGGER FAILED: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;

-- 4. If step 3 showed a trigger error, recreate it cleanly
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (new.id, COALESCE(new.raw_user_meta_data->>'display_name', ''));
  RETURN new;
EXCEPTION WHEN OTHERS THEN
  -- Log the error but don't block user creation
  RAISE WARNING 'Failed to create profile for user %: %', new.id, SQLERRM;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 5. Grant necessary permissions
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT INSERT ON profiles TO supabase_auth_admin;

-- 6. Allow supabase_auth_admin to insert into profiles (bypasses RLS)
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
CREATE POLICY "auth_admin_insert_profiles" ON profiles
  FOR INSERT TO supabase_auth_admin
  WITH CHECK (true);
