import { ReactNode } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { BookOpen, User, LogOut, LayoutDashboard, BookMarked, Settings } from "lucide-react";
import { signOut } from "@/lib/supabase";
import { toast } from "sonner";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";

interface LayoutProps {
  children: ReactNode;
}

const Layout = ({ children }: LayoutProps) => {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, role, loading } = useAuth();

  const handleSignOut = async () => {
    try {
      await signOut();
      toast.success("Signed out successfully");
      navigate("/auth");
    } catch (error) {
      toast.error("Error signing out");
    }
  };

  const getDashboardRoute = () => {
    if (role === "admin") return "/admin";
    if (role === "librarian") return "/librarian";
    return "/student";
  };

  const getInitials = (email: string) => {
    return email.substring(0, 2).toUpperCase();
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center gradient-subtle">
        <div className="text-center">
          <BookOpen className="h-12 w-12 text-primary animate-pulse mx-auto mb-4" />
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return children;
  }

  return (
    <div className="min-h-screen gradient-subtle">
      <header className="bg-card border-b border-border shadow-card sticky top-0 z-50">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3 cursor-pointer" onClick={() => navigate("/")}>
            <div className="gradient-primary p-2 rounded-lg">
              <BookOpen className="h-6 w-6 text-white" />
            </div>
            <div>
              <h1 className="font-bold text-xl">Smart Library</h1>
              <p className="text-xs text-muted-foreground">IoT Management System</p>
            </div>
          </div>

          <nav className="hidden md:flex items-center gap-2">
            <Button
              variant={location.pathname === "/" ? "default" : "ghost"}
              onClick={() => navigate("/")}
            >
              <BookMarked className="mr-2 h-4 w-4" />
              Books
            </Button>
            <Button
              variant={location.pathname.startsWith(getDashboardRoute()) ? "default" : "ghost"}
              onClick={() => navigate(getDashboardRoute())}
            >
              <LayoutDashboard className="mr-2 h-4 w-4" />
              Dashboard
            </Button>
          </nav>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="relative h-10 w-10 rounded-full">
                <Avatar>
                  <AvatarFallback className="bg-primary text-primary-foreground">
                    {user?.email ? getInitials(user.email) : <User className="h-4 w-4" />}
                  </AvatarFallback>
                </Avatar>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>
                <div className="flex flex-col space-y-1">
                  <p className="text-sm font-medium">{user?.email}</p>
                  {role && (
                    <p className="text-xs text-muted-foreground capitalize">{role}</p>
                  )}
                </div>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => navigate(getDashboardRoute())}>
                <LayoutDashboard className="mr-2 h-4 w-4" />
                Dashboard
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => navigate("/")}>
                <BookMarked className="mr-2 h-4 w-4" />
                Browse Books
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={handleSignOut} className="text-destructive">
                <LogOut className="mr-2 h-4 w-4" />
                Sign Out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </header>

      <main className="container mx-auto px-4 py-8">
        {children}
      </main>
    </div>
  );
};

export default Layout;
