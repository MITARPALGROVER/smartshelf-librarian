-- Check if the book was issued after pickup

SELECT '=== BOOK 1 STATUS ===' as step;
SELECT 
  id,
  title,
  status,
  weight,
  shelf_id
FROM books
WHERE title = 'Book 1';

SELECT '=== LATEST RESERVATION FOR BOOK 1 ===' as step;
SELECT 
  r.id,
  r.status,
  r.created_at,
  r.expires_at,
  b.title,
  b.status as book_status
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE b.title = 'Book 1'
ORDER BY r.created_at DESC
LIMIT 1;

SELECT '=== ISSUED BOOKS (recent) ===' as step;
SELECT 
  ib.id,
  b.title,
  u.email as student_email,
  ib.issued_at,
  ib.due_date,
  ib.returned_at
FROM issued_books ib
JOIN books b ON ib.book_id = b.id
JOIN auth.users u ON ib.user_id = u.id
ORDER BY ib.issued_at DESC
LIMIT 5;

SELECT '=== LATEST SHELF ALERT ===' as step;
SELECT 
  created_at,
  shelf_number,
  alert_type,
  message,
  detected_weight
FROM shelf_alerts
ORDER BY created_at DESC
LIMIT 1;
