-- ============================================
-- COMPLETE NOTIFICATION SYSTEM
-- Sends notifications for ALL book activities
-- ============================================

-- Drop existing notification function and trigger
DROP TRIGGER IF EXISTS trigger_notify_shelf_alerts ON shelf_alerts;
DROP TRIGGER IF EXISTS trigger_notify_book_issued ON issued_books;
DROP TRIGGER IF EXISTS trigger_notify_book_reserved ON reservations;
DROP FUNCTION IF EXISTS notify_wrong_shelf_pickup() CASCADE;
DROP FUNCTION IF EXISTS notify_book_issued() CASCADE;
DROP FUNCTION IF EXISTS notify_book_reserved() CASCADE;

-- ============================================
-- 1. Notification for Shelf Alerts (Wrong Shelf, Unknown Object)
-- ============================================
CREATE OR REPLACE FUNCTION notify_wrong_shelf_pickup()
RETURNS TRIGGER AS $$
DECLARE
  student_id UUID;
  student_email TEXT;
  student_name TEXT;
  book_title TEXT;
  correct_shelf INT;
  librarian_record RECORD;
BEGIN
  RAISE NOTICE 'Shelf Alert Trigger: alert_type=%, shelf=%', NEW.alert_type, NEW.shelf_number;
  
  -- Process wrong_shelf alerts
  IF NEW.alert_type = 'wrong_shelf' AND NEW.book_id IS NOT NULL THEN
    
    -- Get student info from active reservation
    SELECT r.user_id, p.email, p.full_name, b.title, s.shelf_number
    INTO student_id, student_email, student_name, book_title, correct_shelf
    FROM reservations r
    JOIN profiles p ON p.id = r.user_id
    JOIN books b ON b.id = r.book_id
    JOIN shelves s ON s.id = b.shelf_id
    WHERE r.book_id = NEW.book_id
      AND r.status = 'active'
    ORDER BY r.reserved_at DESC
    LIMIT 1;

    IF student_id IS NOT NULL THEN
      -- Notify student about wrong shelf
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        student_id,
        'wrong_shelf',
        '⚠️ Wrong Shelf Pickup',
        'You picked up "' || book_title || '" from Shelf ' || NEW.shelf_number || 
        ', but it belongs on Shelf ' || correct_shelf || '. Please return it to the correct location.',
        jsonb_build_object(
          'correct_shelf', correct_shelf,
          'wrong_shelf', NEW.shelf_number,
          'book_id', NEW.book_id,
          'book_title', book_title,
          'alert_id', NEW.id
        )
      );
      
      RAISE NOTICE 'Created wrong_shelf notification for student: %', student_email;

      -- Notify ALL librarians about the mistake
      FOR librarian_record IN 
        SELECT id, email FROM profiles WHERE role = 'librarian'
      LOOP
        INSERT INTO notifications (user_id, type, title, message, metadata)
        VALUES (
          librarian_record.id,
          'wrong_shelf',
          '⚠️ Student Picked Wrong Shelf',
          'Student ' || COALESCE(student_name, student_email) || ' picked up "' || book_title || 
          '" from wrong shelf. Expected: Shelf ' || correct_shelf || 
          ', Actual: Shelf ' || NEW.shelf_number || '. Please assist.',
          jsonb_build_object(
            'student_email', student_email,
            'student_name', student_name,
            'student_id', student_id,
            'book_title', book_title,
            'correct_shelf', correct_shelf,
            'wrong_shelf', NEW.shelf_number,
            'book_id', NEW.book_id,
            'alert_id', NEW.id
          )
        );
      END LOOP;
      
      RAISE NOTICE 'Notified all librarians about wrong shelf';
    END IF;

  -- Process unknown_object alerts
  ELSIF NEW.alert_type = 'unknown_object' THEN
    
    -- Notify all librarians and admins
    FOR librarian_record IN 
      SELECT id, email FROM profiles WHERE role IN ('librarian', 'admin')
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'unknown_object',
        '❓ Unknown Object on Shelf',
        'Unknown object (' || NEW.detected_weight || 'g) detected on Shelf ' || 
        NEW.shelf_number || '. Please investigate immediately.',
        jsonb_build_object(
          'shelf_number', NEW.shelf_number,
          'weight', NEW.detected_weight,
          'alert_id', NEW.id
        )
      );
    END LOOP;
    
    RAISE NOTICE 'Notified librarians about unknown object on Shelf %', NEW.shelf_number;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 2. Notification for Book Pickup/Issuance
