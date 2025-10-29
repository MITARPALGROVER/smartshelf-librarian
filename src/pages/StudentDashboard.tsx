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
  const [currentTime, setCurrentTime] = useState(new Date());

  // Update current time every second for real-time countdown
  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentTime(new Date());
    }, 1000);

    return () => clearInterval(timer);
  }, []);

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
          (payload) => {
            console.log('🔔 Reservation change detected:', payload);
            if (payload.eventType === 'UPDATE' && payload.new.status === 'completed') {
              console.log('✅ Reservation completed - removing from list');
            }
            fetchData();
          }
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
          (payload) => {
            console.log('📖 Issued book change detected:', payload);
            if (payload.eventType === 'INSERT') {
              console.log('✅ New book issued - adding to borrowed list');
            }
            fetchData();
          }
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
    const expiry = new Date(expiresAt);
    const diff = expiry.getTime() - currentTime.getTime();
    
    if (diff <= 0) return "Expired";
    
    const minutes = Math.floor(diff / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  if (loading) {
    return <div className="text-center">Loading...</div>;
  }

  return (
    <div className="space-y-6 sm:space-y-8">
      <div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold mb-2">Student Dashboard</h1>
        <p className="text-sm sm:text-base text-muted-foreground">Manage your borrowed books and reservations</p>
      </div>

      <div className="grid gap-4 sm:gap-6 grid-cols-1 lg:grid-cols-2">
        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
              <BookOpen className="h-4 w-4 sm:h-5 sm:w-5 text-primary" />
              Currently Borrowed
            </CardTitle>
            <CardDescription className="text-xs sm:text-sm">Books you have checked out</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 sm:space-y-4">
            {issuedBooks.length === 0 ? (
              <p className="text-sm sm:text-base text-muted-foreground text-center py-4">No books currently borrowed</p>
            ) : (
              issuedBooks.map((book) => (
                <div key={book.id} className="flex gap-3 sm:gap-4 p-3 sm:p-4 bg-muted/50 rounded-lg">
                  <div className="flex-1 min-w-0">
                    <h4 className="font-semibold text-sm sm:text-base truncate">{book.books.title}</h4>
                    <p className="text-xs sm:text-sm text-muted-foreground truncate">{book.books.author}</p>
                    <div className="flex items-center gap-2 mt-2">
                      <Calendar className="h-3 w-3 sm:h-4 sm:w-4 text-muted-foreground flex-shrink-0" />
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
            <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
              <Clock className="h-4 w-4 sm:h-5 sm:w-5 text-warning" />
              Active Reservations
            </CardTitle>
            <CardDescription className="text-xs sm:text-sm">Books reserved and waiting for pickup</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 sm:space-y-4">
            {reservations.length === 0 ? (
              <p className="text-sm sm:text-base text-muted-foreground text-center py-4">No active reservations</p>
            ) : (
              reservations.map((reservation) => (
                <div key={reservation.id} className="p-3 sm:p-4 bg-warning/10 border border-warning/20 rounded-lg">
                  <div className="flex flex-col sm:flex-row justify-between items-start gap-2 mb-2">
                    <div className="flex-1 min-w-0">
                      <h4 className="font-semibold text-sm sm:text-base truncate">{reservation.books.title}</h4>
                      <p className="text-xs sm:text-sm text-muted-foreground truncate">{reservation.books.author}</p>
                    </div>
                    <Badge variant="outline" className="border-warning text-warning text-xs flex-shrink-0">
                      Shelf {reservation.books.shelves?.shelf_number}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-2 text-xs sm:text-sm text-warning font-medium">
                    <Clock className="h-3 w-3 sm:h-4 sm:w-4 flex-shrink-0" />
                    <span>Time remaining: {getTimeRemaining(reservation.expires_at)}</span>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="shadow-card">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
            <CheckCircle className="h-4 w-4 sm:h-5 sm:w-5 text-success" />
            How It Works
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ol className="space-y-2 sm:space-y-3 list-decimal list-inside text-sm sm:text-base">
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
