-- Comprehensive diagnostic for book pickup issue
-- Run this to understand why the book isn't getting issued

-- STEP 1: Check current reservation status
SELECT '=== ACTIVE RESERVATIONS ===' as step;
SELECT 
  r.id as reservation_id,
  u.email as student_email,
  b.title as book_title,
  b.status as book_status,
  r.status as reservation_status,
  r.reserved_at,
  r.expires_at,
  CASE 
    WHEN r.expires_at < NOW() THEN '⏰ EXPIRED'
    ELSE '✅ VALID (' || EXTRACT(EPOCH FROM (r.expires_at - NOW()))/60 || ' min remaining)'
  END as expiry_status,
  s.shelf_number,
  s.current_weight as shelf_weight,
  b.weight as book_weight
FROM reservations r
JOIN auth.users u ON r.user_id = u.id
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC;

-- STEP 2: Check if trigger exists
SELECT '=== TRIGGER STATUS ===' as step;
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement,
  action_timing,
  CASE 
    WHEN trigger_name = 'on_shelf_weight_change' THEN '✅ Exists'
    ELSE '❌ Missing'
  END as status
FROM information_schema.triggers
WHERE trigger_name = 'on_shelf_weight_change';

-- STEP 3: Check function exists
SELECT '=== FUNCTION STATUS ===' as step;
SELECT 
  routine_name,
  routine_type,
  CASE 
    WHEN routine_name = 'detect_book_from_weight_change' THEN '✅ Exists'
    ELSE '❌ Missing'
  END as status
FROM information_schema.routines
WHERE routine_name = 'detect_book_from_weight_change'
  AND routine_schema = 'public';

-- STEP 4: Check recent issued_books records
SELECT '=== RECENT ISSUED BOOKS ===' as step;
SELECT 
  ib.id,
  u.email as student_email,
  b.title as book_title,
  b.status as current_book_status,
  ib.issued_at,
  ib.due_date,
  ib.returned_at
FROM issued_books ib
JOIN auth.users u ON ib.user_id = u.id
JOIN books b ON ib.book_id = b.id
ORDER BY ib.issued_at DESC
LIMIT 10;

-- STEP 5: Check recent shelf_alerts
SELECT '=== RECENT SHELF ALERTS ===' as step;
SELECT 
  sa.id,
  sa.shelf_number,
  sa.alert_type,
  sa.message,
  sa.detected_weight,
  sa.created_at,
  b.title as book_title
FROM shelf_alerts sa
LEFT JOIN books b ON sa.book_id = b.id
ORDER BY sa.created_at DESC
LIMIT 10;

-- STEP 6: Check database logs (if enabled)
-- This shows the RAISE NOTICE messages from the trigger
SELECT '=== CHECKING DATABASE LOGS ===' as step;
SELECT 
  'Run this in psql to see logs: SELECT * FROM pg_stat_statements;' as info,
  'Or check Supabase Logs in dashboard for RAISE NOTICE messages' as alternative;

-- STEP 7: Manual test - Try to update shelf weight and see what happens
SELECT '=== MANUAL TEST ===' as step;
SELECT 
  'Now manually reduce shelf weight to simulate pickup:' as instruction,
  format(
    'UPDATE shelves SET current_weight = current_weight - %s WHERE shelf_number = %s;',
    b.weight,
    s.shelf_number
  ) as test_command,
  'Then check if book status changes to ''issued''' as expected_result
FROM books b
JOIN shelves s ON b.shelf_id = s.id
WHERE b.status = 'reserved'
LIMIT 1;

-- STEP 8: Check if there's an active reservation with details
SELECT '=== DETAILED RESERVATION CHECK ===' as step;
SELECT 
  r.id as reservation_id,
  r.book_id,
  r.user_id,
  r.status as reservation_status,
  r.expires_at,
  (r.expires_at < NOW()) as is_expired,
  b.status as book_status,
  b.weight as book_weight,
  s.current_weight as shelf_weight,
  s.shelf_number
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC
LIMIT 1;
