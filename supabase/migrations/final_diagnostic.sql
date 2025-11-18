-- FINAL COMPREHENSIVE DIAGNOSTIC
-- This will tell us exactly what's wrong

-- 1. Check if trigger exists and is enabled
SELECT '=== 1. TRIGGER STATUS ===' as step;
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_shelf_weight_change';

-- 2. Check current reservation and book state
SELECT '=== 2. CURRENT STATE ===' as step;
SELECT 
  'Book: ' || b.title as info,
  'Book Status: ' || b.status as book_status,
  'Reservation Status: ' || r.status as reservation_status,
  'Book shelf_id: ' || b.shelf_id::text as book_shelf_id,
  'Shelf shelf_id: ' || s.id::text as actual_shelf_id,
  'Match: ' || CASE WHEN b.shelf_id = s.id THEN 'YES ✅' ELSE 'NO ❌' END as shelf_match,
  'Book weight: ' || b.weight::text || 'g' as book_weight,
  'Shelf weight: ' || s.current_weight::text || 'g' as shelf_weight
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON s.shelf_number = 1
WHERE r.status = 'active'
LIMIT 1;

-- 3. Manually trigger the function to see if it works
SELECT '=== 3. MANUAL TRIGGER TEST ===' as step;

-- First, set book to reserved
UPDATE books SET status = 'reserved' WHERE title = 'Book 1';

-- Add weight
UPDATE shelves SET current_weight = 250 WHERE shelf_number = 1;

-- Wait
SELECT pg_sleep(0.2);

-- Remove weight (this should trigger the function)
UPDATE shelves SET current_weight = 0 WHERE shelf_number = 1;

SELECT 'Trigger should have fired! Check results below...' as status;

-- 4. Check what happened
SELECT '=== 4. RESULT AFTER MANUAL TRIGGER ===' as step;
SELECT 
  b.title,
  b.status as book_status,
  r.status as reservation_status,
  CASE 
    WHEN b.status = 'issued' AND r.status = 'completed' THEN '✅✅✅ SUCCESS! IT WORKED!'
    ELSE '❌❌❌ FAILED: ' || b.status || ' / ' || r.status
  END as final_result
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE b.title = 'Book 1'
ORDER BY r.reserved_at DESC
LIMIT 1;

-- 5. Check if issued_books record was created
SELECT '=== 5. ISSUED_BOOKS CHECK ===' as step;
SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ issued_books record EXISTS!'
    ELSE '❌ NO issued_books record found'
  END as issued_books_status,
  COUNT(*) as count
FROM issued_books
WHERE book_id = (SELECT id FROM books WHERE title = 'Book 1')
  AND returned_at IS NULL;

-- 6. Show recent shelf_alerts (might have error messages)
SELECT '=== 6. RECENT ALERTS ===' as step;
SELECT 
  created_at,
  alert_type,
  message
FROM shelf_alerts
ORDER BY created_at DESC
LIMIT 3;
