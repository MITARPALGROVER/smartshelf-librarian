-- Add ESP8266 IP address to shelves table for QR door control

ALTER TABLE public.shelves 
ADD COLUMN IF NOT EXISTS esp_ip_address VARCHAR(15);

COMMENT ON COLUMN public.shelves.esp_ip_address IS 'IP address of ESP8266 controlling this shelf (e.g., 192.168.1.100)';

-- Update example shelves with sample IPs (update these with your actual ESP8266 IPs)
UPDATE public.shelves 
SET esp_ip_address = '192.168.1.100'
WHERE shelf_number = 1;

UPDATE public.shelves 
SET esp_ip_address = '192.168.1.101'
WHERE shelf_number = 2;

SELECT 
  shelf_number,
  esp_ip_address,
  CASE 
    WHEN esp_ip_address IS NOT NULL THEN '✅ Configured'
    ELSE '❌ Not configured'
  END as status
FROM public.shelves
ORDER BY shelf_number;
