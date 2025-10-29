-- ============================================
-- ALL-IN-ONE COMPLETE SETUP
-- Run this to set up EVERYTHING at once
-- ============================================

-- ============================================
-- PART 1: Fix shelf_alerts table structure
-- ============================================
ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS shelf_number INTEGER;

ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS book_id UUID REFERENCES public.books(id) ON DELETE SET NULL;

ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS detected_weight DECIMAL(8,2);

-- Update shelf_number from shelf_id for existing records
UPDATE public.shelf_alerts sa
SET shelf_number = s.shelf_number
FROM public.shelves s
WHERE sa.shelf_id = s.id
  AND sa.shelf_number IS NULL;

-- ============================================
-- PART 2: Enable Realtime
-- ============================================
DO $$ 
BEGIN
  -- Add tables to realtime publication (ignore if already exists)
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE reservations;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE issued_books;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE books;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;

-- ============================================
-- PART 3: Expiry Functions
-- ============================================
CREATE OR REPLACE FUNCTION expire_old_reservations()
RETURNS void AS $$
DECLARE
  expired_count INT;
BEGIN
  -- Mark expired reservations
  WITH expired AS (
    UPDATE reservations
    SET status = 'expired'
    WHERE status = 'active'
      AND expires_at < NOW()
    RETURNING id, book_id, user_id
  )
  SELECT COUNT(*) INTO expired_count FROM expired;
  
  -- Update book status back to available for expired reservations
  UPDATE books
  SET status = 'available'
  WHERE id IN (
    SELECT book_id 
    FROM reservations 
    WHERE status = 'expired'
      AND book_id NOT IN (
        SELECT book_id 
        FROM issued_books 
        WHERE returned_at IS NULL
      )
  );
  
  IF expired_count > 0 THEN
    RAISE NOTICE 'Expired % reservations', expired_count;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_expired_reservations()
RETURNS void AS $$
DECLARE
  expired_record RECORD;
  librarian_record RECORD;
BEGIN
  -- Find reservations that just expired
  FOR expired_record IN
    SELECT 
      r.id,
      r.user_id,
      r.book_id,
      r.expires_at,
      b.title as book_title,
      p.email as student_email,
      p.full_name as student_name
    FROM reservations r
    JOIN books b ON b.id = r.book_id
    JOIN profiles p ON p.id = r.user_id
    WHERE r.status = 'active'
      AND r.expires_at < NOW()
  LOOP
    -- Notify student
    INSERT INTO notifications (user_id, type, title, message, metadata)
    VALUES (
      expired_record.user_id,
      'expired_reservation',
      '⏰ Reservation Expired',
      format('Your reservation for "%s" has expired. Please reserve again if still needed.', 
        expired_record.book_title),
      jsonb_build_object(
        'book_id', expired_record.book_id,
        'book_title', expired_record.book_title,
        'expired_at', expired_record.expires_at,
        'reservation_id', expired_record.id
      )
    );
    
    -- Notify librarians
    FOR librarian_record IN 
      SELECT DISTINCT p.id, p.email 
      FROM profiles p
      JOIN user_roles ur ON ur.user_id = p.id
      WHERE ur.role = 'librarian'
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'expired_reservation',
        '⏰ Reservation Expired',
        format('Student %s reservation for "%s" expired at %s.', 
          COALESCE(expired_record.student_name, expired_record.student_email),
          expired_record.book_title,
          TO_CHAR(expired_record.expires_at, 'HH24:MI:SS')),
        jsonb_build_object(
          'student_email', expired_record.student_email,
          'student_name', expired_record.student_name,
          'book_id', expired_record.book_id,
          'book_title', expired_record.book_title,
          'expired_at', expired_record.expires_at,
          'reservation_id', expired_record.id
        )
      );
    END LOOP;
    
    -- Mark reservation as expired
    UPDATE reservations
    SET status = 'expired'
    WHERE id = expired_record.id;
    
    -- Update book status back to available
    UPDATE books
    SET status = 'available'
    WHERE id = expired_record.book_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PART 4: Notification Triggers
-- ============================================

-- Drop existing triggers
DROP TRIGGER IF EXISTS trigger_notify_shelf_alerts ON shelf_alerts;
DROP TRIGGER IF EXISTS trigger_notify_book_issued ON issued_books;
DROP TRIGGER IF EXISTS trigger_notify_book_reserved ON reservations;

-- Function for book reservation notifications
CREATE OR REPLACE FUNCTION notify_book_reserved()
RETURNS TRIGGER AS $$
DECLARE
  student_record RECORD;
  book_record RECORD;
  shelf_number INT;
  librarian_record RECORD;
  minutes_remaining INT;
