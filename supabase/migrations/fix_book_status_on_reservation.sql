-- FIX: Update book status to 'reserved' when a reservation is created
-- This was missing and causing the pickup detection to fail

-- Create function to update book status on reservation
CREATE OR REPLACE FUNCTION update_book_status_on_reservation()
RETURNS TRIGGER AS $$
BEGIN
  -- When reservation is created and active, mark book as reserved
  IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
    UPDATE books
    SET status = 'reserved'
    WHERE id = NEW.book_id;
    
    RAISE NOTICE '✅ Book % marked as RESERVED', NEW.book_id;
  END IF;
  
  -- When reservation expires or is cancelled, mark book as available
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status IN ('expired', 'cancelled') THEN
    UPDATE books
    SET status = 'available'
    WHERE id = NEW.book_id;
    
    RAISE NOTICE '✅ Book % marked as AVAILABLE (reservation %)', NEW.book_id, NEW.status;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS trigger_update_book_status_on_reservation ON reservations;

-- Create trigger that runs AFTER insert/update on reservations
CREATE TRIGGER trigger_update_book_status_on_reservation
  AFTER INSERT OR UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION update_book_status_on_reservation();

-- Fix existing active reservations (update their book status)
UPDATE books b
SET status = 'reserved'
FROM reservations r
WHERE r.book_id = b.id
  AND r.status = 'active'
  AND b.status = 'available';

-- Verify the fix
SELECT 
  '=== VERIFICATION ===' as step,
  'Checking if existing reservation now has book marked as reserved' as info;

SELECT 
  r.id as reservation_id,
  b.id as book_id,
  b.title,
  b.status as book_status,
  r.status as reservation_status,
  CASE 
    WHEN b.status = 'reserved' THEN '✅ FIXED!'
    ELSE '❌ Still broken'
  END as status_check
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE r.status = 'active'
ORDER BY r.reserved_at DESC
LIMIT 5;
