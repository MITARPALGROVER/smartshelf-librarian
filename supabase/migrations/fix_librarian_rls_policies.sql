-- Debug: Check RLS policies and data access for librarian

-- Check current user's role
SELECT '=== CURRENT USER INFO ===' as step;
SELECT 
  u.id,
  u.email,
  u.raw_user_meta_data->>'role' as role,
  p.full_name
FROM auth.users u
LEFT JOIN profiles p ON u.id = p.id
WHERE u.email = 'phoenix.xd2925@gmail.com'; -- Replace with actual librarian email

-- Check RLS policies on issued_books
SELECT '=== ISSUED_BOOKS RLS POLICIES ===' as step;
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'issued_books';

-- Check RLS policies on reservations
SELECT '=== RESERVATIONS RLS POLICIES ===' as step;
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'reservations';

-- Check if there's actual data
SELECT '=== ALL ISSUED BOOKS (no RLS) ===' as step;
SELECT COUNT(*) as total_issued_books
FROM issued_books
WHERE returned_at IS NULL;

SELECT '=== ALL ACTIVE RESERVATIONS (no RLS) ===' as step;
SELECT COUNT(*) as total_active_reservations
FROM reservations
WHERE status = 'active';

-- Create/Update RLS policies to allow librarians to see all data
SELECT '=== FIXING RLS POLICIES ===' as step;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Librarians can view all issued books" ON issued_books;
DROP POLICY IF EXISTS "Librarians can view all reservations" ON reservations;
DROP POLICY IF EXISTS "Librarians can update issued books" ON issued_books;
DROP POLICY IF EXISTS "Librarians can update reservations" ON reservations;

-- Allow librarians to SELECT all issued_books
CREATE POLICY "Librarians can view all issued books"
  ON issued_books
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR auth.uid() = user_id  -- Users can see their own
  );

-- Allow librarians to UPDATE issued_books (for marking returned)
CREATE POLICY "Librarians can update issued books"
  ON issued_books
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

-- Allow librarians to SELECT all reservations
CREATE POLICY "Librarians can view all reservations"
  ON reservations
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR auth.uid() = user_id  -- Users can see their own
  );

-- Allow librarians to UPDATE reservations (for cancelling)
CREATE POLICY "Librarians can update reservations"
  ON reservations
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

SELECT '✅ RLS Policies updated!' as status;
SELECT 'Librarians can now view and manage all issued books and reservations' as info;
