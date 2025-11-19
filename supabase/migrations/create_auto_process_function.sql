-- ================================================
-- AUTO-PROCESS BOOK TRANSACTIONS
-- Run this AFTER creating shelf_weight_events table
-- ================================================

-- Function: Automatically process book pickup/return based on weight changes
CREATE OR REPLACE FUNCTION process_book_transaction()
RETURNS TRIGGER AS $$
DECLARE
  v_shelf_id UUID;
  v_user_id UUID;
  v_book_id UUID;
  v_unlock_event_id UUID;
  v_student_email TEXT;
  v_student_name TEXT;
  v_book_title TEXT;
BEGIN
  -- Get the shelf and user info
  v_shelf_id := NEW.shelf_id;
  v_user_id := NEW.user_id;
  v_unlock_event_id := NEW.unlock_event_id;

  -- Only process if we have a user (book must be associated with someone)
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'No user associated with weight event - skipping auto-processing';
    RETURN NEW;
  END IF;

  -- Get user info
  SELECT 
    COALESCE(p.full_name, p.email),
    p.email
  INTO v_student_name, v_student_email
  FROM profiles p
  WHERE p.id = v_user_id;

  IF NEW.action = 'pickup' THEN
    -- BOOK PICKUP: Find an available book on this shelf and issue it
    RAISE NOTICE 'Processing PICKUP for user % on shelf %', v_user_id, v_shelf_id;
    
    SELECT b.id, b.title
    INTO v_book_id, v_book_title
    FROM books b
    WHERE b.shelf_id = v_shelf_id
      AND b.status = 'available'
    LIMIT 1;

    IF v_book_id IS NOT NULL THEN
      -- Create issued_books record
      INSERT INTO issued_books (
        book_id,
        user_id,
        issued_at,
        due_date
      ) VALUES (
        v_book_id,
        v_user_id,
        NOW(),
        NOW() + INTERVAL '14 days'
      );

      -- Update book status
      UPDATE books 
      SET status = 'issued'
      WHERE id = v_book_id;

      -- Update unlock event
      IF v_unlock_event_id IS NOT NULL THEN
        UPDATE door_unlock_events
        SET book_issued = true
        WHERE id = v_unlock_event_id;
      END IF;

      -- Send notification to student
      INSERT INTO notifications (
        user_id,
        type,
        title,
        message
      ) VALUES (
        v_user_id,
        'book_issued',
        '📚 Book Issued',
        format('You have successfully borrowed "%s". Due date: %s', 
          v_book_title, 
          TO_CHAR(NOW() + INTERVAL '14 days', 'Mon DD, YYYY'))
      );

      -- Notify librarians
      INSERT INTO notifications (user_id, type, title, message)
      SELECT 
        id,
        'book_issued',
        '📤 Book Issued (Auto)',
        format('Book "%s" automatically issued to %s via weight sensor', v_book_title, v_student_name)
      FROM auth.users
      WHERE raw_user_meta_data->>'role' IN ('librarian', 'admin');

      RAISE NOTICE '✅ Book % automatically issued to user %', v_book_id, v_user_id;
    ELSE
      RAISE NOTICE '⚠️ No available books found on shelf % for pickup', v_shelf_id;
    END IF;

  ELSIF NEW.action = 'return' THEN
    -- BOOK RETURN: Find the user's issued book from this shelf and return it
    RAISE NOTICE 'Processing RETURN for user % on shelf %', v_user_id, v_shelf_id;
    
    SELECT ib.id, b.id, b.title
    INTO v_unlock_event_id, v_book_id, v_book_title
    FROM issued_books ib
    JOIN books b ON b.id = ib.book_id
    WHERE ib.user_id = v_user_id
      AND b.shelf_id = v_shelf_id
      AND ib.returned_at IS NULL
    ORDER BY ib.issued_at DESC
    LIMIT 1;

    IF v_book_id IS NOT NULL THEN
      -- Mark book as returned
      UPDATE issued_books
      SET returned_at = NOW()
      WHERE id = v_unlock_event_id;

      -- Update book status
      UPDATE books
      SET status = 'available'
      WHERE id = v_book_id;

      -- Send notification to student
      INSERT INTO notifications (
        user_id,
        type,
        title,
        message
      ) VALUES (
        v_user_id,
        'book_returned',
        '✅ Book Returned',
        format('You have successfully returned "%s". Thank you!', v_book_title)
      );

      -- Notify librarians
      INSERT INTO notifications (user_id, type, title, message)
      SELECT 
        id,
        'book_returned',
        '📥 Book Returned (Auto)',
        format('Book "%s" automatically returned by %s via weight sensor', v_book_title, v_student_name)
      FROM auth.users
      WHERE raw_user_meta_data->>'role' IN ('librarian', 'admin');

      RAISE NOTICE '✅ Book % automatically returned by user %', v_book_id, v_user_id;
    ELSE
      RAISE NOTICE '⚠️ No issued books found for user % on shelf %', v_user_id, v_shelf_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on shelf_weight_events
DROP TRIGGER IF EXISTS trigger_process_book_transaction ON shelf_weight_events;
CREATE TRIGGER trigger_process_book_transaction
  AFTER INSERT ON shelf_weight_events
  FOR EACH ROW
  EXECUTE FUNCTION process_book_transaction();

-- Success message
DO $$
BEGIN
  RAISE NOTICE '✅ Auto-processing function created successfully!';
  RAISE NOTICE 'Books will now be automatically issued/returned based on weight sensor events.';
END $$;
