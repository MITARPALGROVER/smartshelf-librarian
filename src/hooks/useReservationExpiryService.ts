import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";

/**
 * Background service that checks for expired reservations every minute
 * This runs in the background and expires reservations automatically
 */
export const useReservationExpiryService = () => {
  useEffect(() => {
    // Function to expire old reservations
    const checkExpiredReservations = async () => {
      console.log('🔍 Checking for expired reservations...');
      
      try {
        // Call the database function to expire old reservations
        const { error } = await (supabase as any).rpc('expire_old_reservations');
        
        if (error) {
          console.error('Error expiring reservations:', error);
        }
        
        // Also call notify function
        const { error: notifyError } = await (supabase as any).rpc('notify_expired_reservations');
        
        if (notifyError) {
          console.error('Error notifying expired reservations:', notifyError);
        }
      } catch (err) {
        console.error('Exception in expiry check:', err);
      }
    };

    // Run immediately on mount
    checkExpiredReservations();

    // Run every 60 seconds (1 minute)
    const interval = setInterval(checkExpiredReservations, 60000);

    console.log('✅ Reservation expiry service started (runs every 60 seconds)');

    // Cleanup on unmount
    return () => {
      clearInterval(interval);
      console.log('⏹️ Reservation expiry service stopped');
    };
  }, []);
};

export default useReservationExpiryService;
