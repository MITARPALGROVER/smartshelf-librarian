-- Migration: Auto Issue and Return Books Based on Weight Changes
-- This handles the complete flow:
-- 1. Track who unlocked each shelf door
-- 2. Auto-issue book when picked up (weight decreases)
-- 3. Auto-return book when put back (weight increases)

-- Table to track door unlock events
CREATE TABLE IF NOT EXISTS door_unlock_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shelf_id UUID REFERENCES shelves(id) NOT NULL,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  unlocked_at TIMESTAMP DEFAULT NOW(),
  book_issued BOOLEAN DEFAULT FALSE,
  book_id UUID REFERENCES books(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_door_unlock_shelf ON door_unlock_events(shelf_id, book_issued);
CREATE INDEX idx_door_unlock_user ON door_unlock_events(user_id);

-- Function to handle book pickup (weight decrease while door unlocked)
CREATE OR REPLACE FUNCTION handle_book_pickup()
RETURNS TRIGGER AS $$
DECLARE
  v_unlock_event door_unlock_events;
  v_book books;
  v_due_date TIMESTAMP;
BEGIN
  -- Only process if weight decreased significantly
  IF NEW.current_weight >= OLD.current_weight THEN
    RETURN NEW;
  END IF;

  -- Find the most recent unlock event for this shelf that hasn't issued a book yet
  SELECT * INTO v_unlock_event
  FROM door_unlock_events
  WHERE shelf_id = NEW.id
    AND book_issued = FALSE
    AND unlocked_at > NOW() - INTERVAL '5 minutes'
  ORDER BY unlocked_at DESC
  LIMIT 1;

  -- If no unlock event found, skip
  IF v_unlock_event.id IS NULL THEN
    RAISE NOTICE 'No recent unlock event found for shelf %', NEW.id;
    RETURN NEW;
  END IF;

  -- Find an available book on this shelf
  SELECT * INTO v_book
  FROM books
  WHERE shelf_id = NEW.id
    AND status = 'available'
  LIMIT 1;

  -- If no available book, skip
  IF v_book.id IS NULL THEN
    RAISE NOTICE 'No available books on shelf %', NEW.id;
    RETURN NEW;
  END IF;

  -- Calculate due date (14 days from now)
  v_due_date := NOW() + INTERVAL '14 days';

  -- Issue the book to the user
  INSERT INTO issued_books (
    book_id,
    user_id,
    issued_at,
    due_date
  ) VALUES (
    v_book.id,
    v_unlock_event.user_id,
    NOW(),
    v_due_date
  );

  -- Update book status
  UPDATE books
  SET status = 'issued'
  WHERE id = v_book.id;

  -- Mark unlock event as processed
  UPDATE door_unlock_events
  SET book_issued = TRUE,
      book_id = v_book.id
  WHERE id = v_unlock_event.id;

  -- Create notification
  INSERT INTO notifications (
    user_id,
    type,
    title,
    message,
    metadata
  ) VALUES (
    v_unlock_event.user_id,
    'info',
    '📚 Book Issued',
    'Your book "' || v_book.title || '" has been automatically issued!',
    jsonb_build_object(
      'book_id', v_book.id,
      'book_title', v_book.title,
      'shelf_id', NEW.id,
      'due_date', v_due_date
    )
  );

  RAISE NOTICE 'Book % issued to user %', v_book.title, v_unlock_event.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle book return (weight increase)
CREATE OR REPLACE FUNCTION handle_book_return()
RETURNS TRIGGER AS $$
DECLARE
  v_issued_book issued_books;
  v_book books;
BEGIN
  -- Only process if weight increased significantly
  IF NEW.current_weight <= OLD.current_weight THEN
    RETURN NEW;
  END IF;

  -- Find a book that was issued from this shelf and not yet returned
  SELECT ib.* INTO v_issued_book
  FROM issued_books ib
  JOIN books b ON b.id = ib.book_id
  WHERE b.shelf_id = NEW.id
    AND ib.returned_at IS NULL
  ORDER BY ib.issued_at DESC
  LIMIT 1;

  -- If no issued book found, skip
  IF v_issued_book.id IS NULL THEN
    RAISE NOTICE 'No issued books found for shelf %', NEW.id;
    RETURN NEW;
  END IF;

  -- Get book details
  SELECT * INTO v_book
  FROM books
  WHERE id = v_issued_book.book_id;

  -- Mark book as returned
  UPDATE issued_books
  SET returned_at = NOW()
  WHERE id = v_issued_book.id;

  -- Update book status back to available
  UPDATE books
  SET status = 'available'
  WHERE id = v_issued_book.book_id;

  -- Create notification
  INSERT INTO notifications (
    user_id,
    type,
    title,
    message,
    metadata
  ) VALUES (
    v_issued_book.user_id,
    'info',
    '✅ Book Returned',
    'Your book "' || v_book.title || '" has been returned successfully!',
    jsonb_build_object(
      'book_id', v_book.id,
      'book_title', v_book.title,
      'shelf_id', NEW.id,
      'returned_at', NOW()
    )
  );

  RAISE NOTICE 'Book % returned by user %', v_book.title, v_issued_book.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS trigger_book_pickup ON shelves;
DROP TRIGGER IF EXISTS trigger_book_return ON shelves;

-- Create trigger for book pickup (weight decrease)
CREATE TRIGGER trigger_book_pickup
AFTER UPDATE OF current_weight ON shelves
FOR EACH ROW
WHEN (NEW.current_weight < OLD.current_weight - 5)  -- Weight decreased by more than 5g
EXECUTE FUNCTION handle_book_pickup();

-- Create trigger for book return (weight increase)
CREATE TRIGGER trigger_book_return
AFTER UPDATE OF current_weight ON shelves
FOR EACH ROW
WHEN (NEW.current_weight > OLD.current_weight + 5)  -- Weight increased by more than 5g
EXECUTE FUNCTION handle_book_return();

-- Grant permissions
GRANT ALL ON door_unlock_events TO authenticated;
GRANT ALL ON door_unlock_events TO service_role;

-- RLS Policies for door_unlock_events
ALTER TABLE door_unlock_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own unlock events"
ON door_unlock_events
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own unlock events"
ON door_unlock_events
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role can insert unlock events"
ON door_unlock_events
FOR INSERT
TO service_role
WITH CHECK (true);

CREATE POLICY "Service role can update unlock events"
ON door_unlock_events
FOR UPDATE
TO service_role
USING (true);

-- Comments
COMMENT ON TABLE door_unlock_events IS 'Tracks door unlock events to know which user should get the book';
COMMENT ON FUNCTION handle_book_pickup() IS 'Auto-issues book when weight decreases after door unlock';
COMMENT ON FUNCTION handle_book_return() IS 'Auto-returns book when weight increases (book put back)';
