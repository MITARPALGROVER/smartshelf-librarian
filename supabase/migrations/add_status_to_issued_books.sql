-- Add missing columns to issued_books table

-- Add status column
ALTER TABLE issued_books 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'issued' CHECK (status IN ('issued', 'returned', 'overdue'));

COMMENT ON COLUMN issued_books.status IS 'Status: issued (currently borrowed), returned (book returned), overdue (past due date)';

-- Add shelf_id column (which shelf the book was taken from)
ALTER TABLE issued_books
ADD COLUMN IF NOT EXISTS shelf_id UUID REFERENCES shelves(id);

COMMENT ON COLUMN issued_books.shelf_id IS 'Shelf from which the book was issued';

-- Add return_shelf_id column (which shelf the book was returned to)
ALTER TABLE issued_books
ADD COLUMN IF NOT EXISTS return_shelf_id UUID REFERENCES shelves(id);

COMMENT ON COLUMN issued_books.return_shelf_id IS 'Shelf to which the book was returned';

-- Add unlock_event_id column (links to the door unlock event)
ALTER TABLE issued_books
ADD COLUMN IF NOT EXISTS unlock_event_id UUID REFERENCES door_unlock_events(id);

COMMENT ON COLUMN issued_books.unlock_event_id IS 'Door unlock event that triggered this issue';

-- Set default for existing records
UPDATE issued_books 
SET status = CASE 
  WHEN returned_at IS NOT NULL THEN 'returned'
  WHEN due_date < NOW() AND returned_at IS NULL THEN 'overdue'
  ELSE 'issued'
END
WHERE status IS NULL;
