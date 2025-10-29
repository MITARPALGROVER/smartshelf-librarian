-- ============================================
-- COMPLETE SYSTEM DIAGNOSIS
-- Check if everything is set up correctly
-- ============================================

-- 1. Check if triggers exist
SELECT 
  'TRIGGERS' as check_type,
  trigger_name,
  event_object_table as table_name,
  action_timing || ' ' || event_manipulation as when_fired
FROM information_schema.triggers
WHERE trigger_name LIKE 'trigger_notify%'
   OR trigger_name LIKE 'on_shelf%'
ORDER BY event_object_table;

-- 2. Check if functions exist
SELECT 
  'FUNCTIONS' as check_type,
  routine_name as function_name,
  routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND (routine_name LIKE 'notify%' 
    OR routine_name LIKE 'expire%'
    OR routine_name LIKE 'detect%')
ORDER BY routine_name;

-- 3. Check if Realtime is enabled
SELECT 
  'REALTIME' as check_type,
  tablename,
  'Enabled' as status
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('notifications', 'reservations', 'issued_books', 'books');

-- 4. Check table structure
SELECT 
  'SHELF_ALERTS_COLUMNS' as check_type,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'shelf_alerts'
ORDER BY ordinal_position;

-- 5. Check recent notifications
SELECT 
  'RECENT_NOTIFICATIONS' as check_type,
  created_at,
  type,
  title,
  user_id
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

-- 6. Check recent reservations
SELECT 
  'RECENT_RESERVATIONS' as check_type,
  r.reserved_at,
  r.status,
  r.expires_at,
  b.title as book_title,
  p.email as student_email
FROM reservations r
JOIN books b ON b.id = r.book_id
JOIN profiles p ON p.id = r.user_id
ORDER BY r.reserved_at DESC
LIMIT 5;

-- 7. Check recent issued books
SELECT 
  'RECENT_ISSUED_BOOKS' as check_type,
  ib.issued_at,
  b.title as book_title,
  p.email as student_email,
  ib.returned_at
FROM issued_books ib
JOIN books b ON b.id = ib.book_id
JOIN profiles p ON p.id = ib.user_id
ORDER BY ib.issued_at DESC
LIMIT 5;

-- 8. Check user roles
SELECT 
  'USER_ROLES' as check_type,
  p.email,
  ur.role
FROM profiles p
JOIN user_roles ur ON ur.user_id = p.id
ORDER BY ur.role, p.email;

-- 9. Test notification trigger manually
DO $$
DECLARE
  test_user_id UUID;
  test_book_id UUID;
  test_reservation_id UUID;
BEGIN
  -- Get a test user (student)
  SELECT id INTO test_user_id 
  FROM auth.users 
  LIMIT 1;
  
  -- Get an available book
  SELECT id INTO test_book_id
  FROM books
  WHERE status = 'available'
  LIMIT 1;
  
  IF test_user_id IS NOT NULL AND test_book_id IS NOT NULL THEN
    RAISE NOTICE 'Found test user: % and book: %', test_user_id, test_book_id;
    RAISE NOTICE 'Triggers should fire automatically when you reserve a book';
    RAISE NOTICE 'Try reserving book ID: % as user: %', test_book_id, test_user_id;
  ELSE
    RAISE NOTICE 'No test data available. Create a user and book first.';
  END IF;
END $$;

-- 10. Summary
SELECT 
  '====== DIAGNOSIS COMPLETE ======' as status,
  'Check the results above to see what is missing' as next_step;
