import { ReactNode, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { UserRole } from "@/lib/supabase";

interface ProtectedRouteProps {
  children: ReactNode;
  requiredRole?: UserRole;
}

const ProtectedRoute = ({ children, requiredRole }: ProtectedRouteProps) => {
  const navigate = useNavigate();
  const { user, role, loading } = useAuth();

  useEffect(() => {
    if (!loading) {
      if (!user) {
        navigate("/auth");
      } else if (requiredRole && role !== requiredRole) {
        // Redirect to appropriate dashboard if user doesn't have required role
        if (role === "admin") {
          navigate("/admin");
        } else if (role === "librarian") {
          navigate("/librarian");
        } else {
          navigate("/student");
        }
      }
    }
  }, [user, role, loading, requiredRole, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null;
  }

  if (requiredRole && role !== requiredRole) {
    return null;
  }

  return <>{children}</>;
};

export default ProtectedRoute;
