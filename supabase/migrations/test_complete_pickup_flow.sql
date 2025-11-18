-- Complete test of the pickup flow

-- Step 1: Check if enhanced trigger is installed
SELECT '=== STEP 1: Check if trigger exists ===' as step;
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'on_shelf_weight_change';

-- Step 2: Get active reservation details
SELECT '=== STEP 2: Active reservation details ===' as step;
SELECT 
  r.id as reservation_id,
  r.user_id,
  r.expires_at,
  (r.expires_at < NOW()) as is_expired,
  b.id as book_id,
  b.title,
  b.status as book_status,
  b.weight as book_weight,
  b.shelf_id as book_shelf_id,
  s.id as shelf_id,
  s.shelf_number,
  s.current_weight as shelf_current_weight
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC
LIMIT 1;

-- Step 3: Manual test - simulate pickup
-- First, let's get the book weight and shelf number
DO $$
DECLARE
  v_shelf_number INT;
  v_book_weight DECIMAL;
  v_book_id UUID;
BEGIN
  -- Get active reservation details
  SELECT s.shelf_number, b.weight, b.id
  INTO v_shelf_number, v_book_weight, v_book_id
  FROM reservations r
  JOIN books b ON r.book_id = b.id
  JOIN shelves s ON b.shelf_id = s.id
  WHERE r.status = 'active'
  LIMIT 1;

  IF v_shelf_number IS NOT NULL THEN
    RAISE NOTICE 'Found active reservation:';
    RAISE NOTICE '  Shelf: %', v_shelf_number;
    RAISE NOTICE '  Book weight: %g', v_book_weight;
    RAISE NOTICE '  Book ID: %', v_book_id;
    
    -- Now simulate adding the book weight first
    RAISE NOTICE 'Step 1: Adding book weight to shelf...';
    UPDATE shelves SET current_weight = v_book_weight WHERE shelf_number = v_shelf_number;
    
    -- Wait a moment (simulate student picking up)
    PERFORM pg_sleep(1);
    
    -- Now simulate removing the book (pickup)
    RAISE NOTICE 'Step 2: Removing book weight (simulating pickup)...';
    UPDATE shelves SET current_weight = 0 WHERE shelf_number = v_shelf_number;
    
    RAISE NOTICE 'Pickup simulation complete! Check logs above for trigger messages.';
  ELSE
    RAISE NOTICE 'No active reservations found to test with.';
  END IF;
END $$;

-- Step 4: Check results
SELECT '=== STEP 4: Check if book was issued ===' as step;
SELECT 
  b.title,
  b.status as book_status,
  r.status as reservation_status,
  CASE 
    WHEN EXISTS (SELECT 1 FROM issued_books WHERE book_id = b.id AND returned_at IS NULL)
    THEN '✅ Book was issued!'
    ELSE '❌ Book was NOT issued'
  END as issue_status
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE r.id = (SELECT id FROM reservations WHERE status IN ('active', 'completed') ORDER BY reserved_at DESC LIMIT 1);
