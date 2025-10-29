-- Debug: Check all recent notifications and their user_ids
-- This will help us understand if notifications are being created with the correct user_id

-- Step 1: Show all users and their emails
SELECT '=== ALL USERS ===' as step;
SELECT id, email, raw_user_meta_data->>'role' as role
FROM auth.users
ORDER BY created_at DESC;

-- Step 2: Show all profiles and their roles
SELECT '=== ALL PROFILES ===' as step;
SELECT id, role, email
FROM profiles
ORDER BY created_at DESC;

-- Step 3: Show all recent notifications (last 10)
SELECT '=== RECENT NOTIFICATIONS ===' as step;
SELECT 
  n.id,
  n.user_id,
  u.email as user_email,
  p.role as user_role,
  n.type,
  n.title,
  n.message,
  n.is_read,
  n.metadata,
  n.created_at
FROM notifications n
LEFT JOIN auth.users u ON n.user_id = u.id
LEFT JOIN profiles p ON n.user_id = p.id
ORDER BY n.created_at DESC
LIMIT 10;

-- Step 4: Check if there are any notifications for non-existent users
SELECT '=== ORPHANED NOTIFICATIONS (user_id not in auth.users) ===' as step;
SELECT n.*
FROM notifications n
LEFT JOIN auth.users u ON n.user_id = u.id
WHERE u.id IS NULL;

-- Step 5: Count notifications by user
SELECT '=== NOTIFICATION COUNT BY USER ===' as step;
SELECT 
  u.email,
  p.role,
  COUNT(n.id) as notification_count,
  COUNT(CASE WHEN n.is_read = false THEN 1 END) as unread_count
FROM auth.users u
LEFT JOIN profiles p ON u.id = p.id
LEFT JOIN notifications n ON u.id = n.user_id
GROUP BY u.email, p.role
ORDER BY notification_count DESC;

-- Step 6: Show RLS policies on notifications
SELECT '=== RLS POLICIES ON NOTIFICATIONS ===' as step;
SELECT 
  schemaname,
  tablename,
  policyname as policy_name,
  permissive,
  roles,
  cmd as command,
  qual as using_expression,
  with_check as with_check_expression
FROM pg_policies
WHERE tablename = 'notifications';

-- Step 7: Test if you're logged in with correct user
-- Replace 'your@email.com' with your actual email
SELECT '=== CURRENT USER TEST ===' as step;
SELECT 
  u.id,
  u.email,
  p.role,
  (SELECT COUNT(*) FROM notifications WHERE user_id = u.id) as total_notifications,
  (SELECT COUNT(*) FROM notifications WHERE user_id = u.id AND is_read = false) as unread_notifications
FROM auth.users u
LEFT JOIN profiles p ON u.id = p.id
WHERE u.email = 'your@email.com'  -- ⚠️ REPLACE THIS WITH YOUR EMAIL
LIMIT 1;
