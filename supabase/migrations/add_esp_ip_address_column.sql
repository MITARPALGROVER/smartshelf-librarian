-- Add esp_ip_address column to shelves table
-- This stores the IP address of the ESP8266 connected to each shelf

ALTER TABLE shelves 
ADD COLUMN IF NOT EXISTS esp_ip_address TEXT;

COMMENT ON COLUMN shelves.esp_ip_address IS 'IP address of the ESP8266 device connected to this shelf';

-- Optional: Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_shelves_esp_ip ON shelves(esp_ip_address) WHERE esp_ip_address IS NOT NULL;
