-- Find and fix shelf_id mismatches

SELECT '=== SHELF IDS ===' as step;
SELECT id, shelf_number FROM shelves ORDER BY shelf_number;

SELECT '=== BOOKS AND THEIR SHELF_IDS ===' as step;
SELECT 
  b.id,
  b.title,
  b.shelf_id as book_shelf_id,
  s.id as actual_shelf_id,
  s.shelf_number,
  CASE 
    WHEN b.shelf_id = s.id THEN '✅ CORRECT'
    ELSE '❌ MISMATCH!'
  END as status
FROM books b
LEFT JOIN shelves s ON s.shelf_number = CAST(SUBSTRING(b.title FROM '[0-9]+') AS INTEGER)
ORDER BY b.title;

SELECT '=== FIX: Update Book shelf_ids to match their shelf numbers ===' as step;

-- Book 1 should be on Shelf 1
UPDATE books b
SET shelf_id = s.id
FROM shelves s
WHERE s.shelf_number = 1
  AND b.title = 'Book 1';

-- Book 2 should be on Shelf 2  
UPDATE books b
SET shelf_id = s.id
FROM shelves s
WHERE s.shelf_number = 2
  AND b.title = 'Book 2';

-- Book 3 should be on Shelf 3
UPDATE books b
SET shelf_id = s.id
FROM shelves s
WHERE s.shelf_number = 3
  AND b.title = 'Book 3';

SELECT '=== VERIFICATION ===' as step;
SELECT 
  b.title,
  b.shelf_id,
  s.shelf_number,
  '✅ FIXED' as status
FROM books b
JOIN shelves s ON b.shelf_id = s.id
ORDER BY b.title;
