-- Quick check: What books and reservations exist?

SELECT '=== ALL BOOKS ===' as step;
SELECT id, title, weight, status, shelf_id FROM books ORDER BY title LIMIT 10;

SELECT '=== ALL SHELVES ===' as step;
SELECT id, shelf_number, current_weight FROM shelves ORDER BY shelf_number;

SELECT '=== ALL RESERVATIONS (any status) ===' as step;
SELECT 
  r.id,
  r.status,
  r.created_at,
  r.expires_at,
  b.title as book_title,
  u.email as user_email
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN auth.users u ON r.user_id = u.id
ORDER BY r.created_at DESC
LIMIT 10;

SELECT '=== ACTIVE RESERVATIONS ===' as step;
SELECT 
  r.id,
  r.status,
  r.expires_at,
  b.title as book_title,
  b.status as book_status,
  b.shelf_id,
  u.email as user_email
FROM reservations r
JOIN books b ON r.book_id = b.id
JOIN auth.users u ON r.user_id = u.id
WHERE r.status = 'active'
ORDER BY r.created_at DESC;
