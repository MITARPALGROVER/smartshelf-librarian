-- ================================================
-- CREATE WEIGHT SENSOR TABLE
-- Run this in Supabase SQL Editor
-- ================================================

-- Table: shelf_weight_events
CREATE TABLE IF NOT EXISTS public.shelf_weight_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shelf_id UUID NOT NULL REFERENCES public.shelves(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('pickup', 'return')),
  current_weight NUMERIC NOT NULL,
  previous_weight NUMERIC NOT NULL,
  weight_change NUMERIC NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  unlock_event_id UUID REFERENCES public.door_unlock_events(id) ON DELETE SET NULL,
  detected_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_shelf_id ON public.shelf_weight_events(shelf_id);
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_detected_at ON public.shelf_weight_events(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_shelf_weight_events_user_id ON public.shelf_weight_events(user_id);

-- Enable RLS
ALTER TABLE public.shelf_weight_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Allow ESP8266 to insert weight events" ON public.shelf_weight_events;
CREATE POLICY "Allow ESP8266 to insert weight events"
  ON public.shelf_weight_events FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow librarians to view all weight events" ON public.shelf_weight_events;
CREATE POLICY "Allow librarians to view all weight events"
  ON public.shelf_weight_events FOR SELECT
  USING (
    (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) IN ('librarian', 'admin')
  );

DROP POLICY IF EXISTS "Allow students to view their own weight events" ON public.shelf_weight_events;
CREATE POLICY "Allow students to view their own weight events"
  ON public.shelf_weight_events FOR SELECT
  USING (user_id = auth.uid());

-- Success message
DO $$
BEGIN
  RAISE NOTICE '✅ shelf_weight_events table created successfully!';
  RAISE NOTICE 'You can now test the weight sensor from the Weight tab.';
END $$;
