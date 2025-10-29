-- ============================================
-- COMPLETE NOTIFICATION TEST - STEP BY STEP
-- Follow this exact sequence to test notifications
-- ============================================

-- ============================================
-- STEP 1: Check Current State
-- ============================================

-- 1a. Check if triggers exist
SELECT 
  '1. TRIGGERS CHECK' as step,
  trigger_name,
  event_object_table as on_table
FROM information_schema.triggers
WHERE trigger_name IN ('trigger_notify_book_reserved', 'trigger_notify_book_issued', 'on_shelf_weight_change')
ORDER BY event_object_table;

-- Expected: Should show 3 triggers

-- 1b. Check if Realtime is enabled
SELECT 
  '2. REALTIME CHECK' as step,
  tablename
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('notifications', 'reservations', 'issued_books');

-- Expected: Should show notifications, reservations, issued_books

-- 1c. Check available books
SELECT 
  '3. AVAILABLE BOOKS' as step,
  b.id,
  b.title,
  b.status,
  b.weight,
  s.shelf_number
FROM books b
LEFT JOIN shelves s ON s.id = b.shelf_id
WHERE b.status = 'available'
ORDER BY s.shelf_number
LIMIT 5;

-- Expected: Should show some available books

-- 1d. Check user roles
SELECT 
  '4. USER ROLES' as step,
  p.email,
  ur.role
FROM profiles p
JOIN user_roles ur ON ur.user_id = p.id
ORDER BY ur.role;

-- Expected: Should show at least one student and one librarian

-- ============================================
-- STEP 2: Manual Test - Create Test Reservation
-- ============================================

-- If you want to test notifications RIGHT NOW without using the UI,
-- run this to create a test reservation:

DO $$
DECLARE
  test_student_id UUID;
  test_book_id UUID;
  test_reservation_id UUID;
BEGIN
  -- Get a student user
  SELECT p.id INTO test_student_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  WHERE ur.role = 'student'
  LIMIT 1;
  
  -- Get an available book
  SELECT id INTO test_book_id
  FROM books
  WHERE status = 'available'
  LIMIT 1;
  
  IF test_student_id IS NULL THEN
    RAISE EXCEPTION 'No student user found. Create a student account first.';
  END IF;
  
  IF test_book_id IS NULL THEN
    RAISE EXCEPTION 'No available books found. Add books first.';
  END IF;
  
  -- Create reservation (this should trigger notification!)
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
  
  -- Update book status
  UPDATE books
  SET status = 'reserved'
  WHERE id = test_book_id;
  
  RAISE NOTICE '✅ TEST RESERVATION CREATED!';
  RAISE NOTICE 'Reservation ID: %', test_reservation_id;
  RAISE NOTICE 'Book ID: %', test_book_id;
  RAISE NOTICE 'Student ID: %', test_student_id;
  RAISE NOTICE '';
  RAISE NOTICE '🔔 CHECK YOUR NOTIFICATIONS NOW!';
  RAISE NOTICE 'You should see:';
  RAISE NOTICE '  - Student gets: "🎉 Book Reserved!"';
  RAISE NOTICE '  - Librarian gets: "📅 New Reservation"';
  
END $$;

-- ============================================
-- STEP 3: Check if Notifications Were Created
-- ============================================

-- Wait 2-3 seconds, then run this:
SELECT 
  '5. NOTIFICATIONS CHECK' as step,
  created_at,
  type,
  title,
  LEFT(message, 50) as message_preview,
  (SELECT email FROM profiles WHERE id = user_id) as recipient_email
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- Expected: Should show notifications with titles:
--   "🎉 Book Reserved!" (for student)
--   "📅 New Reservation" (for librarian)

-- ============================================
-- STEP 4: Simulate Book Pickup (Testing Panel Equivalent)
-- ============================================

-- Now simulate the pickup (what Testing Panel "Pickup" button does):
DO $$
DECLARE
  test_reservation RECORD;
  test_shelf_id UUID;
  test_current_weight DECIMAL;
  test_book_weight DECIMAL;
  test_new_weight DECIMAL;
BEGIN
  -- Get the most recent active reservation
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
    RAISE EXCEPTION 'No active reservations. Reserve a book first!';
  END IF;
  
  -- Calculate new weight (simulate book removal)
  test_new_weight := test_reservation.current_weight - test_reservation.weight;
  
  RAISE NOTICE '📖 SIMULATING BOOK PICKUP...';
  RAISE NOTICE 'Shelf: %', test_reservation.shelf_number;
  RAISE NOTICE 'Book weight: %g', test_reservation.weight;
  RAISE NOTICE 'Current shelf weight: %g', test_reservation.current_weight;
  RAISE NOTICE 'New shelf weight: %g', test_new_weight;
  
  -- Update shelf weight (THIS TRIGGERS THE WEIGHT DETECTION!)
  UPDATE shelves
  SET current_weight = test_new_weight
  WHERE id = test_reservation.shelf_id;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ WEIGHT UPDATED - TRIGGER SHOULD FIRE NOW!';
  RAISE NOTICE '🔔 CHECK NOTIFICATIONS AGAIN!';
  RAISE NOTICE 'You should see:';
  RAISE NOTICE '  - Student gets: "✅ Book Issued Successfully"';
  RAISE NOTICE '  - Librarian gets: "📖 Book Picked Up"';
  
END $$;

-- ============================================
-- STEP 5: Verify Pickup Worked
-- ============================================

-- Wait 2-3 seconds, then check:

-- 5a. Check issued_books table
SELECT 
  '6a. ISSUED BOOKS' as step,
  ib.issued_at,
  ib.due_date,
  b.title as book_title,
  p.email as student_email
FROM issued_books ib
JOIN books b ON b.id = ib.book_id
JOIN profiles p ON p.id = ib.user_id
WHERE ib.returned_at IS NULL
ORDER BY ib.issued_at DESC
LIMIT 5;

-- Expected: Should show the newly issued book

-- 5b. Check reservation status
SELECT 
  '6b. RESERVATION STATUS' as step,
  r.reserved_at,
  r.status,
  b.title as book_title
FROM reservations r
JOIN books b ON b.id = r.book_id
ORDER BY r.reserved_at DESC
LIMIT 5;

-- Expected: Most recent reservation should have status = 'completed'

-- 5c. Check book status
SELECT 
  '6c. BOOK STATUS' as step,
  b.title,
  b.status
FROM books b
WHERE b.status = 'issued'
ORDER BY b.updated_at DESC
LIMIT 5;

-- Expected: Book should now have status = 'issued'

-- 5d. Check notifications AGAIN
SELECT 
  '6d. ALL NOTIFICATIONS' as step,
  created_at,
  type,
  title,
  LEFT(message, 60) as message_preview,
  (SELECT email FROM profiles WHERE id = user_id) as recipient_email
FROM notifications
ORDER BY created_at DESC
LIMIT 20;

-- Expected: Should now show FOUR notifications total:
--   1. "🎉 Book Reserved!" (student)
--   2. "📅 New Reservation" (librarian)
--   3. "✅ Book Issued Successfully" (student) <-- NEW
--   4. "📖 Book Picked Up" (librarian) <-- NEW

-- ============================================
-- SUMMARY
-- ============================================
SELECT 
  '====== TEST COMPLETE ======' as status,
  'If you see all 4 notifications above, the system works!' as result;

SELECT 
  'Next: Try the same flow in the UI!' as next_step,
  '1. Reserve book as student' as step1,
  '2. Go to Testing Panel' as step2,
  '3. Click "Pickup" button' as step3,
  '4. Check notification bell icon' as step4;
