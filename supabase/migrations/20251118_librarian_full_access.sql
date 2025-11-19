-- Grant librarians full access to manage books and shelves
-- This allows librarians to add/edit/delete books and update shelf IP addresses

-- Enable get_user_role function if not exists
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- BOOKS TABLE - Full librarian access
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "librarian_read_books" ON books;
DROP POLICY IF EXISTS "librarian_insert_books" ON books;
DROP POLICY IF EXISTS "librarian_update_books" ON books;
DROP POLICY IF EXISTS "librarian_delete_books" ON books;

-- Allow librarians to read all books
CREATE POLICY "librarian_read_books"
  ON books FOR SELECT
  USING (
    get_user_role() IN ('librarian', 'admin') OR
    true  -- Everyone can read books
  );

-- Allow librarians to insert books
CREATE POLICY "librarian_insert_books"
  ON books FOR INSERT
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- Allow librarians to update books
CREATE POLICY "librarian_update_books"
  ON books FOR UPDATE
  USING (get_user_role() IN ('librarian', 'admin'))
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- Allow librarians to delete books
CREATE POLICY "librarian_delete_books"
  ON books FOR DELETE
  USING (get_user_role() IN ('librarian', 'admin'));

-- ============================================
-- SHELVES TABLE - Full librarian access
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "librarian_read_shelves" ON shelves;
DROP POLICY IF EXISTS "librarian_insert_shelves" ON shelves;
DROP POLICY IF EXISTS "librarian_update_shelves" ON shelves;
DROP POLICY IF EXISTS "librarian_delete_shelves" ON shelves;

-- Allow librarians to read all shelves
CREATE POLICY "librarian_read_shelves"
  ON shelves FOR SELECT
  USING (
    get_user_role() IN ('librarian', 'admin') OR
    true  -- Everyone can read shelves
  );

-- Allow librarians to insert shelves
CREATE POLICY "librarian_insert_shelves"
  ON shelves FOR INSERT
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- Allow librarians to update shelves (including IP addresses)
CREATE POLICY "librarian_update_shelves"
  ON shelves FOR UPDATE
  USING (get_user_role() IN ('librarian', 'admin'))
  WITH CHECK (get_user_role() IN ('librarian', 'admin'));

-- Allow librarians to delete shelves
CREATE POLICY "librarian_delete_shelves"
  ON shelves FOR DELETE
  USING (get_user_role() IN ('librarian', 'admin'));

-- ============================================
-- Verification query
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '✅ Librarian permissions updated successfully!';
  RAISE NOTICE 'Librarians can now:';
  RAISE NOTICE '  - Add, edit, and delete books';
  RAISE NOTICE '  - Manage shelf configurations';
  RAISE NOTICE '  - Update ESP8266 IP addresses';
END $$;
