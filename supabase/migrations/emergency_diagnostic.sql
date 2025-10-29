-- ============================================
-- EMERGENCY DIAGNOSTIC - Find What's Wrong
-- Run this to see exactly what's missing
-- ============================================

-- ============================================
-- 1. Check if ALL-IN-ONE setup was run
-- ============================================
SELECT '1️⃣ CHECKING TRIGGERS' as step;

SELECT 
  trigger_name,
  event_object_table,
  action_timing || ' ' || event_manipulation as when_fires
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_notify_book_reserved',
  'trigger_notify_book_issued',
  'on_shelf_weight_change'
);

-- Expected: Should show 3 rows
-- If 0 rows: You need to run all_in_one_complete_setup.sql

-- ============================================
-- 2. Check if functions exist
-- ============================================
SELECT '2️⃣ CHECKING FUNCTIONS' as step;

SELECT 
  routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'notify_book_reserved',
    'notify_book_issued',
    'detect_book_from_weight_change'
  );

-- Expected: Should show 3 rows
-- If missing: Run all_in_one_complete_setup.sql

-- ============================================
-- 3. Check Realtime Publication
-- ============================================
SELECT '3️⃣ CHECKING REALTIME' as step;

SELECT tablename
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('notifications', 'reservations', 'issued_books', 'books');

-- Expected: Should show all 4 tables
-- If missing: Run the realtime fix below

-- ============================================
-- 4. MANUAL TEST: Create reservation WITHOUT UI
-- ============================================
SELECT '4️⃣ MANUAL RESERVATION TEST' as step;

DO $$
DECLARE
  test_student_id UUID;
  test_book_id UUID;
  test_shelf_id UUID;
  test_reservation_id UUID;
  notification_count INT;
BEGIN
  -- Get student
  SELECT p.id INTO test_student_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  WHERE ur.role = 'student'
  LIMIT 1;
  
  -- Get available book with shelf
  SELECT b.id, b.shelf_id INTO test_book_id, test_shelf_id
  FROM books b
  WHERE b.status = 'available'
    AND b.shelf_id IS NOT NULL
  LIMIT 1;
  
  IF test_student_id IS NULL THEN
    RAISE EXCEPTION '❌ NO STUDENT FOUND! Create a student account with role in user_roles table';
  END IF;
  
  IF test_book_id IS NULL THEN
    RAISE EXCEPTION '❌ NO AVAILABLE BOOKS! Add books in admin dashboard';
  END IF;
  
  RAISE NOTICE '📝 Creating test reservation...';
  RAISE NOTICE 'Student: %', test_student_id;
  RAISE NOTICE 'Book: %', test_book_id;
  
  -- Count notifications BEFORE
  SELECT COUNT(*) INTO notification_count FROM notifications;
  RAISE NOTICE 'Notifications BEFORE: %', notification_count;
  
  -- CREATE RESERVATION (should trigger notification)
  INSERT INTO reservations (
    book_id,
    user_id,
    status,
    reserved_at,
    expires_at
  ) VALUES (
    test_book_id,
    test_student_id,
    'active',
    NOW(),
    NOW() + INTERVAL '5 minutes'
  ) RETURNING id INTO test_reservation_id;
  
  UPDATE books SET status = 'reserved' WHERE id = test_book_id;
  
  RAISE NOTICE '✅ Reservation created: %', test_reservation_id;
  
  -- Wait a moment for trigger
  PERFORM pg_sleep(1);
  
  -- Count notifications AFTER
  SELECT COUNT(*) INTO notification_count FROM notifications;
  RAISE NOTICE 'Notifications AFTER: %', notification_count;
  
  -- Check if notifications were created
  IF EXISTS (
    SELECT 1 FROM notifications 
    WHERE created_at > NOW() - INTERVAL '5 seconds'
  ) THEN
    RAISE NOTICE '✅ TRIGGERS WORKING! Notifications created!';
  ELSE
    RAISE NOTICE '❌ TRIGGERS NOT WORKING! No notifications created!';
    RAISE NOTICE 'Action: Run all_in_one_complete_setup.sql';
  END IF;
  
END $$;

-- ============================================
-- 5. Check if notifications were created
-- ============================================
SELECT '5️⃣ RECENT NOTIFICATIONS' as step;

SELECT 
  created_at,
  type,
  title,
  LEFT(message, 60) as message,
  (SELECT email FROM profiles WHERE id = user_id) as for_user
FROM notifications
WHERE created_at > NOW() - INTERVAL '1 minute'
ORDER BY created_at DESC;

-- Expected: Should show at least 2 notifications
-- If empty: TRIGGERS ARE NOT WORKING

-- ============================================
-- 6. MANUAL TEST: Simulate pickup
-- ============================================
SELECT '6️⃣ MANUAL PICKUP TEST' as step;

