import { supabase } from "@/integrations/supabase/client";

/**
 * Delete a user from the system (Admin only)
 * This requires admin privileges in Supabase
 * 
 * @param userId - The UUID of the user to delete
 * @returns Promise with success/error status
 */
export const deleteUser = async (userId: string) => {
  try {
    // First, delete user's related data
    // Issued books
    await supabase
      .from('issued_books')
      .delete()
      .eq('user_id', userId);

    // Reservations
    await supabase
      .from('reservations')
      .delete()
      .eq('user_id', userId);

    // Profile
    await supabase
      .from('profiles')
      .delete()
      .eq('id', userId);

    // Note: Deleting from auth.users requires admin privileges
    // This must be done via Supabase Dashboard or using service role key
    console.log('User data deleted. Delete user from auth.users via Dashboard.');
    
    return { success: true, message: 'User data deleted successfully' };
  } catch (error: any) {
    console.error('Error deleting user:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Get user details by email
 * 
 * @param email - User's email address
 * @returns User profile data
 */
export const getUserByEmail = async (email: string) => {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('email', email)
    .single();

  if (error) {
    console.error('Error fetching user:', error);
    return null;
  }

  return data;
};

/**
 * List all users with their roles
 * 
 * @returns Array of user profiles
 */
export const getAllUsers = async () => {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Error fetching users:', error);
    return [];
  }

  return data;
};