BEGIN
  -- Only notify on INSERT (new reservation)
  IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
    
    RAISE NOTICE '📚 NEW RESERVATION DETECTED - Starting notification process';
    
    -- Get student info
    SELECT p.id, p.email, p.full_name
    INTO student_record
    FROM profiles p
    WHERE p.id = NEW.user_id;
    
    RAISE NOTICE 'Student found: %', student_record.email;
    
    -- Get book and shelf info
    SELECT b.title, b.author, s.shelf_number
    INTO book_record
    FROM books b
    LEFT JOIN shelves s ON s.id = b.shelf_id
    WHERE b.id = NEW.book_id;
    
    shelf_number := COALESCE(book_record.shelf_number, 0);
    minutes_remaining := EXTRACT(EPOCH FROM (NEW.expires_at - NOW())) / 60;
    
    RAISE NOTICE 'Book: % from Shelf %', book_record.title, shelf_number;
    
    -- Notify student about successful reservation
    INSERT INTO notifications (user_id, type, title, message, metadata)
    VALUES (
      NEW.user_id,
      'info',
      '🎉 Book Reserved!',
      format('You have reserved "%s" from Shelf %s. You have %s minutes to pick it up. Please collect it before %s.',
        book_record.title, 
        shelf_number,
        minutes_remaining::text,
        TO_CHAR(NEW.expires_at, 'HH24:MI')),
      jsonb_build_object(
        'book_id', NEW.book_id,
        'book_title', book_record.title,
        'book_author', book_record.author,
        'shelf_number', shelf_number,
        'reserved_at', NEW.reserved_at,
        'expires_at', NEW.expires_at,
        'reservation_id', NEW.id
      )
    );
    
    RAISE NOTICE '✅ Sent reservation confirmation to student: %', student_record.email;
    
    -- Notify ALL librarians about the reservation
    FOR librarian_record IN 
      SELECT DISTINCT p.id, p.email 
      FROM profiles p
      JOIN user_roles ur ON ur.user_id = p.id
      WHERE ur.role = 'librarian'
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'info',
        '📅 New Reservation',
        format('Student %s reserved "%s" from Shelf %s. Expires at %s.',
          COALESCE(student_record.full_name, student_record.email),
          book_record.title,
          shelf_number,
          TO_CHAR(NEW.expires_at, 'HH24:MI')),
        jsonb_build_object(
          'student_email', student_record.email,
          'student_name', student_record.full_name,
          'student_id', NEW.user_id,
          'book_id', NEW.book_id,
          'book_title', book_record.title,
          'book_author', book_record.author,
          'shelf_number', shelf_number,
          'reserved_at', NEW.reserved_at,
          'expires_at', NEW.expires_at,
          'reservation_id', NEW.id
        )
      );
      RAISE NOTICE '✅ Notified librarian: %', librarian_record.email;
    END LOOP;
    
    RAISE NOTICE '🎉 RESERVATION NOTIFICATION COMPLETE';
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function for book issuance notifications
CREATE OR REPLACE FUNCTION notify_book_issued()
RETURNS TRIGGER AS $$
DECLARE
  student_record RECORD;
  book_record RECORD;
  shelf_number INT;
  librarian_record RECORD;
BEGIN
  -- Only notify on INSERT (new book issued)
  IF TG_OP = 'INSERT' THEN
    
    RAISE NOTICE '📖 BOOK PICKUP DETECTED - Starting notification process';
    
    -- Get student info
    SELECT p.id, p.email, p.full_name
    INTO student_record
    FROM profiles p
    WHERE p.id = NEW.user_id;
    
    RAISE NOTICE 'Student found: %', student_record.email;
    
    -- Get book and shelf info
    SELECT b.title, b.author, s.shelf_number
    INTO book_record
    FROM books b
    LEFT JOIN shelves s ON s.id = b.shelf_id
    WHERE b.id = NEW.book_id;
    
    shelf_number := COALESCE(book_record.shelf_number, 0);
    
    RAISE NOTICE 'Book: % from Shelf %', book_record.title, shelf_number;
    
    -- Notify student about successful pickup
    INSERT INTO notifications (user_id, type, title, message, metadata)
    VALUES (
      NEW.user_id,
      'info',
      '✅ Book Issued Successfully',
      format('You have successfully picked up "%s" by %s from Shelf %s. Due date: %s.',
        book_record.title,
        book_record.author,
        shelf_number,
        TO_CHAR(NEW.due_date, 'Mon DD, YYYY')),
      jsonb_build_object(
        'book_id', NEW.book_id,
        'book_title', book_record.title,
        'book_author', book_record.author,
        'shelf_number', shelf_number,
        'issued_at', NEW.issued_at,
        'due_date', NEW.due_date,
        'issued_book_id', NEW.id
      )
    );
    
    RAISE NOTICE '✅ Sent pickup confirmation to student: %', student_record.email;
    
    -- Notify ALL librarians about the book pickup
    FOR librarian_record IN 
      SELECT DISTINCT p.id, p.email 
      FROM profiles p
      JOIN user_roles ur ON ur.user_id = p.id
      WHERE ur.role = 'librarian'
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'info',
        '📖 Book Picked Up',
        format('Student %s picked up "%s" from Shelf %s. Due: %s.',
          COALESCE(student_record.full_name, student_record.email),
          book_record.title,
          shelf_number,
          TO_CHAR(NEW.due_date, 'Mon DD, YYYY')),
        jsonb_build_object(
          'student_email', student_record.email,
          'student_name', student_record.full_name,
          'student_id', NEW.user_id,
          'book_id', NEW.book_id,
          'book_title', book_record.title,
          'book_author', book_record.author,
          'shelf_number', shelf_number,
          'issued_at', NEW.issued_at,
          'due_date', NEW.due_date,
          'issued_book_id', NEW.id
        )
      );
      RAISE NOTICE '✅ Notified librarian: %', librarian_record.email;
    END LOOP;
    
    RAISE NOTICE '🎉 PICKUP NOTIFICATION COMPLETE';
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create triggers
CREATE TRIGGER trigger_notify_book_reserved
  AFTER INSERT ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION notify_book_reserved();

