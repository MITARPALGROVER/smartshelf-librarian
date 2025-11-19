-- Add expected_action column to door_unlock_events table
-- This tracks whether the unlock is for picking up (issue) or returning a book

ALTER TABLE door_unlock_events 
ADD COLUMN IF NOT EXISTS expected_action TEXT CHECK (expected_action IN ('pickup', 'return'));

COMMENT ON COLUMN door_unlock_events.expected_action IS 'Expected action: pickup (issue book) or return (return book)';

-- Set default for existing records
UPDATE door_unlock_events 
SET expected_action = 'pickup' 
WHERE expected_action IS NULL;
