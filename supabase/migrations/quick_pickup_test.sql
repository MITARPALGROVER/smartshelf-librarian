-- Quick pickup test

-- First check current state
SELECT '=== BEFORE PICKUP ===' as step;
SELECT 
  b.title,
  b.status as book_status,
  b.weight,
  r.status as reservation_status,
  r.expires_at,
  (r.expires_at < NOW()) as is_expired,
  s.shelf_number,
  s.current_weight
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active';

-- Simulate pickup
DO $$
DECLARE
  v_shelf_number INT;
  v_book_weight DECIMAL;
BEGIN
  SELECT s.shelf_number, b.weight
  INTO v_shelf_number, v_book_weight
  FROM reservations r
  JOIN books b ON r.book_id = b.id
  JOIN shelves s ON b.shelf_id = s.id
  WHERE r.status = 'active'
  LIMIT 1;

  IF v_shelf_number IS NOT NULL THEN
    RAISE NOTICE '🧪 TEST: Adding weight %g to Shelf %', v_book_weight, v_shelf_number;
    UPDATE shelves SET current_weight = v_book_weight WHERE shelf_number = v_shelf_number;
    
    PERFORM pg_sleep(0.5);
    
    RAISE NOTICE '🧪 TEST: Removing weight from Shelf % (simulating pickup)', v_shelf_number;
    UPDATE shelves SET current_weight = 0 WHERE shelf_number = v_shelf_number;
  END IF;
END $$;

-- Check result
SELECT '=== AFTER PICKUP ===' as step;
SELECT 
  b.title,
  b.status as book_status,
  r.status as reservation_status,
  CASE 
    WHEN b.status = 'issued' AND r.status = 'completed' THEN '✅ SUCCESS! Book was issued!'
    WHEN b.status = 'reserved' AND r.status = 'active' THEN '❌ FAILED: Book still reserved'
    ELSE '⚠️ UNEXPECTED: ' || b.status || ' / ' || r.status
  END as result,
  (SELECT COUNT(*) FROM issued_books WHERE book_id = b.id AND returned_at IS NULL) as issued_records
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE r.id = (SELECT id FROM reservations WHERE status IN ('active', 'completed') ORDER BY reserved_at DESC LIMIT 1);

-- Show any issued_books records
SELECT '=== ISSUED BOOKS ===' as step;
SELECT * FROM issued_books WHERE returned_at IS NULL ORDER BY issued_at DESC LIMIT 3;
