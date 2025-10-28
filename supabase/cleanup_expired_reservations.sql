-- Quick Fix Script: Clean Up Expired Reservations NOW
-- Run this immediately in Supabase SQL Editor to fix existing data

-- 1. Show current problem (expired reservations still marked as active)
SELECT 
  r.id,
  r.user_id,
  b.title as book_title,
  r.status,
  r.expires_at,
  CASE 
    WHEN r.expires_at < NOW() THEN '❌ EXPIRED'
    ELSE '✅ ACTIVE'
  END as actual_status,
  NOW() - r.expires_at as time_expired_ago
FROM reservations r
JOIN books b ON r.book_id = b.id
WHERE r.status = 'active'
  AND r.expires_at < NOW()
ORDER BY r.expires_at DESC;

-- 2. Update all expired reservations to 'expired' status
UPDATE reservations
SET 
  status = 'expired',
  updated_at = NOW()
WHERE status = 'active'
  AND expires_at < NOW();

-- 3. Free up books that have no active reservations
UPDATE books
SET 
  status = 'available',
  updated_at = NOW()
WHERE status = 'reserved'
  AND id NOT IN (
    SELECT book_id
    FROM reservations
    WHERE status = 'active'
      AND expires_at >= NOW()
  );

-- 4. Verify the fix
SELECT 
  'Total reservations' as metric,
  COUNT(*) as count
FROM reservations
UNION ALL
SELECT 
  'Active reservations',
  COUNT(*)
FROM reservations
WHERE status = 'active'
UNION ALL
SELECT 
  'Expired reservations',
  COUNT(*)
FROM reservations
WHERE status = 'expired'
UNION ALL
SELECT 
  'Available books',
  COUNT(*)
FROM books
WHERE status = 'available'
UNION ALL
SELECT 
  'Reserved books',
  COUNT(*)
FROM books
WHERE status = 'reserved';

-- 5. Show any remaining issues (should be empty)
SELECT 
  'ISSUE: Expired reservation still active' as problem,
  COUNT(*) as count
FROM reservations
WHERE status = 'active'
  AND expires_at < NOW()
UNION ALL
SELECT 
  'ISSUE: Book reserved with no active reservation',
  COUNT(*)
FROM books
WHERE status = 'reserved'
  AND id NOT IN (
    SELECT book_id
    FROM reservations
    WHERE status = 'active'
      AND expires_at >= NOW()
  );
