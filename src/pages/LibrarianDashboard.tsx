import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { BookOpen, Users, Clock, CheckCircle, Activity } from "lucide-react";
import { formatDistanceToNow } from "date-fns";
import { toast } from "sonner";

interface IssuedBook {
  id: string;
  issued_at: string;
  due_date: string;
  returned_at: string | null;
  books: {
    title: string;
    author: string;
  };
  profiles: {
    full_name: string;
    email: string;
    student_id: string | null;
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
    shelves: {
      shelf_number: number;
    };
  };
  profiles: {
    full_name: string;
    email: string;
  };
}

const LibrarianDashboard = () => {
  const [issuedBooks, setIssuedBooks] = useState<IssuedBook[]>([]);
  const [activeReservations, setActiveReservations] = useState<Reservation[]>([]);
  const [stats, setStats] = useState({
    totalIssued: 0,
    activeReservations: 0,
    overdueBooks: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchData();
    
    // Subscribe to real-time updates
    const reservationsChannel = supabase
      .channel('all-reservations')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'reservations'
        },
        () => fetchData()
      )
      .subscribe();

    const issuedBooksChannel = supabase
      .channel('all-issued-books')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'issued_books'
        },
        () => fetchData()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(reservationsChannel);
      supabase.removeChannel(issuedBooksChannel);
    };
  }, []);

  const fetchData = async () => {
    // Fetch all currently issued books (not returned)
    const { data: booksData } = await supabase
      .from("issued_books")
      .select(`
        id,
        issued_at,
        due_date,
        returned_at,
        books (
          title,
          author
        ),
        profiles (
          full_name,
          email,
          student_id
        )
      `)
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
          shelves (
            shelf_number
          )
        ),
        profiles (
          full_name,
          email
        )
      `)
      .eq("status", "active")
      .order("reserved_at", { ascending: false });

    if (booksData) {
      setIssuedBooks(booksData as IssuedBook[]);
      
      // Calculate overdue books
      const now = new Date();
      const overdue = booksData.filter(book => 
        new Date(book.due_date) < now && !book.returned_at
      ).length;

      setStats({
        totalIssued: booksData.length,
        activeReservations: reservationsData?.length || 0,
        overdueBooks: overdue,
      });
    }

    if (reservationsData) {
      setActiveReservations(reservationsData as Reservation[]);
    }

    setLoading(false);
  };

  const handleMarkReturned = async (bookId: string) => {
    const { error } = await supabase
      .from("issued_books")
      .update({ returned_at: new Date().toISOString() })
      .eq("id", bookId);

    if (error) {
      toast.error("Failed to mark book as returned");
    } else {
      toast.success("Book marked as returned");
      fetchData();
    }
  };

  if (loading) {
    return <div className="text-center">Loading...</div>;
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-4xl font-bold mb-2">Librarian Dashboard</h1>
        <p className="text-muted-foreground">Monitor all library activities and manage book returns</p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="shadow-card">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Currently Issued</CardTitle>
            <BookOpen className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.totalIssued}</div>
            <p className="text-xs text-muted-foreground">Books out for reading</p>
          </CardContent>
        </Card>

        <Card className="shadow-card">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Reservations</CardTitle>
            <Clock className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.activeReservations}</div>
            <p className="text-xs text-muted-foreground">Waiting for pickup</p>
          </CardContent>
        </Card>

        <Card className="shadow-card">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Overdue Books</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">{stats.overdueBooks}</div>
            <p className="text-xs text-muted-foreground">Need attention</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-warning" />
              Active Reservations
            </CardTitle>
            <CardDescription>Students waiting to pick up books</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {activeReservations.length === 0 ? (
              <p className="text-muted-foreground text-center py-4">No active reservations</p>
            ) : (
              activeReservations.map((reservation) => (
                <div key={reservation.id} className="p-4 bg-warning/10 border border-warning/20 rounded-lg">
                  <div className="flex justify-between items-start mb-2">
                    <div>
                      <h4 className="font-semibold">{reservation.books.title}</h4>
                      <p className="text-sm text-muted-foreground">{reservation.books.author}</p>
                      <p className="text-sm text-muted-foreground mt-1">
                        Student: {reservation.profiles.full_name}
                      </p>
                    </div>
                    <Badge variant="outline" className="border-warning text-warning">
                      Shelf {reservation.books.shelves?.shelf_number}
                    </Badge>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Expires {formatDistanceToNow(new Date(reservation.expires_at), { addSuffix: true })}
                  </p>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <BookOpen className="h-5 w-5 text-primary" />
              Currently Issued Books
            </CardTitle>
            <CardDescription>Books checked out by students</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4 max-h-[500px] overflow-y-auto">
            {issuedBooks.length === 0 ? (
              <p className="text-muted-foreground text-center py-4">No books currently issued</p>
            ) : (
              issuedBooks.map((book) => {
                const isOverdue = new Date(book.due_date) < new Date();
                return (
                  <div
                    key={book.id}
                    className={`p-4 rounded-lg border ${
                      isOverdue ? "bg-destructive/10 border-destructive/20" : "bg-muted/50"
                    }`}
                  >
                    <div className="flex justify-between items-start mb-2">
                      <div className="flex-1">
                        <h4 className="font-semibold">{book.books.title}</h4>
                        <p className="text-sm text-muted-foreground">{book.books.author}</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          {book.profiles.full_name}
                          {book.profiles.student_id && ` (${book.profiles.student_id})`}
                        </p>
                        <p className={`text-xs mt-1 ${isOverdue ? "text-destructive font-medium" : "text-muted-foreground"}`}>
                          Due {formatDistanceToNow(new Date(book.due_date), { addSuffix: true })}
                          {isOverdue && " - OVERDUE"}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        variant="success"
                        onClick={() => handleMarkReturned(book.id)}
                      >
                        <CheckCircle className="mr-1 h-4 w-4" />
                        Return
                      </Button>
                    </div>
                  </div>
                );
              })
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

export default LibrarianDashboard;
