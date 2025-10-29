-- ============================================
-- FIX: Auto-create issued_books when reserved book is picked up
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
    -- STEP 2: If no match, check OTHER shelves (wrong shelf detection)
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
          format('Book "%s" (belongs to Shelf %s) may have been placed on Shelf %s. Weight: %sg', 
            wrong_shelf_book_title, 
            correct_shelf_number, 
            NEW.shelf_number,
            weight_diff
          ),
          weight_diff,
          wrong_shelf_book_id
        );
        
        RAISE NOTICE 'ALERT: Book "%" from Shelf % placed on Shelf %!', 
          wrong_shelf_book_title, correct_shelf_number, NEW.shelf_number;
      ELSE
        -- Unknown object added (not a registered book)
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
          format('Unknown object (%sg) added to Shelf %s. No matching book found.', 
            weight_diff,
            NEW.shelf_number
          ),
          weight_diff
        );
        
        RAISE NOTICE 'ALERT: Unknown object (%g) added to Shelf %', 
          weight_diff, NEW.shelf_number;
      END IF;
    END IF;
    
    -- ============================================
    -- STEP 3: Process detected book (if found on correct shelf)
    -- ============================================
    IF matching_book_id IS NOT NULL THEN
      IF weight_increased THEN
        -- Book returned
        IF matching_book_status = 'issued' THEN
          UPDATE issued_books
          SET returned_at = NOW()
          WHERE book_id = matching_book_id
            AND returned_at IS NULL;
          
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book RETURNED to Shelf %: % (auto-returned)', 
            NEW.shelf_number, matching_book_title;
        ELSE
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book ADDED to Shelf %: %', 
            NEW.shelf_number, matching_book_title;
        END IF;
      ELSE
        -- Book removed (PICKUP)
        IF matching_book_status = 'reserved' THEN
          -- ✨ NEW: Find active reservation and create issued_books record
          SELECT r.id, r.user_id
          INTO active_reservation_id, reservation_user_id
          FROM reservations r
          WHERE r.book_id = matching_book_id
            AND r.status = 'active'
          ORDER BY r.reserved_at DESC
          LIMIT 1;
          
          IF active_reservation_id IS NOT NULL THEN
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
            
            RAISE NOTICE '📖 Reserved book PICKED UP from Shelf %: % by user %', 
              NEW.shelf_number, matching_book_title, reservation_user_id;
          ELSE
            RAISE NOTICE '⚠️ Reserved book removed but no active reservation found!';
          END IF;
          
        ELSIF matching_book_status = 'available' THEN
          -- Available book picked up without reservation
          UPDATE books
          SET status = 'issued'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book PICKED UP from Shelf % (no reservation): %', 
            NEW.shelf_number, matching_book_title;
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

-- Verification
SELECT '✅ Book pickup detection fixed!' as status;
SELECT 'Now when you pick up a reserved book:' as info
UNION ALL SELECT '  1. Reservation will be marked as completed'
UNION ALL SELECT '  2. issued_books record will be created'
UNION ALL SELECT '  3. Book status will change to issued'
UNION ALL SELECT '  4. Librarian dashboard will show the book';
