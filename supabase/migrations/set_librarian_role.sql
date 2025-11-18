-- Check if your librarian account has the role set

SELECT 
  id,
  email,
  raw_user_meta_data->>'role' as role_in_metadata,
  raw_user_meta_data
FROM auth.users
WHERE email = 'phoenix.xd2925@gmail.com';

-- If role is NULL, let's set it
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"role": "librarian"}'::jsonb
WHERE email = 'phoenix.xd2925@gmail.com'
  AND (raw_user_meta_data->>'role' IS NULL OR raw_user_meta_data->>'role' != 'librarian');

-- Verify it was set
SELECT 
  email,
  raw_user_meta_data->>'role' as role_after_update
FROM auth.users
WHERE email = 'phoenix.xd2925@gmail.com';

-- Test the function with this user
SELECT '=== TESTING get_user_role() FUNCTION ===' as step;
SELECT get_user_role() as current_user_role;
