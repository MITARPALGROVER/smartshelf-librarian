import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider } from "@/hooks/useAuth";
import useReservationExpiryService from "@/hooks/useReservationExpiryService";
import Layout from "@/components/Layout";
import ProtectedRoute from "@/components/ProtectedRoute";
import Index from "./pages/Index";
import Auth from "./pages/Auth";
import BooksPage from "./pages/BooksPage";
import StudentDashboard from "./pages/StudentDashboard";
import LibrarianDashboard from "./pages/LibrarianDashboard";
import AdminDashboard from "./pages/AdminDashboard";
import RoleManager from "./pages/RoleManager";
import BorrowedBooksReport from "./pages/BorrowedBooksReport";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

// Component to run background services
const BackgroundServices = () => {
  useReservationExpiryService();
  return null;
};

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <BackgroundServices />
          <Routes>
            <Route path="/auth" element={<Auth />} />
            <Route path="/roles" element={<RoleManager />} />
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <Layout>
                    <BooksPage />
                  </Layout>
                </ProtectedRoute>
              }
            />
            <Route
              path="/student"
              element={
                <ProtectedRoute requiredRole="student">
                  <Layout>
                    <StudentDashboard />
                  </Layout>
                </ProtectedRoute>
              }
            />
            <Route
              path="/librarian"
              element={
                <ProtectedRoute requiredRole="librarian">
                  <Layout>
                    <LibrarianDashboard />
                  </Layout>
                </ProtectedRoute>
              }
            />
            <Route
              path="/admin"
              element={
                <ProtectedRoute requiredRole="admin">
                  <Layout>
                    <AdminDashboard />
                  </Layout>
                </ProtectedRoute>
              }
            />
            <Route
              path="/reports/borrowed-books"
              element={
                <ProtectedRoute requiredRole="librarian">
                  <Layout>
                    <BorrowedBooksReport />
                  </Layout>
                </ProtectedRoute>
              }
            />
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
