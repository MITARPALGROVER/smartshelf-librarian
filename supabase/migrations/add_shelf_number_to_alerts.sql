-- ============================================
-- ADD SHELF_NUMBER COLUMN TO SHELF_ALERTS
-- Fixes: column "shelf_number" does not exist
-- ============================================

-- Add shelf_number column to shelf_alerts table
ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS shelf_number INTEGER;

-- Add book_id column if it doesn't exist (used in realistic_library_system.sql)
ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS book_id UUID REFERENCES public.books(id) ON DELETE SET NULL;

-- Add detected_weight column if it doesn't exist (renamed from weight_change)
ALTER TABLE public.shelf_alerts 
ADD COLUMN IF NOT EXISTS detected_weight DECIMAL(8,2);

-- Update shelf_number from shelf_id for existing records
UPDATE public.shelf_alerts sa
SET shelf_number = s.shelf_number
FROM public.shelves s
WHERE sa.shelf_id = s.id
  AND sa.shelf_number IS NULL;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_shelf_alerts_shelf_number 
  ON public.shelf_alerts(shelf_number);

-- ============================================
-- VERIFICATION
-- ============================================
SELECT '✅ shelf_alerts table structure updated!' as status;

-- Show the table structure
SELECT 
  column_name, 
  data_type, 
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'shelf_alerts'
ORDER BY ordinal_position;
