import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";
import { UserCog, ShieldCheck } from "lucide-react";

const RoleManager = () => {
  const [email, setEmail] = useState("");
  const [newRole, setNewRole] = useState<"student" | "librarian" | "admin">("student");
  const [loading, setLoading] = useState(false);

  const handleAssignRole = async () => {
    if (!email) {
      toast.error("Please enter an email address");
      return;
    }

    setLoading(true);

    try {
      // Find user by email
      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("id")
        .eq("email", email)
        .single();

      if (profileError || !profile) {
        toast.error("User not found with that email");
        setLoading(false);
        return;
      }

      // Check if role already exists
      const { data: existingRole } = await supabase
        .from("user_roles")
        .select("*")
        .eq("user_id", profile.id)
        .eq("role", newRole)
        .single();

      if (existingRole) {
        toast.error(`User already has the ${newRole} role`);
        setLoading(false);
        return;
      }

      // Insert new role
      const { error: roleError } = await supabase
        .from("user_roles")
        .insert({
          user_id: profile.id,
          role: newRole,
        });

      if (roleError) {
        console.error("Role assignment error:", roleError);
        toast.error("Failed to assign role. Make sure you have admin privileges.");
      } else {
        toast.success(`Successfully assigned ${newRole} role to ${email}`);
        setEmail("");
      }
    } catch (error: any) {
      console.error("Error:", error);
      toast.error("An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen gradient-subtle flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-elegant">
        <CardHeader className="text-center space-y-2">
          <div className="flex justify-center mb-4">
            <div className="gradient-primary p-4 rounded-full">
              <UserCog className="h-12 w-12 text-white" />
            </div>
          </div>
          <CardTitle className="text-3xl">Role Manager</CardTitle>
          <CardDescription>Assign librarian or admin roles to users</CardDescription>
        </CardHeader>
        
        <CardContent className="space-y-6">
          <div className="bg-warning/10 border border-warning/20 rounded-lg p-4 space-y-2">
            <div className="flex items-start gap-2">
              <ShieldCheck className="h-5 w-5 text-warning mt-0.5" />
              <div className="text-sm">
                <p className="font-medium text-warning mb-1">First Admin Setup</p>
                <p className="text-muted-foreground">
                  To create your first admin, you need to manually add the role in the database.
                </p>
              </div>
            </div>
          </div>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">User Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="user@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={loading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="role">Role to Assign</Label>
              <Select
                value={newRole}
                onValueChange={(value: any) => setNewRole(value)}
                disabled={loading}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="student">Student</SelectItem>
                  <SelectItem value="librarian">Librarian</SelectItem>
                  <SelectItem value="admin">Admin</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <Button
              onClick={handleAssignRole}
              disabled={loading}
              className="w-full"
              variant="accent"
            >
              {loading ? "Assigning..." : "Assign Role"}
            </Button>
          </div>

          <div className="bg-muted/50 rounded-lg p-4 text-sm space-y-2">
            <p className="font-medium">Quick Setup Guide:</p>
            <ol className="list-decimal list-inside space-y-1 text-muted-foreground">
              <li>Sign up with your email</li>
              <li>Go to Backend → user_roles table</li>
              <li>Click "Insert" → "Insert row"</li>
              <li>Select your user_id and role "admin"</li>
              <li>Click "Save" and refresh this page</li>
            </ol>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default RoleManager;
