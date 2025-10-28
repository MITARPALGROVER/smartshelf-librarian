import { supabase } from "@/integrations/supabase/client";

export interface Notification {
  id: string;
  user_id: string;
  type: 'wrong_shelf' | 'unknown_object' | 'expired_reservation' | 'info' | 'warning' | 'error';
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
  metadata?: {
    shelf_number?: number;
    book_id?: string;
    alert_id?: string;
  };
}

/**
 * Create a notification for a user
 */
export const createNotification = async (
  userId: string,
  type: Notification['type'],
  title: string,
  message: string,
  metadata?: any
) => {
  try {
    const { data, error } = await (supabase as any)
      .from('notifications')
      .insert({
        user_id: userId,
        type,
        title,
        message,
        metadata,
        is_read: false
      })
      .select()
      .single();

    if (error) throw error;
    return { success: true, data };
  } catch (error: any) {
    console.error('Error creating notification:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Notify student about wrong pickup
 */
export const notifyStudentWrongPickup = async (
  userId: string,
  bookTitle: string,
  correctShelf: number,
  wrongShelf: number
) => {
  return await createNotification(
    userId,
    'wrong_shelf',
    '⚠️ Wrong Shelf Pickup',
    `You picked up "${bookTitle}" from Shelf ${wrongShelf}, but it should be on Shelf ${correctShelf}. Please return it to the correct shelf.`,
    { correct_shelf: correctShelf, wrong_shelf: wrongShelf }
  );
};

/**
 * Notify librarian about wrong pickup
 */
export const notifyLibrarianWrongPickup = async (
  librarianId: string,
  studentEmail: string,
  bookTitle: string,
  correctShelf: number,
  wrongShelf: number
) => {
  return await createNotification(
    librarianId,
    'wrong_shelf',
    '⚠️ Wrong Shelf Alert',
    `Student ${studentEmail} picked up "${bookTitle}" from wrong shelf. Expected: Shelf ${correctShelf}, Actual: Shelf ${wrongShelf}`,
    { student_email: studentEmail, correct_shelf: correctShelf, wrong_shelf: wrongShelf }
  );
};

/**
 * Notify about unknown object on shelf
 */
export const notifyLibrarianUnknownObject = async (
  librarianId: string,
  shelfNumber: number,
  weight: number
) => {
  return await createNotification(
    librarianId,
    'unknown_object',
    '❓ Unknown Object Detected',
    `Unknown object (${weight}g) detected on Shelf ${shelfNumber}. Please investigate.`,
    { shelf_number: shelfNumber, weight }
  );
};

/**
 * Get all librarian user IDs
 */
export const getAllLibrarians = async () => {
  const { data, error } = await (supabase as any)
    .from('profiles')
    .select('id')
    .eq('role', 'librarian');

  if (error) {
    console.error('Error fetching librarians:', error);
    return [];
  }

  return data.map((l: any) => l.id);
};

/**
 * Get all admin user IDs
 */
export const getAllAdmins = async () => {
  const { data, error } = await (supabase as any)
    .from('profiles')
    .select('id')
    .eq('role', 'admin');

  if (error) {
    console.error('Error fetching admins:', error);
    return [];
  }

  return data.map((a: any) => a.id);
};

/**
 * Mark notification as read
 */
export const markNotificationRead = async (notificationId: string) => {
  const { error } = await (supabase as any)
    .from('notifications')
    .update({ is_read: true })
    .eq('id', notificationId);

  if (error) {
    console.error('Error marking notification as read:', error);
    return { success: false, error: error.message };
  }

  return { success: true };
};

/**
 * Mark all notifications as read for a user
 */
export const markAllNotificationsRead = async (userId: string) => {
  const { error } = await (supabase as any)
    .from('notifications')
    .update({ is_read: true })
    .eq('user_id', userId)
    .eq('is_read', false);

  if (error) {
    console.error('Error marking all notifications as read:', error);
    return { success: false, error: error.message };
  }

  return { success: true };
};

/**
 * Get unread notification count
 */
export const getUnreadCount = async (userId: string) => {
  const { count, error } = await (supabase as any)
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('is_read', false);

  if (error) {
    console.error('Error getting unread count:', error);
    return 0;
  }

  return count || 0;
};
