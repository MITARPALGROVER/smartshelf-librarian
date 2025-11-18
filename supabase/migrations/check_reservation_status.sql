-- Check why trigger isn't issuing the book

-- Show everything in one query
SELECT 
    'RESERVATION CHECK' as check_type,
    r.id as reservation_id,
    r.status as reservation_status,
    r.expires_at,
    CASE 
        WHEN r.expires_at > NOW() THEN 'Valid'
        ELSE 'EXPIRED'
    END as expiry_status,
    b.title as book_title,
    b.status as book_status,
    b.weight as book_weight,
    r.user_id
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE b.title = 'Book 1'
  AND r.status = 'active'
ORDER BY r.reserved_at DESC
LIMIT 1;

-- If no results above, check if reservation exists but is not active
SELECT 
    'ALL BOOK 1 RESERVATIONS' as check_type,
    r.id as reservation_id,
    r.status as reservation_status,
    r.expires_at,
    b.status as book_status
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE b.title = 'Book 1'
ORDER BY r.reserved_at DESC
LIMIT 3;

-- Check book status directly
SELECT 
    'BOOK STATUS' as check_type,
    status as book_status,
    shelf_id
FROM books 
WHERE title = 'Book 1';
