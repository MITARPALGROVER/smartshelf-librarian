import { supabase } from "@/integrations/supabase/client";
import type { User, Session } from "@supabase/supabase-js";

export type UserRole = "student" | "librarian" | "admin";

export interface AuthUser extends User {
  role?: UserRole;
}

export const getUserRole = async (userId: string): Promise<UserRole | null> => {
  const { data, error } = await supabase
    .from("user_roles")
    .select("role")
    .eq("user_id", userId)
    .single();

  if (error || !data) {
    console.error("Error fetching user role:", error);
    return null;
  }

  return data.role as UserRole;
};

export const getUserProfile = async (userId: string) => {
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userId)
    .single();

  if (error) {
    console.error("Error fetching profile:", error);
    return null;
  }

  return data;
};

export const signOut = async () => {
  const { error } = await supabase.auth.signOut();
  if (error) {
    console.error("Error signing out:", error);
    throw error;
  }
};
