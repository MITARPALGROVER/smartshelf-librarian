-- ============================================
-- ESP8266 Smart Shelf Database Configuration
-- ============================================

-- 1. Enable ESP8266 to update shelf weights
-- This allows the anonymous API key (used by ESP8266) to update shelf data
CREATE POLICY "ESP8266 can update shelf weight and timestamp"
  ON public.shelves FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- 2. Create a function to auto-detect books based on weight
CREATE OR REPLACE FUNCTION detect_book_from_weight_change()
RETURNS TRIGGER AS $$
DECLARE
  weight_diff DECIMAL(8,2);
  matching_book_id UUID;
BEGIN
  -- Calculate weight difference
  weight_diff := ABS(NEW.current_weight - OLD.current_weight);
  
  -- If weight increased significantly (book added)
  IF weight_diff > 10 THEN
    -- Find a reserved book with matching weight on this shelf
    SELECT b.id INTO matching_book_id
    FROM books b
    WHERE b.shelf_id = NEW.id
      AND b.status = 'reserved'
      AND ABS(b.weight - weight_diff) < 20  -- Within 20g tolerance
    LIMIT 1;
    
    IF matching_book_id IS NOT NULL THEN
      -- Update book status to available (ready for pickup)
      UPDATE books 
      SET status = 'available'
      WHERE id = matching_book_id;
      
      -- Log the detection
      RAISE NOTICE 'Book detected on shelf %: book_id=%', NEW.shelf_number, matching_book_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create trigger for automatic book detection
CREATE TRIGGER on_shelf_weight_change
  AFTER UPDATE ON public.shelves
  FOR EACH ROW
  WHEN (OLD.current_weight IS DISTINCT FROM NEW.current_weight)
  EXECUTE FUNCTION detect_book_from_weight_change();

-- 4. Create a view for shelf monitoring (optional but useful)
CREATE OR REPLACE VIEW shelf_status AS
SELECT 
  s.id,
  s.shelf_number,
  s.current_weight,
  s.max_weight,
  s.is_active,
  s.last_sensor_update,
  ROUND((s.current_weight / s.max_weight * 100)::numeric, 2) as capacity_percent,
  COUNT(b.id) as book_count,
  ARRAY_AGG(b.title) FILTER (WHERE b.title IS NOT NULL) as books_on_shelf
FROM shelves s
LEFT JOIN books b ON b.shelf_id = s.id
GROUP BY s.id, s.shelf_number, s.current_weight, s.max_weight, s.is_active, s.last_sensor_update;

-- 5. Grant select on the view
GRANT SELECT ON shelf_status TO anon, authenticated;

-- 6. Add index for better performance
CREATE INDEX IF NOT EXISTS idx_books_shelf_status ON books(shelf_id, status);
CREATE INDEX IF NOT EXISTS idx_shelves_last_update ON shelves(last_sensor_update DESC);

-- ============================================
-- Query to get shelf UUID for ESP8266 config
-- ============================================
-- Run this to get your shelf IDs:
SELECT 
  id as shelf_uuid,
  shelf_number,
  current_weight,
  last_sensor_update
FROM shelves
ORDER BY shelf_number;

-- ============================================
-- Test queries
-- ============================================

-- View current shelf status
SELECT * FROM shelf_status;

-- View recent shelf updates
SELECT 
  shelf_number,
  current_weight,
  last_sensor_update,
  NOW() - last_sensor_update as time_since_update
FROM shelves
ORDER BY last_sensor_update DESC;

-- Monitor weight changes in real-time (run this and add/remove books)
SELECT 
  shelf_number,
  current_weight,
  to_char(last_sensor_update, 'HH24:MI:SS') as last_update
FROM shelves
WHERE last_sensor_update > NOW() - INTERVAL '1 minute'
ORDER BY last_sensor_update DESC;
