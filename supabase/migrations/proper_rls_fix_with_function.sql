-- PROPER FIX: Create a function to check user role and use it in RLS policies
-- This avoids the "permission denied for table users" error

-- Create a function to get current user's role
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN (
    SELECT raw_user_meta_data->>'role'
    FROM auth.users
    WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_user_role() TO authenticated;

-- Now DROP and recreate all policies using this function

-- ISSUED_BOOKS policies
DROP POLICY IF EXISTS "Librarians can view all issued books" ON issued_books;
DROP POLICY IF EXISTS "Librarians can update issued books" ON issued_books;
DROP POLICY IF EXISTS "Users can view own issued books" ON issued_books;

CREATE POLICY "Librarians can view all issued books"
  ON issued_books
  FOR SELECT
  TO authenticated
  USING (
    get_user_role() IN ('librarian', 'admin')
    OR auth.uid() = user_id
  );

CREATE POLICY "Librarians can update issued books"
  ON issued_books
  FOR UPDATE
  TO authenticated
  USING (get_user_role() IN ('librarian', 'admin'))
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- RESERVATIONS policies
DROP POLICY IF EXISTS "Librarians can view all reservations" ON reservations;
DROP POLICY IF EXISTS "Librarians can update reservations" ON reservations;
DROP POLICY IF EXISTS "Users can view own reservations" ON reservations;

CREATE POLICY "Librarians can view all reservations"
  ON reservations
  FOR SELECT
  TO authenticated
  USING (
    get_user_role() IN ('librarian', 'admin')
    OR auth.uid() = user_id
  );

CREATE POLICY "Librarians can update reservations"
  ON reservations
  FOR UPDATE
  TO authenticated
  USING (get_user_role() IN ('librarian', 'admin'))
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- PROFILES policies
DROP POLICY IF EXISTS "Librarians can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;

CREATE POLICY "Librarians can view all profiles"
  ON profiles
  FOR SELECT
  TO authenticated
  USING (
    get_user_role() IN ('librarian', 'admin')
    OR auth.uid() = id
  );

-- BOOKS policies  
DROP POLICY IF EXISTS "Librarians can view all books" ON books;
DROP POLICY IF EXISTS "Librarians can update books" ON books;
DROP POLICY IF EXISTS "Public can view available books" ON books;
DROP POLICY IF EXISTS "Everyone can view books" ON books;

CREATE POLICY "Everyone can view books"
  ON books
  FOR SELECT
  TO authenticated
  USING (true);  -- Everyone can see all books

CREATE POLICY "Librarians can update books"
  ON books
  FOR UPDATE
  TO authenticated
  USING (get_user_role() IN ('librarian', 'admin'))
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- Test the function
SELECT '=== TEST USER ROLE FUNCTION ===' as step;
SELECT 
  'Your role is: ' || COALESCE(get_user_role(), 'NOT SET') as role_check;

SELECT '✅ PROPER FIX APPLIED!' as status;
SELECT 'Using SECURITY DEFINER function to check roles' as method;
SELECT 'Refresh Librarian Dashboard now!' as action;
