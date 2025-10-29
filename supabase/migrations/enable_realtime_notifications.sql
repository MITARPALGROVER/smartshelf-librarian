-- ============================================
-- ENABLE REALTIME FOR NOTIFICATIONS
-- Ensures notifications are delivered instantly
-- ============================================

-- Enable Realtime for notifications table
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- Verify Realtime is enabled
SELECT 
  tablename,
  CASE 
    WHEN tablename IN (
      SELECT tablename 
      FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime'
    ) THEN '✅ Enabled'
    ELSE '❌ Not Enabled'
  END as realtime_status
FROM pg_tables
WHERE schemaname = 'public' 
  AND tablename IN ('notifications', 'reservations', 'issued_books', 'shelf_alerts');

-- ============================================
-- VERIFICATION MESSAGE
-- ============================================
SELECT '✅ Realtime enabled for notifications!' as status;
SELECT 'Notifications will now appear instantly without page refresh!' as info;
