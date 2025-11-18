-- Fix the book status issue permanently

-- 1. Check if reservation trigger is enabled
SELECT 
    tgname as trigger_name,
    tgenabled as enabled,
    CASE tgenabled
        WHEN 'O' THEN 'ENABLED ✅'
        WHEN 'D' THEN 'DISABLED ❌'
        ELSE 'UNKNOWN'
    END as status
FROM pg_trigger
WHERE tgname = 'trigger_update_book_status_on_reservation';

-- 2. Manually set Book 1 to reserved RIGHT NOW
UPDATE books
SET status = 'reserved'
WHERE title = 'Book 1'
  AND id IN (SELECT book_id FROM reservations WHERE status = 'active');

-- 3. Verify it worked
SELECT 
    'Book 1 status updated' as message,
    status as current_status
FROM books
WHERE title = 'Book 1';

-- 4. Now test the pickup trigger manually
-- Add weight first
UPDATE shelves SET current_weight = 250 WHERE shelf_number = 1;

-- Wait a moment
SELECT pg_sleep(0.1);

-- Remove weight (this should trigger the pickup and issue the book)
UPDATE shelves SET current_weight = 0 WHERE shelf_number = 1;

-- 5. Check if it worked THIS TIME
SELECT 
    CASE 
        WHEN b.status = 'issued' THEN '✅✅✅ SUCCESS! Book is now ISSUED!'
        WHEN b.status = 'reserved' THEN '⚠️ Book still RESERVED (trigger did not fire)'
        ELSE '❌ Book status: ' || b.status
    END as result,
    b.status as book_status,
    r.status as reservation_status,
    (SELECT COUNT(*) FROM issued_books WHERE book_id = b.id AND returned_at IS NULL) as issued_books_count
FROM books b
LEFT JOIN reservations r ON r.book_id = b.id AND r.status IN ('active', 'completed')
WHERE b.title = 'Book 1'
ORDER BY r.reserved_at DESC
LIMIT 1;
