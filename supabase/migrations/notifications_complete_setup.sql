-- 🔔 NOTIFICATION SYSTEM DEBUG & SETUP
-- Run this entire file in Supabase SQL Editor to set up notifications

-- ============================================
-- STEP 1: Create notifications table
-- ============================================
DROP TABLE IF EXISTS notifications CASCADE;

CREATE TABLE notifications (
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

-- Create indexes
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- ============================================
-- STEP 2: Enable Row Level Security
-- ============================================
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
DROP POLICY IF EXISTS "System can create notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can delete own notifications" ON notifications;

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

-- ============================================
-- STEP 3: Create notification trigger function
-- ============================================
DROP FUNCTION IF EXISTS notify_wrong_shelf_pickup() CASCADE;

CREATE OR REPLACE FUNCTION notify_wrong_shelf_pickup()
RETURNS TRIGGER AS $$
DECLARE
  student_id UUID;
  student_email TEXT;
  book_title TEXT;
  correct_shelf INT;
  librarian_record RECORD;
BEGIN
  RAISE NOTICE 'Trigger fired: alert_type=%', NEW.alert_type;
  
  -- Only process wrong_shelf alerts
  IF NEW.alert_type = 'wrong_shelf' AND NEW.book_id IS NOT NULL THEN
    
    RAISE NOTICE 'Processing wrong_shelf alert for book_id=%', NEW.book_id;
    
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

    RAISE NOTICE 'Found student: id=%, email=%, book=%', student_id, student_email, book_title;

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
      
      RAISE NOTICE 'Created notification for student %', student_email;

      -- Notify all librarians
      FOR librarian_record IN 
        SELECT id, email FROM profiles WHERE role = 'librarian'
      LOOP
        INSERT INTO notifications (user_id, type, title, message, metadata)
        VALUES (
          librarian_record.id,
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
        
        RAISE NOTICE 'Created notification for librarian %', librarian_record.email;
      END LOOP;
    ELSE
      RAISE NOTICE 'No student found for book_id=%', NEW.book_id;
    END IF;

  -- Handle unknown object alerts
  ELSIF NEW.alert_type = 'unknown_object' THEN
    
    RAISE NOTICE 'Processing unknown_object alert on shelf %', NEW.shelf_number;
    
    -- Notify all librarians and admins
    FOR librarian_record IN 
      SELECT id, email FROM profiles WHERE role IN ('librarian', 'admin')
    LOOP
      INSERT INTO notifications (user_id, type, title, message, metadata)
      VALUES (
        librarian_record.id,
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
      
      RAISE NOTICE 'Created unknown_object notification for %', librarian_record.email;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- STEP 4: Create trigger on shelf_alerts
-- ============================================
DROP TRIGGER IF EXISTS trigger_notify_shelf_alerts ON shelf_alerts;

CREATE TRIGGER trigger_notify_shelf_alerts
  AFTER INSERT ON shelf_alerts
  FOR EACH ROW
  EXECUTE FUNCTION notify_wrong_shelf_pickup();

-- ============================================
-- STEP 5: Verification queries
-- ============================================

-- Check if table exists
SELECT 'notifications table exists' as status, count(*) as row_count 
FROM notifications;

-- Check if trigger exists
SELECT 'trigger exists' as status
FROM pg_trigger 
WHERE tgname = 'trigger_notify_shelf_alerts';

-- Show current notifications
SELECT 
  n.id,
  n.type,
  n.title,
  p.email as user_email,
  n.is_read,
  n.created_at
FROM notifications n
JOIN profiles p ON p.id = n.user_id
ORDER BY n.created_at DESC
LIMIT 10;

-- ============================================
-- STEP 6: Manual test notification
-- ============================================
-- Uncomment and run this to create a test notification for yourself:
-- Replace 'YOUR_EMAIL@example.com' with your actual email

/*
INSERT INTO notifications (user_id, type, title, message)
SELECT 
  id,
  'info',
  '🧪 Test Notification',
  'If you can see this in the bell icon, notifications are working!'
FROM profiles
WHERE email = 'YOUR_EMAIL@example.com'
LIMIT 1;
*/

-- ============================================
-- SUCCESS MESSAGE
-- ============================================
SELECT 
  '✅ Notification system setup complete!' as message,
  'Run the manual test above to verify' as next_step;
