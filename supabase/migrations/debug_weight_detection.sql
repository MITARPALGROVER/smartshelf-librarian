-- Debug: Check what the weight detection trigger sees
-- This will show us why the book isn't being matched

-- First, check current state
SELECT '=== CURRENT STATE ===' as step;

SELECT 
  b.id as book_id,
  b.title,
  b.weight as book_weight,
  b.status as book_status,
  b.shelf_id,
  s.shelf_number,
  s.current_weight as shelf_current_weight,
  r.id as reservation_id,
  r.status as reservation_status,
  r.expires_at,
  (r.expires_at < NOW()) as is_expired
FROM books b
LEFT JOIN shelves s ON b.shelf_id = s.id
LEFT JOIN reservations r ON r.book_id = b.id AND r.status = 'active'
WHERE b.title = 'Book 2';

-- Check if there's an active reservation
SELECT '=== ACTIVE RESERVATIONS FOR BOOK 2 ===' as step;

SELECT 
  r.*,
  b.title,
  b.weight,
  b.status as book_status
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE b.title = 'Book 2'
  AND r.status = 'active';

-- Check what books match the weight when we remove 247g
-- This simulates what the trigger sees
SELECT '=== WEIGHT MATCHING TEST (simulating 247g removal) ===' as step;

WITH shelf_info AS (
  SELECT id, shelf_number, current_weight 
  FROM shelves 
  WHERE shelf_number = 2
)
SELECT 
  b.id,
  b.title,
  b.weight as book_weight,
  b.status,
  ABS(b.weight - 247) as weight_difference,
  CASE 
    WHEN ABS(b.weight - 247) < 20 THEN '✅ MATCHES (diff < 20g)'
    ELSE '❌ NO MATCH (diff >= 20g)'
  END as matching_status,
  b.shelf_id = (SELECT id FROM shelf_info) as on_correct_shelf
FROM books b
WHERE b.shelf_id = (SELECT id FROM shelf_info)
  AND b.status IN ('available', 'reserved')
ORDER BY ABS(b.weight - 247);

-- Check recent shelf alerts to see what was detected
SELECT '=== RECENT SHELF ALERTS ===' as step;

SELECT 
  created_at,
  shelf_number,
  alert_type,
  message,
  detected_weight
FROM shelf_alerts
ORDER BY created_at DESC
LIMIT 5;
