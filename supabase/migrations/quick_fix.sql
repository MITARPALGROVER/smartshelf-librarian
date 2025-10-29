-- ============================================
-- COMPLETE FIX - Run Everything At Once
-- This will fix ALL issues
-- ============================================

-- Step 1: Enable Realtime
DO $$ 
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE reservations;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE issued_books;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE books;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  
  RAISE NOTICE '✅ Realtime enabled for all tables';
END $$;

-- Step 2: Verify what we have now
SELECT 
  'Triggers Installed: ' || COUNT(*)::text as status
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_notify_book_reserved',
  'trigger_notify_book_issued',
  'on_shelf_weight_change'
);

-- If you see "0", you MUST run all_in_one_complete_setup.sql next!

-- Step 3: Show current state
SELECT 
  CASE 
    WHEN COUNT(*) = 3 THEN '✅ ALL TRIGGERS EXIST - System is ready!'
    WHEN COUNT(*) = 0 THEN '❌ NO TRIGGERS - Run all_in_one_complete_setup.sql NOW'
    ELSE '⚠️ PARTIAL SETUP - Run all_in_one_complete_setup.sql NOW'
  END as diagnosis
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_notify_book_reserved',
  'trigger_notify_book_issued',
  'on_shelf_weight_change'
);