DO $$
DECLARE
  test_reservation RECORD;
  test_new_weight DECIMAL;
  issued_count_before INT;
  issued_count_after INT;
BEGIN
  -- Get active reservation
  SELECT 
    r.id,
    r.book_id,
    r.user_id,
    b.weight,
    b.shelf_id,
    s.current_weight,
    s.shelf_number
  INTO test_reservation
  FROM reservations r
  JOIN books b ON b.id = r.book_id
  JOIN shelves s ON s.id = b.shelf_id
  WHERE r.status = 'active'
  ORDER BY r.reserved_at DESC
  LIMIT 1;
  
  IF test_reservation IS NULL THEN
    RAISE NOTICE '⚠️ No active reservations to test pickup';
    RETURN;
  END IF;
  
  -- Count issued books BEFORE
  SELECT COUNT(*) INTO issued_count_before FROM issued_books;
  RAISE NOTICE 'Issued books BEFORE: %', issued_count_before;
  
  -- Simulate pickup (decrease weight)
  test_new_weight := test_reservation.current_weight - test_reservation.weight;
  
  RAISE NOTICE '📖 Simulating pickup...';
  RAISE NOTICE 'Shelf: %', test_reservation.shelf_number;
  RAISE NOTICE 'Weight change: %g → %g', test_reservation.current_weight, test_new_weight;
  
  -- UPDATE WEIGHT (should trigger weight detection)
  UPDATE shelves
  SET current_weight = test_new_weight
  WHERE id = test_reservation.shelf_id;
  
  RAISE NOTICE '✅ Weight updated';
  
  -- Wait for trigger
  PERFORM pg_sleep(1);
  
  -- Count issued books AFTER
  SELECT COUNT(*) INTO issued_count_after FROM issued_books;
  RAISE NOTICE 'Issued books AFTER: %', issued_count_after;
  
  -- Check if book was issued
  IF issued_count_after > issued_count_before THEN
    RAISE NOTICE '✅ WEIGHT TRIGGER WORKING! Book was issued!';
  ELSE
    RAISE NOTICE '❌ WEIGHT TRIGGER NOT WORKING! Book was NOT issued!';
    RAISE NOTICE 'Action: Run all_in_one_complete_setup.sql';
  END IF;
  
END $$;

-- ============================================
-- 7. Check issued books
-- ============================================
SELECT '7️⃣ RECENT ISSUED BOOKS' as step;

SELECT 
  ib.issued_at,
  b.title,
  p.email as student
FROM issued_books ib
JOIN books b ON b.id = ib.book_id
JOIN profiles p ON p.id = ib.user_id
WHERE ib.issued_at > NOW() - INTERVAL '1 minute'
ORDER BY ib.issued_at DESC;

-- Expected: Should show newly issued book
-- If empty: Weight trigger is not working

-- ============================================
-- 8. Check reservation status
-- ============================================
SELECT '8️⃣ RESERVATION STATUS' as step;

SELECT 
  r.reserved_at,
  r.status,
  r.expires_at,
  b.title,
  p.email as student
FROM reservations r
JOIN books b ON b.id = r.book_id
JOIN profiles p ON p.id = r.user_id
WHERE r.reserved_at > NOW() - INTERVAL '5 minutes'
ORDER BY r.reserved_at DESC;

-- Expected: 
-- - If pickup worked: status should be 'completed'
-- - If pickup didn't work: status still 'active'

-- ============================================
-- DIAGNOSIS SUMMARY
-- ============================================
SELECT '═══════════════════════════════════════' as result;
SELECT 'DIAGNOSIS COMPLETE' as result;
SELECT '═══════════════════════════════════════' as result;
SELECT '' as result;
SELECT 'Check the results above:' as result;
SELECT '' as result;
SELECT '✅ If triggers exist (step 1-2): Triggers are installed' as result;
SELECT '❌ If 0 triggers: RUN all_in_one_complete_setup.sql' as result;
SELECT '' as result;
SELECT '✅ If notifications created (step 5): Reservation trigger works' as result;
SELECT '❌ If no notifications: Triggers not firing - check logs' as result;
SELECT '' as result;
SELECT '✅ If issued_books created (step 7): Pickup trigger works' as result;
SELECT '❌ If no issued_books: Weight trigger not working' as result;
SELECT '' as result;
SELECT '✅ If realtime tables shown (step 3): Frontend will update' as result;
SELECT '❌ If missing: Run realtime fix at bottom of this file' as result;

-- ============================================
-- QUICK FIX: If anything is missing, run this
-- ============================================

/*

-- If triggers are missing, run this entire file:
-- File: all_in_one_complete_setup.sql

-- If realtime is missing, run this:

DO $$ 
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE reservations;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE issued_books;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE books;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

*/
