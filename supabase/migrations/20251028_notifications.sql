-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('wrong_shelf', 'unknown_object', 'expired_reservation', 'info', 'warning', 'error')),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  metadata JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own notifications
CREATE POLICY "Users can view own notifications"
  ON notifications
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: System can create notifications (allow insert for any authenticated user)
CREATE POLICY "System can create notifications"
  ON notifications
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- Policy: Users can update their own notifications (mark as read)
CREATE POLICY "Users can update own notifications"
  ON notifications
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy: Users can delete their own notifications
CREATE POLICY "Users can delete own notifications"
  ON notifications
  FOR DELETE
  USING (auth.uid() = user_id);

-- Function to automatically notify on wrong shelf detection
CREATE OR REPLACE FUNCTION notify_wrong_shelf_pickup()
RETURNS TRIGGER AS $$
DECLARE
  student_id UUID;
  student_email TEXT;
  book_title TEXT;
  correct_shelf INT;
  librarian_id UUID;
BEGIN
  -- Only process wrong_shelf alerts
  IF NEW.alert_type = 'wrong_shelf' AND NEW.book_id IS NOT NULL THEN
    
    -- Get student info from active reservation
    SELECT r.user_id, p.email, b.title, s.shelf_number
    INTO student_id, student_email, book_title, correct_shelf
    FROM reservations r
    JOIN profiles p ON p.id = r.user_id
    JOIN books b ON b.id = r.book_id
    JOIN shelves s ON s.id = b.shelf_id
    WHERE r.book_id = NEW.book_id
      AND r.status = 'active'
    ORDER BY r.reserved_at DESC
    LIMIT 1;

    -- If we found the student
    IF student_id IS NOT NULL THEN
      -- Notify student
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        student_id,
        'wrong_shelf',
        '⚠️ Wrong Shelf Pickup',
        'You picked up "' || book_title || '" from Shelf ' || NEW.shelf_number || 
        ', but it should be on Shelf ' || correct_shelf || '. Please return it to the correct shelf.',
        jsonb_build_object(
          'correct_shelf', correct_shelf,
          'wrong_shelf', NEW.shelf_number,
          'book_id', NEW.book_id,
          'alert_id', NEW.id
        )
      );

      -- Notify all librarians
      FOR librarian_id IN 
        SELECT id FROM profiles WHERE role = 'librarian'
      LOOP
        INSERT INTO notifications (user_id, type, title, message, metadata)
        VALUES (
          librarian_id,
          'wrong_shelf',
          '⚠️ Wrong Shelf Alert',
          'Student ' || student_email || ' picked up "' || book_title || 
          '" from wrong shelf. Expected: Shelf ' || correct_shelf || 
          ', Actual: Shelf ' || NEW.shelf_number,
          jsonb_build_object(
            'student_email', student_email,
            'student_id', student_id,
            'correct_shelf', correct_shelf,
            'wrong_shelf', NEW.shelf_number,
            'book_id', NEW.book_id,
            'alert_id', NEW.id
          )
        );
      END LOOP;
    END IF;

  -- Handle unknown object alerts
  ELSIF NEW.alert_type = 'unknown_object' THEN
    -- Notify all librarians and admins
    FOR librarian_id IN 
      SELECT id FROM profiles WHERE role IN ('librarian', 'admin')
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_id,
        'unknown_object',
        '❓ Unknown Object Detected',
        'Unknown object (' || NEW.detected_weight || 'g) detected on Shelf ' || 
        NEW.shelf_number || '. Please investigate.',
        jsonb_build_object(
          'shelf_number', NEW.shelf_number,
          'weight', NEW.detected_weight,
          'alert_id', NEW.id
        )
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for shelf alerts
DROP TRIGGER IF EXISTS trigger_notify_shelf_alerts ON shelf_alerts;
CREATE TRIGGER trigger_notify_shelf_alerts
  AFTER INSERT ON shelf_alerts
  FOR EACH ROW
  EXECUTE FUNCTION notify_wrong_shelf_pickup();

-- Function to clean old read notifications (optional, for maintenance)
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS void AS $$
BEGIN
  -- Delete read notifications older than 30 days
  DELETE FROM notifications
  WHERE is_read = true
    AND created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
