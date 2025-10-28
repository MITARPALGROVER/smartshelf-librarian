-- Migration: Auto-expire reservations
-- This migration adds automatic expiration for reservations that have passed their expiry time

-- Function to expire old reservations and free up books
CREATE OR REPLACE FUNCTION public.expire_old_reservations()
RETURNS void
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update expired reservations
  UPDATE public.reservations
  SET status = 'expired'
  WHERE status = 'active'
    AND expires_at < NOW();

  -- Update books back to available if their reservations expired
  UPDATE public.books
  SET status = 'available'
  WHERE status = 'reserved'
    AND id IN (
      SELECT book_id
      FROM public.reservations
      WHERE status = 'expired'
        AND expires_at < NOW()
    );
END;
$$;

-- Create a trigger to automatically expire reservations when checking
-- This runs before any SELECT on reservations table
CREATE OR REPLACE FUNCTION public.check_and_expire_reservations()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Expire any reservations that have passed their expiry time
  UPDATE public.reservations
  SET status = 'expired',
      updated_at = NOW()
  WHERE status = 'active'
    AND expires_at < NOW();
  
  -- Update books back to available if their reservations expired
  UPDATE public.books b
  SET status = 'available',
      updated_at = NOW()
  WHERE status = 'reserved'
    AND NOT EXISTS (
      SELECT 1
      FROM public.reservations r
      WHERE r.book_id = b.id
        AND r.status = 'active'
        AND r.expires_at >= NOW()
    );
  
  RETURN NEW;
END;
$$;

-- Create trigger that runs before insert to clean up expired reservations
CREATE OR REPLACE TRIGGER before_reservation_insert_expire_old
  BEFORE INSERT ON public.reservations
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.check_and_expire_reservations();

-- Manually run the expiration function once to clean up existing data
SELECT public.expire_old_reservations();

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.expire_old_reservations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_expire_reservations() TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION public.expire_old_reservations() IS 
'Expires all reservations that have passed their expiry time and frees up the associated books';

COMMENT ON FUNCTION public.check_and_expire_reservations() IS 
'Trigger function that automatically expires old reservations before new reservations are created';
