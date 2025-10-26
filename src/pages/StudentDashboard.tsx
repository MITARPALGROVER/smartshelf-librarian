import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { BookOpen, Calendar, Clock, CheckCircle } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

interface IssuedBook {
  id: string;
  issued_at: string;
  due_date: string;
  returned_at: string | null;
  books: {
    title: string;
    author: string;
    cover_image: string | null;
  };
}

interface Reservation {
  id: string;
  reserved_at: string;
  expires_at: string;
  status: string;
  books: {
    title: string;
    author: string;
    shelf_id: string;
    shelves: {
      shelf_number: number;
    };
  };
}

const StudentDashboard = () => {
  const { user } = useAuth();
  const [issuedBooks, setIssuedBooks] = useState<IssuedBook[]>([]);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (user) {
      fetchData();
      
      // Subscribe to real-time updates
      const reservationsChannel = supabase
        .channel('reservations-changes')
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'reservations',
            filter: `user_id=eq.${user.id}`
          },
          () => fetchData()
        )
        .subscribe();

      const issuedBooksChannel = supabase
        .channel('issued-books-changes')
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'issued_books',
            filter: `user_id=eq.${user.id}`
          },
          () => fetchData()
        )
        .subscribe();

      return () => {
        supabase.removeChannel(reservationsChannel);
        supabase.removeChannel(issuedBooksChannel);
      };
    }
  }, [user]);

  const fetchData = async () => {
    if (!user) return;

    // Fetch issued books
    const { data: booksData } = await supabase
      .from("issued_books")
      .select(`
        id,
        issued_at,
        due_date,
        returned_at,
        books (
          title,
          author,
          cover_image
        )
      `)
      .eq("user_id", user.id)
      .is("returned_at", null)
      .order("issued_at", { ascending: false });

    // Fetch active reservations
    const { data: reservationsData } = await supabase
      .from("reservations")
      .select(`
        id,
        reserved_at,
        expires_at,
        status,
        books (
          title,
          author,
          shelf_id,
          shelves (
            shelf_number
          )
        )
      `)
      .eq("user_id", user.id)
      .eq("status", "active")
      .order("reserved_at", { ascending: false });

    if (booksData) setIssuedBooks(booksData as IssuedBook[]);
    if (reservationsData) setReservations(reservationsData as Reservation[]);
    setLoading(false);
  };

  const getTimeRemaining = (expiresAt: string) => {
    const now = new Date();
    const expiry = new Date(expiresAt);
    const diff = expiry.getTime() - now.getTime();
    
    if (diff <= 0) return "Expired";
    
    const minutes = Math.floor(diff / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  if (loading) {
    return <div className="text-center">Loading...</div>;
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-4xl font-bold mb-2">Student Dashboard</h1>
        <p className="text-muted-foreground">Manage your borrowed books and reservations</p>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <BookOpen className="h-5 w-5 text-primary" />
              Currently Borrowed
            </CardTitle>
            <CardDescription>Books you have checked out</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {issuedBooks.length === 0 ? (
              <p className="text-muted-foreground text-center py-4">No books currently borrowed</p>
            ) : (
              issuedBooks.map((book) => (
                <div key={book.id} className="flex gap-4 p-4 bg-muted/50 rounded-lg">
                  <div className="flex-1">
                    <h4 className="font-semibold">{book.books.title}</h4>
                    <p className="text-sm text-muted-foreground">{book.books.author}</p>
                    <div className="flex items-center gap-2 mt-2">
                      <Calendar className="h-4 w-4 text-muted-foreground" />
                      <span className="text-xs text-muted-foreground">
                        Due {formatDistanceToNow(new Date(book.due_date), { addSuffix: true })}
                      </span>
                    </div>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-warning" />
              Active Reservations
            </CardTitle>
            <CardDescription>Books reserved and waiting for pickup</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {reservations.length === 0 ? (
              <p className="text-muted-foreground text-center py-4">No active reservations</p>
            ) : (
              reservations.map((reservation) => (
                <div key={reservation.id} className="p-4 bg-warning/10 border border-warning/20 rounded-lg">
                  <div className="flex justify-between items-start mb-2">
                    <div>
                      <h4 className="font-semibold">{reservation.books.title}</h4>
                      <p className="text-sm text-muted-foreground">{reservation.books.author}</p>
                    </div>
                    <Badge variant="outline" className="border-warning text-warning">
                      Shelf {reservation.books.shelves?.shelf_number}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-2 text-sm text-warning font-medium">
                    <Clock className="h-4 w-4" />
                    Time remaining: {getTimeRemaining(reservation.expires_at)}
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="shadow-card">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <CheckCircle className="h-5 w-5 text-success" />
            How It Works
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ol className="space-y-3 list-decimal list-inside">
            <li className="text-muted-foreground">
              Browse the book catalog and click <strong>"Reserve"</strong> on any available book
            </li>
            <li className="text-muted-foreground">
              You'll have <strong>5 minutes</strong> to pick up the book from its shelf
            </li>
            <li className="text-muted-foreground">
              When you remove the book from the shelf, our <strong>weight sensors</strong> will detect it
            </li>
            <li className="text-muted-foreground">
              The book will be automatically <strong>issued to you</strong> and the librarian will be notified
            </li>
          </ol>
        </CardContent>
      </Card>
    </div>
  );
};

export default StudentDashboard;