-- ============================================
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
    
    -- Get student info
    SELECT p.id, p.email, p.full_name
    INTO student_record
    FROM profiles p
    WHERE p.id = NEW.user_id;
    
    -- Get book and shelf info
    SELECT b.title, b.author, s.shelf_number
    INTO book_record
    FROM books b
    LEFT JOIN shelves s ON s.id = b.shelf_id
    WHERE b.id = NEW.book_id;
    
    shelf_number := COALESCE(book_record.shelf_number, 0);
    
    RAISE NOTICE 'Book Issued: % to % from Shelf %', book_record.title, student_record.email, shelf_number;
    
    -- Notify student about successful pickup
    INSERT INTO notifications (user_id, type, title, message, metadata)
    VALUES (
      NEW.user_id,
      'info',
      '✅ Book Issued Successfully',
      'You have successfully picked up "' || book_record.title || '" by ' || book_record.author || 
      ' from Shelf ' || shelf_number || '. Due date: ' || 
      TO_CHAR(NEW.due_date, 'Mon DD, YYYY') || '.',
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
    
    RAISE NOTICE 'Sent pickup confirmation to student: %', student_record.email;
    
    -- Notify ALL librarians about the book pickup
    FOR librarian_record IN 
      SELECT id, email FROM profiles WHERE role = 'librarian'
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'info',
        '📖 Book Picked Up',
        'Student ' || COALESCE(student_record.full_name, student_record.email) || 
        ' picked up "' || book_record.title || '" from Shelf ' || shelf_number || 
        '. Due: ' || TO_CHAR(NEW.due_date, 'Mon DD, YYYY') || '.',
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
    END LOOP;
    
    RAISE NOTICE 'Notified all librarians about book pickup';
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. Notification for Book Reservation
-- ============================================
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
    
    -- Get student info
    SELECT p.id, p.email, p.full_name
    INTO student_record
    FROM profiles p
    WHERE p.id = NEW.user_id;
    
    -- Get book and shelf info
    SELECT b.title, b.author, s.shelf_number
    INTO book_record
    FROM books b
    LEFT JOIN shelves s ON s.id = b.shelf_id
    WHERE b.id = NEW.book_id;
    
    shelf_number := COALESCE(book_record.shelf_number, 0);
    minutes_remaining := EXTRACT(EPOCH FROM (NEW.expires_at - NOW())) / 60;
    
    RAISE NOTICE 'Book Reserved: % by % from Shelf %', book_record.title, student_record.email, shelf_number;
    
    -- Notify student about successful reservation
    INSERT INTO notifications (user_id, type, title, message, metadata)
    VALUES (
      NEW.user_id,
      'info',
      '🎉 Book Reserved!',
      'You have reserved "' || book_record.title || '" from Shelf ' || shelf_number || 
      '. You have ' || minutes_remaining || ' minutes to pick it up. Please collect it before ' || 
      TO_CHAR(NEW.expires_at, 'HH24:MI') || '.',
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
    
    RAISE NOTICE 'Sent reservation confirmation to student: %', student_record.email;
    
    -- Notify ALL librarians about the reservation
    FOR librarian_record IN 
      SELECT id, email FROM profiles WHERE role = 'librarian'
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
        'info',
        '📅 New Reservation',
        'Student ' || COALESCE(student_record.full_name, student_record.email) || 
        ' reserved "' || book_record.title || '" from Shelf ' || shelf_number || 
        '. Expires at ' || TO_CHAR(NEW.expires_at, 'HH24:MI') || '.',
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
    END LOOP;
    
    RAISE NOTICE 'Notified all librarians about reservation';
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. Create Triggers
-- ============================================

-- Trigger for shelf alerts (wrong shelf, unknown object)
CREATE TRIGGER trigger_notify_shelf_alerts
  AFTER INSERT ON shelf_alerts
  FOR EACH ROW
  EXECUTE FUNCTION notify_wrong_shelf_pickup();

-- Trigger for book issuance (pickup)
CREATE TRIGGER trigger_notify_book_issued
  AFTER INSERT ON issued_books
  FOR EACH ROW
  EXECUTE FUNCTION notify_book_issued();

-- Trigger for book reservation
CREATE TRIGGER trigger_notify_book_reserved
  AFTER INSERT ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION notify_book_reserved();

-- ============================================
-- 5. Verification
-- ============================================
SELECT 
  '✅ Complete notification system installed!' as status,
  'Notifications will be sent for:' as info;

SELECT 
  '  • Book reservations (student + librarian)' as feature
UNION ALL SELECT '  • Book pickups (student + librarian)'
UNION ALL SELECT '  • Wrong shelf alerts (student + librarian)'
UNION ALL SELECT '  • Unknown objects (librarian only)';

-- Check triggers
SELECT 
  trigger_name,
  event_object_table as table_name,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_name LIKE 'trigger_notify%'
ORDER BY event_object_table;
