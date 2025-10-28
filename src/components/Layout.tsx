import { ReactNode, useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { BookOpen, User, LogOut, LayoutDashboard, BookMarked, Menu, X } from "lucide-react";
import { signOut } from "@/lib/supabase";
import { toast } from "sonner";
import NotificationBell from "@/components/NotificationBell";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";

interface LayoutProps {
  children: ReactNode;
}

const Layout = ({ children }: LayoutProps) => {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, role, loading } = useAuth();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

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
        <div className="container mx-auto px-3 sm:px-4 lg:px-6 h-14 sm:h-16 flex items-center justify-between">
          {/* Logo - Responsive */}
          <div className="flex items-center gap-2 sm:gap-3 cursor-pointer" onClick={() => navigate("/")}>
            <div className="gradient-primary p-1.5 sm:p-2 rounded-lg">
              <BookOpen className="h-4 w-4 sm:h-5 md:h-6 text-white" />
            </div>
            <div className="hidden sm:block">
              <h1 className="font-bold text-base sm:text-lg md:text-xl">Smart Library</h1>
              <p className="text-xs text-muted-foreground hidden md:block">IoT Management System</p>
            </div>
            <h1 className="font-bold text-sm sm:hidden">Library</h1>
          </div>

          {/* Desktop Navigation */}
          <nav className="hidden md:flex items-center gap-2">
            <Button
              variant={location.pathname === "/" ? "default" : "ghost"}
              onClick={() => navigate("/")}
              size="sm"
            >
              <BookMarked className="mr-2 h-4 w-4" />
              Books
            </Button>
            <Button
              variant={location.pathname.startsWith(getDashboardRoute()) ? "default" : "ghost"}
              onClick={() => navigate(getDashboardRoute())}
              size="sm"
            >
              <LayoutDashboard className="mr-2 h-4 w-4" />
              Dashboard
            </Button>
          </nav>

          {/* Mobile + Desktop User Menu */}
          <div className="flex items-center gap-2">
            {/* Notification Bell */}
            <NotificationBell />
            
            {/* Mobile Menu Button */}
            <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
              <SheetTrigger asChild className="md:hidden">
                <Button variant="ghost" size="icon" className="h-9 w-9">
                  <Menu className="h-5 w-5" />
                </Button>
              </SheetTrigger>
              <SheetContent side="right" className="w-[280px] sm:w-[350px]">
                <SheetHeader>
                  <SheetTitle className="text-left">Navigation</SheetTitle>
                </SheetHeader>
                <div className="flex flex-col gap-4 mt-6">
                  {/* User Info */}
                  <div className="flex items-center gap-3 pb-4 border-b">
                    <Avatar className="h-12 w-12">
                      <AvatarFallback className="bg-primary text-primary-foreground text-lg">
                        {user?.email ? getInitials(user.email) : <User className="h-5 w-5" />}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1 overflow-hidden">
                      <p className="text-sm font-medium truncate">{user?.email}</p>
                      {role && (
                        <p className="text-xs text-muted-foreground capitalize">{role}</p>
                      )}
                    </div>
                  </div>

                  {/* Navigation Links */}
                  <Button
                    variant={location.pathname === "/" ? "default" : "ghost"}
                    onClick={() => {
                      navigate("/");
                      setMobileMenuOpen(false);
                    }}
                    className="w-full justify-start"
                  >
                    <BookMarked className="mr-2 h-4 w-4" />
                    Browse Books
                  </Button>
                  <Button
                    variant={location.pathname.startsWith(getDashboardRoute()) ? "default" : "ghost"}
                    onClick={() => {
                      navigate(getDashboardRoute());
                      setMobileMenuOpen(false);
                    }}
                    className="w-full justify-start"
                  >
                    <LayoutDashboard className="mr-2 h-4 w-4" />
                    Dashboard
                  </Button>
                  <Button
                    variant={location.pathname === "/testing" ? "default" : "ghost"}
                    onClick={() => {
                      navigate("/testing");
                      setMobileMenuOpen(false);
                    }}
                    className="w-full justify-start"
                  >
                    🧪 Testing Panel
                  </Button>
                  
                  {/* Librarian/Admin: Borrowed Books Report */}
                  {(role === "librarian" || role === "admin") && (
                    <Button
                      variant={location.pathname === "/reports/borrowed-books" ? "default" : "ghost"}
                      onClick={() => {
                        navigate("/reports/borrowed-books");
                        setMobileMenuOpen(false);
                      }}
                      className="w-full justify-start"
                    >
                      📊 Borrowed Books
                    </Button>
                  )}
                  
                  {/* Sign Out */}
                  <div className="pt-4 border-t">
                    <Button
                      variant="ghost"
                      onClick={handleSignOut}
                      className="w-full justify-start text-destructive hover:text-destructive hover:bg-destructive/10"
                    >
                      <LogOut className="mr-2 h-4 w-4" />
                      Sign Out
                    </Button>
                  </div>
                </div>
              </SheetContent>
            </Sheet>

            {/* Desktop User Dropdown */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild className="hidden md:flex">
                <Button variant="ghost" className="relative h-9 w-9 sm:h-10 sm:w-10 rounded-full">
                  <Avatar className="h-9 w-9 sm:h-10 sm:w-10">
                    <AvatarFallback className="bg-primary text-primary-foreground text-sm">
                      {user?.email ? getInitials(user.email) : <User className="h-4 w-4" />}
                    </AvatarFallback>
                  </Avatar>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                <DropdownMenuLabel>
                  <div className="flex flex-col space-y-1">
                    <p className="text-sm font-medium truncate">{user?.email}</p>
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
                <DropdownMenuItem onClick={() => navigate("/testing")}>
                  🧪 Testing Panel
                </DropdownMenuItem>
                {(role === "librarian" || role === "admin") && (
                  <DropdownMenuItem onClick={() => navigate("/reports/borrowed-books")}>
                    📊 Borrowed Books Report
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={handleSignOut} className="text-destructive">
                  <LogOut className="mr-2 h-4 w-4" />
                  Sign Out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </header>

      <main className="container mx-auto px-3 sm:px-4 lg:px-6 py-4 sm:py-6 md:py-8">
        {children}
      </main>
    </div>
  );
};

export default Layout;
