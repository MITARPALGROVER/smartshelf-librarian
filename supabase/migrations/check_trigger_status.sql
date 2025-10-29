-- Check if the enhanced trigger with logging is installed

SELECT '=== CHECK TRIGGER ===' as step;
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'on_shelf_weight_change';

SELECT '=== CHECK FUNCTION ===' as step;
SELECT 
  routine_name,
  routine_type,
  CASE 
    WHEN routine_definition LIKE '%RAISE NOTICE%' THEN '✅ Has logging'
    ELSE '❌ No logging'
  END as has_logging
FROM information_schema.routines
WHERE routine_name = 'detect_book_from_weight_change';

-- Now let's manually test the scenario
SELECT '=== CURRENT ACTIVE RESERVATION ===' as step;
SELECT 
  r.id as reservation_id,
  r.user_id,
  b.id as book_id,
  b.title,
  b.weight as book_weight,
  b.status as book_status,
  b.shelf_id as book_shelf_id,
  s.id as shelf_id,
  s.shelf_number,
  s.current_weight as shelf_current_weight,
  r.expires_at,
  (r.expires_at < NOW()) as is_expired,
  ABS(b.weight - s.current_weight) as weight_diff
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
ORDER BY r.created_at DESC
LIMIT 1;

-- Test: What happens if we manually simulate the pickup?
SELECT '=== SIMULATION: Remove book weight from shelf ===' as step;
SELECT 
  'Run this command to test:' as instruction,
  format(
    'UPDATE shelves SET current_weight = 0 WHERE shelf_number = %s;',
    s.shelf_number
  ) as command,
  'Then check if book status changes to issued' as expected
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
LIMIT 1;
