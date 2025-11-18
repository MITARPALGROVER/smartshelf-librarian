-- Debug why book matching is failing

-- 1. Show all active reservations with book details
SELECT '=== ACTIVE RESERVATIONS ===' as section;
SELECT 
    r.id as reservation_id,
    r.user_id,
    r.status as reservation_status,
    r.reserved_at,
    r.expires_at,
    CASE 
        WHEN r.expires_at > NOW() THEN 'Valid ✅'
        ELSE 'EXPIRED ❌'
    END as expiry_status,
    b.id as book_id,
    b.title,
    b.status as book_status,
    b.weight,
    b.shelf_id,
    s.shelf_number,
    s.current_weight as shelf_current_weight
FROM reservations r
JOIN books b ON r.book_id = b.id
LEFT JOIN shelves s ON b.shelf_id = s.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC;

-- 2. Show Book 1 specifically
SELECT '=== BOOK 1 DETAILS ===' as section;
SELECT 
    id,
    title,
    status,
    weight,
    shelf_id,
    (SELECT shelf_number FROM shelves WHERE id = books.shelf_id) as shelf_number
FROM books 
WHERE title = 'Book 1';

-- 3. Show Shelf 1 details
SELECT '=== SHELF 1 DETAILS ===' as section;
SELECT 
    id,
    shelf_number,
    current_weight,
    (SELECT COUNT(*) FROM books WHERE shelf_id = shelves.id) as books_on_shelf
FROM shelves 
WHERE shelf_number = 1;

-- 4. Test the exact matching logic the trigger uses
SELECT '=== MATCHING TEST ===' as section;
WITH weight_change AS (
    SELECT 
        id as shelf_id,
        250.0 as weight_removed  -- The weight we detected
    FROM shelves 
    WHERE shelf_number = 1
)
SELECT 
    'Testing match for 250g removed from Shelf 1' as test,
    b.id as book_id,
    b.title,
    b.weight,
    b.shelf_id,
    wc.shelf_id as changed_shelf_id,
    wc.weight_removed,
    CASE WHEN b.shelf_id = wc.shelf_id THEN 'Shelf Match ✅' ELSE 'Shelf Mismatch ❌' END as shelf_check,
    CASE WHEN ABS(b.weight - wc.weight_removed) <= 10 THEN 'Weight Match ✅' ELSE 'Weight Mismatch ❌' END as weight_check
FROM weight_change wc
LEFT JOIN books b ON b.shelf_id = wc.shelf_id 
    AND ABS(b.weight - wc.weight_removed) <= 10
LEFT JOIN reservations r ON r.book_id = b.id 
    AND r.status = 'active' 
    AND r.expires_at > NOW();
