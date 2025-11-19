-- ================================================
-- Smart Shelf Production Tables
-- Run this in Supabase SQL Editor
-- ================================================

-- Table: shelf_weight_events
-- Records all weight changes detected by the shelf sensor
CREATE TABLE IF NOT EXISTS shelf_weight_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shelf_id UUID NOT NULL REFERENCES shelves(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('pickup', 'return')),
  current_weight NUMERIC NOT NULL,
  previous_weight NUMERIC NOT NULL,
  weight_change NUMERIC NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  unlock_event_id UUID REFERENCES door_unlock_events(id) ON DELETE SET NULL,
  detected_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_shelf_id ON shelf_weight_events(shelf_id);
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_detected_at ON shelf_weight_events(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_user_id ON shelf_weight_events(user_id);

-- Enable Row Level Security
ALTER TABLE shelf_weight_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies for shelf_weight_events
CREATE POLICY "Allow ESP8266 to insert weight events"
  ON shelf_weight_events FOR INSERT
  WITH CHECK (true);  -- Allow inserts from anyone (ESP8266 uses service role key)

CREATE POLICY "Allow librarians to view all weight events"
  ON shelf_weight_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'librarian'
    )
  );

CREATE POLICY "Allow students to view their own weight events"
  ON shelf_weight_events FOR SELECT
  USING (user_id = auth.uid());

-- ================================================
-- Function: Automatically process book pickup/return
-- Triggered by shelf_weight_events
-- ================================================

CREATE OR REPLACE FUNCTION process_book_transaction()
RETURNS TRIGGER AS $$
DECLARE
  v_book_id UUID;
  v_user_id UUID;
  v_issued_book_id UUID;
BEGIN
  -- Get user_id from the unlock event
  IF NEW.unlock_event_id IS NOT NULL THEN
    SELECT user_id INTO v_user_id
    FROM door_unlock_events
    WHERE id = NEW.unlock_event_id;
  ELSE
    v_user_id := NEW.user_id;
  END IF;

  -- Only process if we have a user
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'No user associated with weight change event';
    RETURN NEW;
  END IF;

  -- BOOK PICKUP (weight decreased)
  IF NEW.action = 'pickup' THEN
    -- Find which book is on this shelf and not yet issued
    SELECT id INTO v_book_id
    FROM books
    WHERE shelf_id = NEW.shelf_id
    AND status = 'available'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_book_id IS NOT NULL THEN
      -- Create issued_books record
      INSERT INTO issued_books (book_id, user_id, issued_at)
      VALUES (v_book_id, v_user_id, now())
      RETURNING id INTO v_issued_book_id;

      -- Update book status
      UPDATE books
      SET status = 'issued'
      WHERE id = v_book_id;

      -- Create notification for student
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        v_user_id,
        'success',
        '📚 Book Issued Successfully',
        'Your book has been automatically issued. Return it to the same shelf when done.',
        jsonb_build_object(
          'book_id', v_book_id,
          'shelf_id', NEW.shelf_id,
          'action', 'auto_issue',
          'weight_change', NEW.weight_change
        )
      );

      -- Create notification for librarian
      INSERT INTO notifications (user_id, type, title, message, metadata)
      SELECT 
        ur.user_id,
        'info',
        '📤 Book Picked Up',
        'A student picked up a book from Shelf ' || s.shelf_number,
        jsonb_build_object(
          'book_id', v_book_id,
          'shelf_id', NEW.shelf_id,
          'student_id', v_user_id,
          'action', 'auto_issue',
          'weight_change', NEW.weight_change
        )
      FROM user_roles ur
      CROSS JOIN shelves s
      WHERE ur.role = 'librarian'
      AND s.id = NEW.shelf_id;

      RAISE NOTICE 'Book % auto-issued to user %', v_book_id, v_user_id;
    END IF;
  
  -- BOOK RETURN (weight increased)
  ELSIF NEW.action = 'return' THEN
    -- Find the issued book for this user and shelf
    SELECT ib.id, ib.book_id INTO v_issued_book_id, v_book_id
    FROM issued_books ib
    JOIN books b ON b.id = ib.book_id
    WHERE ib.user_id = v_user_id
    AND b.shelf_id = NEW.shelf_id
    AND ib.returned_at IS NULL
    ORDER BY ib.issued_at DESC
    LIMIT 1;

    IF v_issued_book_id IS NOT NULL THEN
      -- Update issued_books record
      UPDATE issued_books
      SET returned_at = now()
      WHERE id = v_issued_book_id;

      -- Update book status
      UPDATE books
      SET status = 'available'
      WHERE id = v_book_id;

      -- Create notification for student
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        v_user_id,
        'success',
        '✅ Book Returned Successfully',
        'Thank you for returning the book on time!',
        jsonb_build_object(
          'book_id', v_book_id,
          'shelf_id', NEW.shelf_id,
          'action', 'auto_return',
          'weight_change', NEW.weight_change
        )
      );

      -- Create notification for librarian
      INSERT INTO notifications (user_id, type, title, message, metadata)
      SELECT 
        ur.user_id,
        'info',
        '📥 Book Returned',
        'A student returned a book to Shelf ' || s.shelf_number,
        jsonb_build_object(
          'book_id', v_book_id,
          'shelf_id', NEW.shelf_id,
          'student_id', v_user_id,
          'action', 'auto_return',
          'weight_change', NEW.weight_change
        )
      FROM user_roles ur
      CROSS JOIN shelves s
      WHERE ur.role = 'librarian'
      AND s.id = NEW.shelf_id;

      RAISE NOTICE 'Book % auto-returned by user %', v_book_id, v_user_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic book transaction processing
DROP TRIGGER IF EXISTS trigger_process_book_transaction ON shelf_weight_events;
CREATE TRIGGER trigger_process_book_transaction
  AFTER INSERT ON shelf_weight_events
  FOR EACH ROW
  EXECUTE FUNCTION process_book_transaction();

-- ================================================
-- Grant permissions
-- ================================================

-- Allow service role to bypass RLS (for ESP8266)
ALTER TABLE shelf_weight_events FORCE ROW LEVEL SECURITY;

-- ================================================
-- Test the setup
-- ================================================

-- View recent weight events
-- SELECT * FROM shelf_weight_events ORDER BY detected_at DESC LIMIT 10;

-- View books with their shelf info
-- SELECT b.title, s.shelf_number, b.status
-- FROM books b
-- JOIN shelves s ON s.id = b.shelf_id
-- ORDER BY s.shelf_number;
