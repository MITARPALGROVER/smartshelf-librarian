-- Create test user
-- Email: test@test.com
-- Password: test

-- This will create a user in Supabase Auth
-- Run this in Supabase SQL Editor

-- Note: Direct user creation in auth.users requires admin privileges
-- The safer way is to use the Supabase Dashboard: Authentication > Users > Invite User

-- Alternative: Use this query to insert directly (requires admin access)
-- Replace 'YOUR_PROJECT_ID' with actual project ID if needed

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  invited_at,
  confirmation_token,
  confirmation_sent_at,
  recovery_token,
  recovery_sent_at,
  email_change_token_new,
  email_change,
  email_change_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  created_at,
  updated_at,
  phone,
  phone_confirmed_at,
  phone_change,
  phone_change_token,
  phone_change_sent_at,
  email_change_token_current,
  email_change_confirm_status,
  banned_until,
  reauthentication_token,
  reauthentication_sent_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'test@test.com',
  crypt('test', gen_salt('bf')), -- Password: test
  NOW(),
  NULL,
  '',
  NULL,
  '',
  NULL,
  '',
  '',
  NULL,
  NULL,
  '{"provider":"email","providers":["email"]}',
  '{}',
  FALSE,
  NOW(),
  NOW(),
  NULL,
  NULL,
  '',
  '',
  NULL,
  '',
  0,
  NULL,
  '',
  NULL
);

-- After creating the user, you may need to add them to profiles table
-- This will be done automatically by your app's trigger, but if not:

-- INSERT INTO profiles (id, email, full_name)
-- SELECT id, email, 'Test User'
-- FROM auth.users
-- WHERE email = 'test@test.com';

-- Assign role (student by default)
-- INSERT INTO user_roles (user_id, role)
-- SELECT id, 'student'
-- FROM auth.users
-- WHERE email = 'test@test.com'
-- ON CONFLICT (user_id) DO NOTHING;
