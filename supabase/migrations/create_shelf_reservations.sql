-- Shelf Reservations Table
-- Tracks the 1-minute window when door is unlocked as active reservations

CREATE TABLE IF NOT EXISTS shelf_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unlock_event_id UUID NOT NULL REFERENCES door_unlock_events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'expired')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,
  
  CONSTRAINT unique_unlock_reservation UNIQUE(unlock_event_id)
);

-- Indexes
CREATE INDEX idx_shelf_reservations_user ON shelf_reservations(user_id);
CREATE INDEX idx_shelf_reservations_status ON shelf_reservations(status);
CREATE INDEX idx_shelf_reservations_expires ON shelf_reservations(expires_at);

-- RLS Policies
ALTER TABLE shelf_reservations ENABLE ROW LEVEL SECURITY;

-- Users can see their own reservations
CREATE POLICY "Users can view own reservations"
  ON shelf_reservations FOR SELECT
  USING (user_id = auth.uid());

-- Librarians can see all reservations
CREATE POLICY "Librarians can view all reservations"
  ON shelf_reservations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid() AND role = 'librarian'
    )
  );

-- ESP8266 can insert reservations (via service role or anon with proper function)
CREATE POLICY "Allow ESP8266 to create reservations"
  ON shelf_reservations FOR INSERT
  WITH CHECK (true);

-- ESP8266 can update reservations
CREATE POLICY "Allow ESP8266 to update reservations"
  ON shelf_reservations FOR UPDATE
  USING (true);

-- Auto-expire function
CREATE OR REPLACE FUNCTION expire_old_reservations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE shelf_reservations
  SET status = 'expired'
  WHERE status = 'active'
    AND expires_at < NOW();
END;
$$;

COMMENT ON TABLE shelf_reservations IS 'Tracks active 1-minute reservation windows when shelf door is unlocked';
COMMENT ON COLUMN shelf_reservations.status IS 'active=door unlocked, completed=book taken/returned, expired=timeout';
