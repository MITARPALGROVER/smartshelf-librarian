-- Check and fix the reservation trigger

-- Check if trigger exists
SELECT '=== CHECK RESERVATION TRIGGER ===' as step;
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'trigger_update_book_status_on_reservation';

-- Check the function
SELECT '=== CHECK FUNCTION ===' as step;
SELECT 
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_name = 'update_book_status_on_reservation';

-- If it doesn't exist or isn't working, let's reinstall it
DROP TRIGGER IF EXISTS trigger_update_book_status_on_reservation ON reservations;
DROP FUNCTION IF EXISTS update_book_status_on_reservation() CASCADE;

CREATE OR REPLACE FUNCTION update_book_status_on_reservation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE NOTICE '🔔 Reservation trigger fired! TG_OP: %, reservation_id: %, book_id: %', TG_OP, NEW.id, NEW.book_id;
  
  -- When reservation is created and active, mark book as reserved
  IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
    RAISE NOTICE '📚 Setting book % to RESERVED', NEW.book_id;
    UPDATE books
    SET status = 'reserved'
    WHERE id = NEW.book_id;
  END IF;
  
  -- When reservation expires or is cancelled, mark book as available
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status IN ('expired', 'cancelled') THEN
    RAISE NOTICE '📚 Setting book % to AVAILABLE (reservation %)', NEW.book_id, NEW.status;
    UPDATE books
    SET status = 'available'
    WHERE id = NEW.book_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_update_book_status_on_reservation
  AFTER INSERT OR UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION update_book_status_on_reservation();

SELECT '✅ Reservation trigger reinstalled!' as status;

-- Now fix the current reservation's book status
UPDATE books b
SET status = 'reserved'
FROM reservations r
WHERE r.book_id = b.id
  AND r.status = 'active'
  AND b.status != 'reserved';

SELECT '✅ Fixed existing active reservations!' as fix_status;

-- Verify
SELECT 
  b.title,
  b.status as book_status,
  r.status as reservation_status
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE r.status = 'active';
