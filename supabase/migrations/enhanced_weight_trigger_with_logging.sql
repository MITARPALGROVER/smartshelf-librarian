-- Enhanced version of detect_book_from_weight_change with detailed logging
-- This will help us see exactly what's happening

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
  
  RAISE NOTICE '🔍 WEIGHT CHANGE DETECTED: Shelf % changed from %g to %g (diff: %g, increased: %)',
    NEW.shelf_number, OLD.current_weight, NEW.current_weight, weight_diff, weight_increased;
  
  -- Only process significant weight changes
  IF weight_diff > 10 THEN
    RAISE NOTICE '✅ Significant weight change (>10g), processing...';
  
    -- ============================================
    -- STEP 1: Try to find matching book on THIS shelf
    -- ============================================
    IF weight_increased THEN
      RAISE NOTICE '📈 Weight INCREASED - looking for issued/reserved books to return';
      
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
      
      IF matching_book_id IS NOT NULL THEN
        RAISE NOTICE '📚 FOUND matching book: "%" (status: %)', matching_book_title, matching_book_status;
      ELSE
        RAISE NOTICE '❌ NO matching issued/reserved book found on this shelf';
      END IF;
      
    ELSE
      RAISE NOTICE '📉 Weight DECREASED - looking for available/reserved books for pickup';
      
      -- First, let's see ALL books on this shelf
      RAISE NOTICE '🔎 Searching for books on Shelf % (shelf_id: %)', NEW.shelf_number, NEW.id;
      
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
      
      IF matching_book_id IS NOT NULL THEN
        RAISE NOTICE '📚 FOUND matching book: "%" (status: %, weight diff: %g)', 
          matching_book_title, matching_book_status, ABS((SELECT weight FROM books WHERE id = matching_book_id) - weight_diff);
      ELSE
        RAISE NOTICE '❌ NO matching available/reserved book found on Shelf %', NEW.shelf_number;
        
        -- Debug: Show what books ARE on this shelf
        RAISE NOTICE '🐛 DEBUG - Books on Shelf %:', NEW.shelf_number;
        FOR matching_book_id, matching_book_title, matching_book_status IN 
          SELECT b.id, b.title, b.status 
          FROM books b 
          WHERE b.shelf_id = NEW.id
        LOOP
          RAISE NOTICE '  - % (status: %)', matching_book_title, matching_book_status;
        END LOOP;
        
        matching_book_id := NULL; -- Reset
      END IF;
    END IF;
    
    -- ============================================
    -- STEP 2: If no match on correct shelf, check OTHER shelves (wrong shelf)
    -- ============================================
    IF matching_book_id IS NULL AND weight_increased THEN
      RAISE NOTICE '🔍 Checking other shelves for wrong placement...';
      
      SELECT b.id, b.title, s.shelf_number
      INTO wrong_shelf_book_id, wrong_shelf_book_title, correct_shelf_number
      FROM books b
      JOIN shelves s ON b.shelf_id = s.id
      WHERE b.shelf_id != NEW.id
        AND b.status IN ('reserved', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
      
      IF wrong_shelf_book_id IS NOT NULL THEN
        RAISE NOTICE '⚠️ WRONG SHELF DETECTED: "%" from Shelf % placed on Shelf %', 
          wrong_shelf_book_title, correct_shelf_number, NEW.shelf_number;
          
        INSERT INTO shelf_alerts (
          shelf_id, shelf_number, alert_type, message, detected_weight, book_id
        ) VALUES (
          NEW.id, NEW.shelf_number, 'wrong_shelf',
          format('Book "%s" (belongs to Shelf %s) was placed on Shelf %s. Weight: %sg', 
            wrong_shelf_book_title, correct_shelf_number, NEW.shelf_number, weight_diff),
          weight_diff, wrong_shelf_book_id
        );
      ELSE
        RAISE NOTICE '❓ UNKNOWN OBJECT detected on Shelf %', NEW.shelf_number;
        
        INSERT INTO shelf_alerts (
          shelf_id, shelf_number, alert_type, message, detected_weight
        ) VALUES (
          NEW.id, NEW.shelf_number, 'unknown_object',
          format('Unknown object (%sg) detected on Shelf %s. Not matching any registered book.', 
            weight_diff, NEW.shelf_number),
          weight_diff
        );
      END IF;
    END IF;
    
    -- ============================================
    -- STEP 3: Process detected book (if found on correct shelf)
    -- ============================================
    IF matching_book_id IS NOT NULL THEN
      RAISE NOTICE '🎯 Processing matched book: "%"', matching_book_title;
      
      IF weight_increased THEN
        RAISE NOTICE '📥 BOOK RETURNED to shelf';
        
        IF matching_book_status = 'issued' THEN
          UPDATE issued_books SET returned_at = NOW()
          WHERE book_id = matching_book_id AND returned_at IS NULL;
          
          UPDATE books SET status = 'available' WHERE id = matching_book_id;
          RAISE NOTICE '✅ Book RETURNED and marked as available: "%"', matching_book_title;
        ELSE
          UPDATE books SET status = 'available' WHERE id = matching_book_id;
          RAISE NOTICE '✅ Book ADDED to shelf: "%"', matching_book_title;
        END IF;
        
      ELSE
        RAISE NOTICE '📤 BOOK PICKED UP from shelf (status: %)', matching_book_status;
            
        IF matching_book_status = 'reserved' THEN
          RAISE NOTICE '🔍 Checking for active reservation...';
          
          SELECT r.id, r.user_id, r.expires_at, (r.expires_at < NOW()) as is_expired
          INTO active_reservation_id, reservation_user_id, reservation_expires_at, reservation_is_expired
          FROM reservations r
          WHERE r.book_id = matching_book_id AND r.status = 'active'
          ORDER BY r.reserved_at DESC LIMIT 1;
          
          IF active_reservation_id IS NOT NULL THEN
            RAISE NOTICE '📋 Found reservation ID: % (expires: %, expired: %)', 
              active_reservation_id, reservation_expires_at, reservation_is_expired;
            
            IF reservation_is_expired THEN
              RAISE NOTICE '❌ RESERVATION EXPIRED - Pickup DENIED';
              
              UPDATE reservations SET status = 'expired' WHERE id = active_reservation_id;
              UPDATE books SET status = 'available' WHERE id = matching_book_id;
              
              INSERT INTO shelf_alerts (shelf_id, shelf_number, alert_type, message, detected_weight, book_id)
              VALUES (NEW.id, NEW.shelf_number, 'expired_reservation',
                format('Attempted pickup of "%s" after reservation expired', matching_book_title),
                weight_diff, matching_book_id);
              
            ELSE
              RAISE NOTICE '✅ VALID RESERVATION - Issuing book...';
              
              UPDATE reservations SET status = 'completed' WHERE id = active_reservation_id;
              
              INSERT INTO issued_books (book_id, user_id, issued_at, due_date)
              VALUES (matching_book_id, reservation_user_id, NOW(), NOW() + INTERVAL '14 days');
              
              UPDATE books SET status = 'issued' WHERE id = matching_book_id;
              
              RAISE NOTICE '🎉 SUCCESS! Book issued to user %', reservation_user_id;
            END IF;
          ELSE
            RAISE NOTICE '⚠️ Reserved book but NO active reservation found!';
          END IF;
          
        ELSIF matching_book_status = 'available' THEN
          RAISE NOTICE '📖 Available book picked up (no reservation)';
        END IF;
      END IF;
    ELSE
      RAISE NOTICE '❌ No matching book found to process';
    END IF;
    
  ELSE
    RAISE NOTICE '⏭️ Weight change too small (<%g), ignoring', weight_diff;
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

SELECT '✅ Enhanced trigger with detailed logging installed!' as status;
SELECT 'Check Supabase Logs tab after pickup to see detailed RAISE NOTICE messages' as next_step;
