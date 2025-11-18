-- Complete RLS fix for Librarian Dashboard
-- This ensures librarians can access all necessary tables

-- First, check what tables are involved
SELECT '=== TABLES WITH RLS ENABLED ===' as step;
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('issued_books', 'reservations', 'books', 'profiles', 'shelves');

-- Check existing policies
SELECT '=== ALL CURRENT POLICIES ===' as step;
SELECT 
  tablename,
  policyname,
  cmd,
  roles
FROM pg_policies
WHERE tablename IN ('issued_books', 'reservations', 'books', 'profiles')
ORDER BY tablename, policyname;

-- DROP ALL existing librarian-related policies
DROP POLICY IF EXISTS "Librarians can view all issued books" ON issued_books;
DROP POLICY IF EXISTS "Librarians can view all reservations" ON reservations;
DROP POLICY IF EXISTS "Librarians can update issued books" ON issued_books;
DROP POLICY IF EXISTS "Librarians can update reservations" ON reservations;
DROP POLICY IF EXISTS "Librarians can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Librarians can view all books" ON books;

-- ISSUED_BOOKS: Allow librarians to SELECT
CREATE POLICY "Librarians can view all issued books"
  ON issued_books
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR auth.uid() = user_id
  );

-- ISSUED_BOOKS: Allow librarians to UPDATE (for marking returned)
CREATE POLICY "Librarians can update issued books"
  ON issued_books
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  )
  WITH CHECK (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

-- RESERVATIONS: Allow librarians to SELECT
CREATE POLICY "Librarians can view all reservations"
  ON reservations
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR auth.uid() = user_id
  );

-- RESERVATIONS: Allow librarians to UPDATE (for cancelling)
CREATE POLICY "Librarians can update reservations"
  ON reservations
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  )
  WITH CHECK (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

-- PROFILES: Allow librarians to view all profiles (needed for joins)
CREATE POLICY "Librarians can view all profiles"
  ON profiles
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR auth.uid() = id
  );

-- BOOKS: Allow librarians to view all books (needed for joins)
CREATE POLICY "Librarians can view all books"
  ON books
  FOR SELECT
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
    OR status = 'available'  -- Everyone can see available books
  );

-- BOOKS: Allow librarians to update books (for status changes)
CREATE POLICY "Librarians can update books"
  ON books
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  )
  WITH CHECK (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

-- Verify the user's role
SELECT '=== VERIFY YOUR ROLE ===' as step;
SELECT 
  email,
  raw_user_meta_data->>'role' as role,
  CASE 
    WHEN raw_user_meta_data->>'role' IN ('librarian', 'admin') THEN '✅ Can access librarian dashboard'
    ELSE '❌ Not a librarian/admin'
  END as access_status
FROM auth.users
WHERE email = 'phoenix.xd2925@gmail.com';

SELECT '✅ RLS Policies created!' as status;
SELECT 'Now librarians can view all issued books, reservations, profiles, and books' as info;
SELECT 'Refresh your Librarian Dashboard now!' as action;
