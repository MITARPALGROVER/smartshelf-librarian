-- Comprehensive fix: Add all missing columns to tables
-- This fixes all the schema mismatches between code and database

-- 1. Add missing columns to door_unlock_events
ALTER TABLE door_unlock_events 
ADD COLUMN IF NOT EXISTS expected_action TEXT CHECK (expected_action IN ('pickup', 'return')),
ADD COLUMN IF NOT EXISTS actual_action TEXT CHECK (actual_action IN ('pickup', 'return', 'timeout')),
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN door_unlock_events.expected_action IS 'Expected action: pickup (issue) or return';
COMMENT ON COLUMN door_unlock_events.actual_action IS 'What actually happened: pickup, return, or timeout';
COMMENT ON COLUMN door_unlock_events.completed_at IS 'When the action was completed';

-- 2. Add missing columns to issued_books
ALTER TABLE issued_books 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'issued' CHECK (status IN ('issued', 'returned', 'overdue')),
ADD COLUMN IF NOT EXISTS shelf_id UUID REFERENCES shelves(id),
ADD COLUMN IF NOT EXISTS return_shelf_id UUID REFERENCES shelves(id),
ADD COLUMN IF NOT EXISTS unlock_event_id UUID REFERENCES door_unlock_events(id);

COMMENT ON COLUMN issued_books.status IS 'Status: issued, returned, or overdue';
COMMENT ON COLUMN issued_books.shelf_id IS 'Shelf from which book was issued';
COMMENT ON COLUMN issued_books.return_shelf_id IS 'Shelf to which book was returned';
COMMENT ON COLUMN issued_books.unlock_event_id IS 'Door unlock event that triggered this';

-- 3. Add current_shelf_id to books if not exists
ALTER TABLE books
ADD COLUMN IF NOT EXISTS current_shelf_id UUID REFERENCES shelves(id);

COMMENT ON COLUMN books.current_shelf_id IS 'Current shelf location of the book';

-- 4. Add missing columns to notifications table
ALTER TABLE notifications
ADD COLUMN IF NOT EXISTS related_book_id UUID REFERENCES books(id),
ADD COLUMN IF NOT EXISTS metadata JSONB;

COMMENT ON COLUMN notifications.related_book_id IS 'Book related to this notification';
COMMENT ON COLUMN notifications.metadata IS 'Additional metadata as JSON';

-- 5. Set defaults for existing records
UPDATE issued_books 
SET status = CASE 
  WHEN returned_at IS NOT NULL THEN 'returned'
  WHEN due_date < NOW() AND returned_at IS NULL THEN 'overdue'
  ELSE 'issued'
END
WHERE status IS NULL;

UPDATE door_unlock_events
SET expected_action = 'pickup'
WHERE expected_action IS NULL;

-- 5. Update books to set current_shelf_id from shelf_id if not set
UPDATE books
SET current_shelf_id = shelf_id
WHERE current_shelf_id IS NULL AND shelf_id IS NOT NULL;

COMMENT ON TABLE door_unlock_events IS 'Records each time a shelf door is unlocked';
COMMENT ON TABLE issued_books IS 'Tracks book issues and returns with full audit trail';
