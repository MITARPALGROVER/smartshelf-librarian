-- ============================================
-- ENHANCED: Bidirectional Book Detection
-- Detects when books are ADDED or REMOVED from shelf
-- ============================================

-- Drop old function and trigger
DROP TRIGGER IF EXISTS on_shelf_weight_change ON public.shelves;
DROP FUNCTION IF EXISTS detect_book_from_weight_change();

-- Create enhanced function that handles BOTH directions
CREATE OR REPLACE FUNCTION detect_book_from_weight_change()
RETURNS TRIGGER AS $$
DECLARE
  weight_diff DECIMAL(8,2);
  weight_increased BOOLEAN;
  matching_book_id UUID;
  matching_book_title TEXT;
BEGIN
  -- Calculate weight difference
  weight_diff := ABS(NEW.current_weight - OLD.current_weight);
  weight_increased := NEW.current_weight > OLD.current_weight;
  
  -- Only process if weight changed significantly (more than 10g)
  IF weight_diff > 10 THEN
  
    -- ============================================
    -- CASE 1: Weight INCREASED (Book ADDED to shelf)
    -- ============================================
    IF weight_increased THEN
      -- Find a reserved book with matching weight on this shelf
      SELECT b.id, b.title INTO matching_book_id, matching_book_title
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
        
        RAISE NOTICE 'Book ADDED to shelf %: % (book_id=%)', 
          NEW.shelf_number, matching_book_title, matching_book_id;
      END IF;
    
    -- ============================================
    -- CASE 2: Weight DECREASED (Book REMOVED from shelf)
    -- ============================================
    ELSE
      -- Find an available or issued book with matching weight on this shelf
      SELECT b.id, b.title INTO matching_book_id, matching_book_title
      FROM books b
      WHERE b.shelf_id = NEW.id
        AND b.status IN ('available', 'issued')
        AND ABS(b.weight - weight_diff) < 20  -- Within 20g tolerance
      ORDER BY 
        -- Prioritize issued books (likely being returned)
        CASE WHEN b.status = 'issued' THEN 1 ELSE 2 END,
        b.updated_at DESC
      LIMIT 1;
      
      IF matching_book_id IS NOT NULL THEN
        -- Check if this is a book being returned (was issued)
        IF (SELECT status FROM books WHERE id = matching_book_id) = 'issued' THEN
          -- Find the issued_books record and mark as returned
          UPDATE issued_books
          SET returned_at = NOW()
          WHERE book_id = matching_book_id
            AND returned_at IS NULL;
          
          -- Update book status back to available
          UPDATE books
          SET status = 'available'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book RETURNED to shelf %: % (book_id=%, auto-returned)', 
            NEW.shelf_number, matching_book_title, matching_book_id;
        ELSE
          -- Book was available and now removed (picked up after reservation)
          UPDATE books
          SET status = 'issued'
          WHERE id = matching_book_id;
          
          RAISE NOTICE 'Book PICKED UP from shelf %: % (book_id=%)', 
            NEW.shelf_number, matching_book_title, matching_book_id;
        END IF;
      END IF;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic bidirectional book detection
CREATE TRIGGER on_shelf_weight_change
  AFTER UPDATE ON public.shelves
  FOR EACH ROW
  WHEN (OLD.current_weight IS DISTINCT FROM NEW.current_weight)
  EXECUTE FUNCTION detect_book_from_weight_change();

-- ============================================
-- Test the function
-- ============================================

-- Show which books could be detected
SELECT 
  b.id,
  b.title,
  b.status,
  b.weight,
  s.shelf_number,
  s.current_weight
FROM books b
JOIN shelves s ON b.shelf_id = s.id
WHERE b.weight IS NOT NULL
ORDER BY s.shelf_number, b.status;

COMMENT ON FUNCTION detect_book_from_weight_change() IS 
'Automatically detects when books are added to or removed from shelves based on weight changes.
- Weight INCREASE: Marks reserved books as available (restocked)
- Weight DECREASE: Marks issued books as returned OR available books as issued (picked up)';
