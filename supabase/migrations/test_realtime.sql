-- ============================================
-- TEST REALTIME SUBSCRIPTION
-- This checks if frontend can receive notifications
-- ============================================

-- 1. Check if Realtime is enabled for notifications table
SELECT 
  '1. REALTIME STATUS' as step,
  CASE 
    WHEN tablename = 'notifications' THEN '✅ Notifications table is in realtime publication'
    ELSE '❌ NOT FOUND'
  END as status
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename = 'notifications';

-- If the above returns no rows, run this fix:
/*
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
*/

-- 2. Insert a test notification for YOUR current user
-- Replace with your actual user email
INSERT INTO notifications (
  user_id,
  type,
  title,
  message,
  metadata
)
SELECT 
  id,
  'info',
  '🔔 REAL-TIME TEST',
  'This notification was created at ' || NOW()::text || '. If you see this in your bell WITHOUT refreshing, Realtime works!',
  jsonb_build_object('test', true, 'created_at', NOW())
FROM auth.users
WHERE email = 'mitar10pal@gmail.com'  -- ⚠️ CHANGE THIS TO YOUR EMAIL
LIMIT 1;

-- 3. Verify it was created
SELECT 
  '2. NOTIFICATION CREATED' as step,
  created_at,
  title,
  message,
  (SELECT email FROM profiles WHERE id = user_id) as for_user
FROM notifications
WHERE title = '🔔 REAL-TIME TEST'
ORDER BY created_at DESC
LIMIT 1;

-- 4. Check RLS policies on notifications table
SELECT 
  '3. RLS POLICIES' as step,
  policyname as policy_name,
  cmd as command
FROM pg_policies
WHERE tablename = 'notifications';

-- Expected: Should see policies like "Users can view own notifications"
