-- Insert a test notification RIGHT NOW for your user
-- Replace 'your@email.com' with YOUR actual email

INSERT INTO notifications (user_id, type, title, message, metadata, is_read)
SELECT 
  id,
  'info',
  '🎉 TEST #' || FLOOR(RANDOM() * 1000)::text,
  'Created at ' || NOW()::text || '. Check: (1) Bell badge increases, (2) Click bell to see notification, (3) Toast appears in corner',
  jsonb_build_object('test', true, 'timestamp', NOW()),
  false
FROM auth.users 
WHERE email = 'your@email.com'  -- ⚠️ REPLACE WITH YOUR EMAIL
RETURNING 
  id,
  type,
  title,
  message,
  created_at,
  'Notification created! Now check:' as next_step,
  '1. Does bell badge number increase?' as check_1,
  '2. Click bell - do you see this notification?' as check_2,
  '3. Did a toast popup appear?' as check_3,
  '4. Check browser console for new logs' as check_4;