CREATE TRIGGER trigger_notify_book_issued
  AFTER INSERT ON issued_books
  FOR EACH ROW
  EXECUTE FUNCTION notify_book_issued();

-- ============================================
-- PART 5: Weight Detection with Expiry Validation
-- ============================================
DROP TRIGGER IF EXISTS on_shelf_weight_change ON shelves;

CREATE OR REPLACE FUNCTION detect_book_from_weight_change()
RETURNS TRIGGER AS $$
DECLARE
  weight_diff DECIMAL(8,2);
  weight_increased BOOLEAN;
  matching_book_id UUID;
  matching_book_title TEXT;
  matching_book_status TEXT;
  active_reservation_id UUID;
  reservation_user_id UUID;
  reservation_expires_at TIMESTAMPTZ;
  reservation_is_expired BOOLEAN;
BEGIN
  -- Calculate weight difference
  weight_diff := ABS(NEW.current_weight - OLD.current_weight);
  weight_increased := NEW.current_weight > OLD.current_weight;
  
  -- Only process significant weight changes
  IF weight_diff > 10 THEN
    
    RAISE NOTICE '⚖️ Weight change detected on Shelf %: %g (increased: %)', 
      NEW.shelf_number, weight_diff, weight_increased;
  
    IF NOT weight_increased THEN
      -- Book removed (pickup)
      SELECT b.id, b.title, b.status
      INTO matching_book_id, matching_book_title, matching_book_status
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('available', 'reserved')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'reserved' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
      
      IF matching_book_id IS NOT NULL AND matching_book_status = 'reserved' THEN
        RAISE NOTICE '📖 Found reserved book: %', matching_book_title;
        
        -- Check for active reservation
        SELECT 
          r.id, 
          r.user_id, 
          r.expires_at,
          (r.expires_at < NOW()) as is_expired
        INTO 
          active_reservation_id, 
          reservation_user_id, 
          reservation_expires_at,
          reservation_is_expired
        FROM reservations r
        WHERE r.book_id = matching_book_id
          AND r.status = 'active'
        ORDER BY r.reserved_at DESC
        LIMIT 1;
        
        IF active_reservation_id IS NOT NULL THEN
          IF NOT reservation_is_expired THEN
            -- ✅ VALID RESERVATION - Issue the book!
            RAISE NOTICE '✅ Valid reservation - Issuing book to user %', reservation_user_id;
            
            -- Mark reservation as completed
            UPDATE reservations
            SET status = 'completed'
            WHERE id = active_reservation_id;
            
            -- Create issued_books record
            INSERT INTO issued_books (book_id, user_id, issued_at, due_date)
            VALUES (
              matching_book_id,
              reservation_user_id,
              NOW(),
              NOW() + INTERVAL '14 days'
            );
            
            -- Update book status to issued
            UPDATE books
            SET status = 'issued'
            WHERE id = matching_book_id;
            
            RAISE NOTICE '✅ Book issued successfully!';
          ELSE
            RAISE NOTICE '❌ Reservation expired - pickup denied';
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_shelf_weight_change
  AFTER UPDATE OF current_weight ON shelves
  FOR EACH ROW
  WHEN (OLD.current_weight IS DISTINCT FROM NEW.current_weight)
  EXECUTE FUNCTION detect_book_from_weight_change();

-- ============================================
-- PART 6: Verification
-- ============================================
SELECT '✅ ALL-IN-ONE SETUP COMPLETE!' as status;

-- Show installed triggers
SELECT 
  trigger_name,
  event_object_table as on_table,
  action_timing || ' ' || event_manipulation as fires_on
FROM information_schema.triggers
WHERE trigger_name IN ('trigger_notify_book_reserved', 'trigger_notify_book_issued', 'on_shelf_weight_change')
ORDER BY event_object_table;

-- Show realtime tables
SELECT 
  'Realtime enabled on: ' || string_agg(tablename, ', ') as realtime_status
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('notifications', 'reservations', 'issued_books', 'books');
