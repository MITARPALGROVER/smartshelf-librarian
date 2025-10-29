-- ============================================
-- DIRECT TEST - See What Happens
-- ============================================

-- First, let's manually insert a notification to test if the table works
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
  '🧪 TEST NOTIFICATION',
  'If you see this in your bell icon, notifications table works!',
  '{}'::jsonb
FROM auth.users
LIMIT 1;

-- Check if it was created
SELECT 
  '1. TEST NOTIFICATION CREATED' as step,
  created_at,
  title,
  message
FROM notifications
ORDER BY created_at DESC
LIMIT 1;

-- Now let's see if triggers exist
SELECT 
  '2. TRIGGERS CHECK' as step,
  COUNT(*) as trigger_count,
  CASE 
    WHEN COUNT(*) = 0 THEN '❌ NO TRIGGERS INSTALLED'
    WHEN COUNT(*) < 3 THEN '⚠️ PARTIAL INSTALLATION'
    ELSE '✅ ALL TRIGGERS INSTALLED'
  END as status
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_notify_book_reserved',
  'trigger_notify_book_issued',
  'on_shelf_weight_change'
);

-- Show trigger details
SELECT 
  '3. TRIGGER DETAILS' as step,
  trigger_name,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE trigger_name LIKE 'trigger_notify%'
   OR trigger_name = 'on_shelf_weight_change';

-- Check if user has role
SELECT 
  '4. USER ROLES CHECK' as step,
  p.email,
  ur.role
FROM profiles p
JOIN user_roles ur ON ur.user_id = p.id
LIMIT 10;

-- Now let's test creating a reservation
SELECT '5. CREATING TEST RESERVATION...' as step;

DO $$
DECLARE
  v_student_id UUID;
  v_book_id UUID;
  v_res_id UUID;
  v_notif_count_before INT;
  v_notif_count_after INT;
BEGIN
  -- Count notifications before
  SELECT COUNT(*) INTO v_notif_count_before FROM notifications;
  RAISE NOTICE 'Notifications before: %', v_notif_count_before;
  
  -- Get student
  SELECT p.id INTO v_student_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  WHERE ur.role = 'student'
  LIMIT 1;
  
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION '❌ NO STUDENT WITH ROLE FOUND';
  END IF;
  
  -- Get available book
  SELECT id INTO v_book_id
  FROM books
  WHERE status = 'available'
  LIMIT 1;
  
  IF v_book_id IS NULL THEN
    RAISE EXCEPTION '❌ NO AVAILABLE BOOKS';
  END IF;
  
  RAISE NOTICE 'Creating reservation for student: %, book: %', v_student_id, v_book_id;
  
  -- Create reservation (THIS SHOULD TRIGGER NOTIFICATION!)
  INSERT INTO reservations (
    book_id,
    user_id,
    status,
    reserved_at,
    expires_at
  ) VALUES (
    v_book_id,
    v_student_id,
    'active',
    NOW(),
    NOW() + INTERVAL '5 minutes'
  ) RETURNING id INTO v_res_id;
  
  UPDATE books SET status = 'reserved' WHERE id = v_book_id;
  
  RAISE NOTICE '✅ Reservation created: %', v_res_id;
  
  -- Wait a moment
  PERFORM pg_sleep(0.5);
  
  -- Count notifications after
  SELECT COUNT(*) INTO v_notif_count_after FROM notifications;
  RAISE NOTICE 'Notifications after: %', v_notif_count_after;
  
  IF v_notif_count_after > v_notif_count_before THEN
    RAISE NOTICE '✅✅✅ TRIGGER WORKED! % new notifications created', 
      (v_notif_count_after - v_notif_count_before);
  ELSE
    RAISE NOTICE '❌❌❌ TRIGGER DID NOT FIRE! No notifications created!';
  END IF;
END $$;

-- Check the notifications
SELECT 
  '6. ALL NOTIFICATIONS' as step,
  created_at,
  type,
  title,
  LEFT(message, 80) as message,
  (SELECT email FROM profiles WHERE id = user_id) as for_user
FROM notifications
ORDER BY created_at DESC
LIMIT 20;

-- FINAL DIAGNOSIS
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM notifications 
      WHERE created_at > NOW() - INTERVAL '10 seconds'
        AND title LIKE '%Reserved%'
    ) THEN '✅✅✅ SYSTEM WORKING! Notifications are being created!'
    
    WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_notify_book_reserved'
    ) THEN '❌ TRIGGER NOT INSTALLED - Run all_in_one_complete_setup.sql'
    
    ELSE '❌ TRIGGER EXISTS BUT NOT FIRING - Check trigger function code'
  END as final_diagnosis;
