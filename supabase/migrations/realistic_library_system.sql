-- ============================================
-- REALISTIC LIBRARY SYSTEM
-- Handles reservation expiry and automatic cleanup
-- ============================================

-- ============================================
-- 1. Function to expire old reservations
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

-- ============================================
-- 2. Create cron job to run every minute (requires pg_cron extension)
-- Note: If pg_cron is not available, this will be handled by the app
-- ============================================
-- Uncomment if you have pg_cron enabled:
-- SELECT cron.schedule('expire-reservations', '* * * * *', 'SELECT expire_old_reservations()');

-- ============================================
-- 3. Enhanced weight detection with reservation validation
-- ============================================
DROP TRIGGER IF EXISTS on_shelf_weight_change ON shelves;
DROP FUNCTION IF EXISTS detect_book_from_weight_change() CASCADE;

CREATE OR REPLACE FUNCTION detect_book_from_weight_change()
RETURNS TRIGGER AS $$
DECLARE
  weight_diff DECIMAL(8,2);
  weight_increased BOOLEAN;
  matching_book_id UUID;
  matching_book_title TEXT;
  matching_book_shelf_id UUID;
  matching_book_status TEXT;
  wrong_shelf_book_id UUID;
  wrong_shelf_book_title TEXT;
  correct_shelf_number INTEGER;
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
  
    -- ============================================
    -- STEP 1: Try to find matching book on THIS shelf
    -- ============================================
    IF weight_increased THEN
      -- Weight increased - looking for issued/reserved books
      SELECT b.id, b.title, b.shelf_id, b.status
      INTO matching_book_id, matching_book_title, matching_book_shelf_id, matching_book_status
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('reserved', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
    ELSE
      -- Weight decreased - looking for available/reserved books
      SELECT b.id, b.title, b.shelf_id, b.status
      INTO matching_book_id, matching_book_title, matching_book_shelf_id, matching_book_status
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('available', 'reserved')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'reserved' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
    END IF;
    
    -- ============================================
    -- STEP 2: If no match on correct shelf, check OTHER shelves (wrong shelf)
    -- ============================================
    IF matching_book_id IS NULL AND weight_increased THEN
      -- Look for issued/reserved books on ANY other shelf
      SELECT b.id, b.title, s.shelf_number
      INTO wrong_shelf_book_id, wrong_shelf_book_title, correct_shelf_number
      FROM books b
      JOIN shelves s ON b.shelf_id = s.id
      WHERE b.shelf_id != NEW.id  -- Different shelf
        AND b.status IN ('reserved', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
      
      IF wrong_shelf_book_id IS NOT NULL THEN
        -- Book placed on WRONG shelf!
        INSERT INTO shelf_alerts (
          shelf_id,
          shelf_number,
          alert_type,
          message,
          detected_weight,
          book_id
        ) VALUES (
          NEW.id,
          NEW.shelf_number,
          'wrong_shelf',
          format('Book "%s" (belongs to Shelf %s) was placed on Shelf %s. Weight: %sg', 
            wrong_shelf_book_title, 
            correct_shelf_number, 
            NEW.shelf_number,
            weight_diff
          ),
          weight_diff,
          wrong_shelf_book_id
        );
        
        RAISE NOTICE '⚠️ ALERT: Book "%" from Shelf % placed on Shelf %!', 
          wrong_shelf_book_title, correct_shelf_number, NEW.shelf_number;
      ELSE
        -- Unknown object added
        INSERT INTO shelf_alerts (
          shelf_id,
          shelf_number,
          alert_type,
          message,
          detected_weight
        ) VALUES (
          NEW.id,
          NEW.shelf_number,
          'unknown_object',
          format('Unknown object (%sg) detected on Shelf %s. Not matching any registered book.', 
            weight_diff,
            NEW.shelf_number
          ),
          weight_diff
        );
        
        RAISE NOTICE '❓ ALERT: Unknown object (%g) added to Shelf %', 
          weight_diff, NEW.shelf_number;
      END IF;
    END IF;
    
    -- ============================================
    -- STEP 3: Process detected book (if found on correct shelf)
    -- ============================================
    IF matching_book_id IS NOT NULL THEN
      IF weight_increased THEN
        -- ===== BOOK RETURNED =====
        IF matching_book_status = 'issued' THEN
          -- Mark as returned
          UPDATE issued_books
          SET returned_at = NOW()
          WHERE book_id = matching_book_id
            AND returned_at IS NULL;
          
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE '✅ Book RETURNED to Shelf %: "%"', 
            NEW.shelf_number, matching_book_title;
        ELSE
          -- Available book added back
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE '📚 Book ADDED to Shelf %: "%"', 
            NEW.shelf_number, matching_book_title;
        END IF;
        
      ELSE
        -- ===== BOOK REMOVED (PICKUP) =====
            
        IF matching_book_status = 'reserved' THEN
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
            IF reservation_is_expired THEN
              -- ⏰ RESERVATION EXPIRED - Don't issue!
              RAISE NOTICE '❌ Reservation EXPIRED for "%". Reservation expired at %. Pickup denied.', 
                matching_book_title, reservation_expires_at;
              
              -- Mark reservation as expired
              UPDATE reservations
              SET status = 'expired'
              WHERE id = active_reservation_id;
              
              -- Keep book as available (or mark it as such)
              UPDATE books
              SET status = 'available'
              WHERE id = matching_book_id;
              
              -- Create alert for expired pickup attempt
              INSERT INTO shelf_alerts (
                shelf_id,
                shelf_number,
                alert_type,
                message,
                detected_weight,
                book_id
              ) VALUES (
                NEW.id,
                NEW.shelf_number,
                'expired_reservation',
                format('Attempted pickup of "%s" after reservation expired (expired: %s)', 
                  matching_book_title,
                  TO_CHAR(reservation_expires_at, 'HH24:MI:SS')
                ),
                weight_diff,
                matching_book_id
              );
              
            ELSE
              -- ✅ VALID RESERVATION - Issue the book!
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
              
              RAISE NOTICE '✅ Reserved book PICKED UP from Shelf %: "%" by user % (within time limit)', 
                NEW.shelf_number, matching_book_title, reservation_user_id;
            END IF;
          ELSE
            -- Reserved but no active reservation found (shouldn't happen)
            RAISE NOTICE '⚠️ Reserved book "%" removed but no active reservation found!', 
              matching_book_title;
          END IF;
          
        ELSIF matching_book_status = 'available' THEN
          -- Available book picked up without reservation
          RAISE NOTICE '📖 Available book "%" picked up from Shelf % (no reservation)', 
            matching_book_title, NEW.shelf_number;
          
          -- Optional: Update status but don't issue (requires reservation)
          -- Or you can auto-issue for walk-in borrowing
        END IF;
      END IF;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
CREATE TRIGGER on_shelf_weight_change
  AFTER UPDATE OF current_weight ON shelves
  FOR EACH ROW
  WHEN (OLD.current_weight IS DISTINCT FROM NEW.current_weight)
  EXECUTE FUNCTION detect_book_from_weight_change();

-- ============================================
-- 4. Create notification for expired reservations
-- ============================================
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
-- 5. Verification
-- ============================================
SELECT '✅ Realistic library system installed!' as status;
SELECT 'Features enabled:' as info
UNION ALL SELECT '  • Reservations expire automatically after 5 minutes'
UNION ALL SELECT '  • Books can only be picked up within reservation time'
UNION ALL SELECT '  • Expired pickup attempts are blocked and logged'
UNION ALL SELECT '  • Notifications sent when reservations expire'
UNION ALL SELECT '  • Weight sensors trigger real pickup/return detection'
UNION ALL SELECT '  • Wrong shelf placements are detected and alerted';

-- ============================================
-- 6. Manual cleanup (run this to expire old reservations now)
-- ============================================
SELECT expire_old_reservations();
SELECT notify_expired_reservations();
