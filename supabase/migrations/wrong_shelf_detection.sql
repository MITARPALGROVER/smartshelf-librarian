-- ============================================
-- ENHANCED: Wrong Shelf Detection & Alerts
-- Detects when books are placed on incorrect shelves
-- ============================================

-- Create a table to log misplaced books
CREATE TABLE IF NOT EXISTS public.shelf_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shelf_id UUID REFERENCES public.shelves(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL,
  message TEXT NOT NULL,
  weight_change DECIMAL(8,2),
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.shelf_alerts ENABLE ROW LEVEL SECURITY;

-- Allow librarians and admins to view alerts
CREATE POLICY "Librarians can view shelf alerts"
  ON public.shelf_alerts FOR SELECT
  USING (
    public.has_role(auth.uid(), 'librarian') OR 
    public.has_role(auth.uid(), 'admin')
  );

-- Allow system to insert alerts
CREATE POLICY "System can create alerts"
  ON public.shelf_alerts FOR INSERT
  WITH CHECK (true);

-- Allow librarians to resolve alerts
CREATE POLICY "Librarians can resolve alerts"
  ON public.shelf_alerts FOR UPDATE
  USING (
    public.has_role(auth.uid(), 'librarian') OR 
    public.has_role(auth.uid(), 'admin')
  );

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_shelf_alerts_unresolved 
  ON public.shelf_alerts(shelf_id, detected_at DESC) 
  WHERE resolved_at IS NULL;

-- ============================================
-- Enhanced Detection Function with Alerts
-- ============================================

DROP TRIGGER IF EXISTS on_shelf_weight_change ON public.shelves;
DROP FUNCTION IF EXISTS detect_book_from_weight_change();

CREATE OR REPLACE FUNCTION detect_book_from_weight_change()
RETURNS TRIGGER AS $$
DECLARE
  weight_diff DECIMAL(8,2);
  weight_increased BOOLEAN;
  matching_book_id UUID;
  matching_book_title TEXT;
  matching_book_shelf_id UUID;
  wrong_shelf_book_id UUID;
  wrong_shelf_book_title TEXT;
  correct_shelf_number INTEGER;
BEGIN
  -- Calculate weight difference
  weight_diff := ABS(NEW.current_weight - OLD.current_weight);
  weight_increased := NEW.current_weight > OLD.current_weight;
  
  -- Only process significant weight changes
  IF weight_diff > 10 THEN
  
    -- ============================================
    -- STEP 1: Try to find matching book on THIS shelf
    -- ============================================
    IF weight_increased THEN
      -- Weight increased - looking for issued/reserved books
      SELECT b.id, b.title, b.shelf_id 
      INTO matching_book_id, matching_book_title, matching_book_shelf_id
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('reserved', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
    ELSE
      -- Weight decreased - looking for available/issued books
      SELECT b.id, b.title, b.shelf_id 
      INTO matching_book_id, matching_book_title, matching_book_shelf_id
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('available', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
    END IF;
    
    -- ============================================
    -- STEP 2: If no match, check OTHER shelves (wrong shelf detection)
    -- ============================================
    IF matching_book_id IS NULL AND weight_increased THEN
      -- Look for issued/reserved books on ANY other shelf
      SELECT b.id, b.title, s.shelf_number
      INTO wrong_shelf_book_id, wrong_shelf_book_title, correct_shelf_number
      FROM books b
      JOIN shelves s ON b.shelf_id = s.id
      WHERE b.shelf_id != NEW.id  -- Different shelf
        AND b.status IN ('reserved', 'issued')
        AND ABS(b.weight - weight_diff) < 20
      ORDER BY 
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
      
      IF wrong_shelf_book_id IS NOT NULL THEN
        -- Book placed on WRONG shelf!
        INSERT INTO shelf_alerts (
          shelf_id,
          alert_type,
          message,
          weight_change
        ) VALUES (
          NEW.id,
          'wrong_shelf',
          format('Book "%s" (belongs to Shelf %s) may have been placed on Shelf %s. Weight: %sg', 
            wrong_shelf_book_title, 
            correct_shelf_number, 
            NEW.shelf_number,
            weight_diff
          ),
          weight_diff
        );
        
        RAISE NOTICE 'ALERT: Book "%" from Shelf % placed on Shelf %!', 
          wrong_shelf_book_title, correct_shelf_number, NEW.shelf_number;
      ELSE
        -- Unknown object added (not a registered book)
        INSERT INTO shelf_alerts (
          shelf_id,
          alert_type,
          message,
          weight_change
        ) VALUES (
          NEW.id,
          'unknown_object',
          format('Unknown object (%sg) added to Shelf %s. No matching book found.', 
            weight_diff,
            NEW.shelf_number
          ),
          weight_diff
        );
        
        RAISE NOTICE 'ALERT: Unknown object (%g) added to Shelf %', 
          weight_diff, NEW.shelf_number;
      END IF;
    END IF;
    
    -- ============================================
    -- STEP 3: Process detected book (if found on correct shelf)
    -- ============================================
    IF matching_book_id IS NOT NULL THEN
      IF weight_increased THEN
        -- Book returned
        IF (SELECT status FROM books WHERE id = matching_book_id) = 'issued' THEN
          UPDATE issued_books
          SET returned_at = NOW()
          WHERE book_id = matching_book_id
            AND returned_at IS NULL;
          
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book RETURNED to Shelf %: % (auto-returned)', 
            NEW.shelf_number, matching_book_title;
        ELSE
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book ADDED to Shelf %: %', 
            NEW.shelf_number, matching_book_title;
        END IF;
      ELSE
        -- Book removed
        IF (SELECT status FROM books WHERE id = matching_book_id) = 'available' THEN
          UPDATE books
          SET status = 'issued'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book PICKED UP from Shelf %: %', 
            NEW.shelf_number, matching_book_title;
        END IF;
      END IF;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger
CREATE TRIGGER on_shelf_weight_change
  AFTER UPDATE ON public.shelves
  FOR EACH ROW
  WHEN (OLD.current_weight IS DISTINCT FROM NEW.current_weight)
  EXECUTE FUNCTION detect_book_from_weight_change();

-- ============================================
-- Helper Functions
-- ============================================

-- Function to get unresolved alerts
CREATE OR REPLACE FUNCTION get_unresolved_shelf_alerts()
RETURNS TABLE (
  alert_id UUID,
  shelf_number INTEGER,
  alert_type TEXT,
  message TEXT,
  weight_change DECIMAL(8,2),
  detected_at TIMESTAMPTZ,
  minutes_ago INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    sa.id,
    s.shelf_number,
    sa.alert_type,
    sa.message,
    sa.weight_change,
    sa.detected_at,
    EXTRACT(EPOCH FROM (NOW() - sa.detected_at))::INTEGER / 60 AS minutes_ago
  FROM shelf_alerts sa
  JOIN shelves s ON sa.shelf_id = s.id
  WHERE sa.resolved_at IS NULL
  ORDER BY sa.detected_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve alert
CREATE OR REPLACE FUNCTION resolve_shelf_alert(alert_id UUID, resolver_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE shelf_alerts
  SET 
    resolved_at = NOW(),
    resolved_by = resolver_id
  WHERE id = alert_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_unresolved_shelf_alerts() TO authenticated;
GRANT EXECUTE ON FUNCTION resolve_shelf_alert(UUID, UUID) TO authenticated;

-- ============================================
-- Useful Queries
-- ============================================

-- View all unresolved alerts
SELECT * FROM get_unresolved_shelf_alerts();

-- View alert history
SELECT 
  s.shelf_number,
  sa.alert_type,
  sa.message,
  sa.detected_at,
  sa.resolved_at,
  p.full_name as resolved_by
FROM shelf_alerts sa
JOIN shelves s ON sa.shelf_id = s.id
LEFT JOIN profiles p ON sa.resolved_by = p.id
ORDER BY sa.detected_at DESC
LIMIT 20;

-- Count alerts by type
SELECT 
  alert_type,
  COUNT(*) as total_alerts,
  COUNT(*) FILTER (WHERE resolved_at IS NULL) as unresolved
FROM shelf_alerts
GROUP BY alert_type;

COMMENT ON TABLE shelf_alerts IS 
'Stores alerts for misplaced books, unknown objects, and other shelf anomalies';

COMMENT ON FUNCTION detect_book_from_weight_change() IS 
'Enhanced bidirectional detection with wrong shelf alerts and unknown object detection';
