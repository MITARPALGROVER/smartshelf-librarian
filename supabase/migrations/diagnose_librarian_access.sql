-- Diagnostic: Check what data librarian should see

-- Test the role function
SELECT '=== YOUR ROLE ===' as step;
SELECT get_user_role() as your_role;

-- Check active reservations WITHOUT RLS (as admin)
SELECT '=== ALL ACTIVE RESERVATIONS (RAW) ===' as step;
SELECT 
  r.id,
  r.user_id,
  r.book_id,
  r.status,
  r.reserved_at,
  r.expires_at
FROM reservations r
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC;

-- Check with the same query the frontend uses
SELECT '=== FRONTEND QUERY SIMULATION ===' as step;
SELECT 
  r.id,
  r.reserved_at,
  r.expires_at,
  r.status,
  r.book_id,
  r.user_id,
  b.id as book_id_check,
  b.title,
  b.author,
  b.shelf_id,
  s.shelf_number,
  p.full_name,
  p.email
FROM reservations r
JOIN books b ON r.book_id = b.id
LEFT JOIN shelves s ON b.shelf_id = s.id
JOIN profiles p ON r.user_id = p.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC;

-- Check issued books
SELECT '=== ALL ISSUED BOOKS (RAW) ===' as step;
SELECT 
  ib.id,
  ib.user_id,
  ib.book_id,
  ib.issued_at,
  ib.due_date,
  ib.returned_at
FROM issued_books ib
WHERE ib.returned_at IS NULL
ORDER BY ib.issued_at DESC;

-- Test if RLS is blocking
SELECT '=== TEST RLS POLICY ===' as step;
SELECT 
  CASE 
    WHEN get_user_role() IN ('librarian', 'admin') THEN '✅ You are a librarian/admin - RLS should allow access'
    ELSE '❌ You are NOT a librarian/admin - RLS will block access'
  END as rls_status;

-- Check if there are ANY policies blocking
SELECT '=== CURRENT POLICIES ===' as step;
SELECT 
  tablename,
  policyname,
  cmd,
  qual::text as using_clause
FROM pg_policies
WHERE tablename IN ('issued_books', 'reservations', 'profiles', 'books')
ORDER BY tablename, policyname;
