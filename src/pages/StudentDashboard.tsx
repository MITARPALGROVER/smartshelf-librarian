import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { BookOpen, Calendar, QrCode } from "lucide-react";
import { formatDistanceToNow } from "date-fns";
import { QRScanner } from "@/components/QRScanner";
import { toast } from "sonner";

interface Book {
  id: string;
  title: string;
  author: string;
  cover_image: string | null;
  status: string;
  shelf_id: string;
  shelves: {
    shelf_number: number;
    id: string;
  } | null;
}

interface IssuedBook {
  id: string;
  book_id: string;
  issued_at: string;
  due_date: string;
  returned_at: string | null;
  books: {
    id: string;
    title: string;
    author: string;
    cover_image: string | null;
  };
}

const StudentDashboard = () => {
  const { user } = useAuth();
  const [books, setBooks] = useState<Book[]>([]);
  const [issuedBooks, setIssuedBooks] = useState<IssuedBook[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedBook, setSelectedBook] = useState<Book | null>(null);
  const [showQRScanner, setShowQRScanner] = useState(false);

  useEffect(() => {
    if (user) {
      fetchData();
      
      // Subscribe to real-time updates for issued books
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

      // Subscribe to real-time updates for books table (status changes)
      const booksChannel = supabase
        .channel('books-changes')
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'books'
          },
          (payload) => {
            console.log('📚 Book status changed:', payload);
            fetchData();
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(issuedBooksChannel);
        supabase.removeChannel(booksChannel);
      };
    }
  }, [user]);

  const fetchData = async () => {
    if (!user) return;

    // Fetch issued books first
    const { data: issuedBooksData } = await supabase
      .from("issued_books")
      .select(`
        id,
        issued_at,
        due_date,
        returned_at,
        book_id,
        books (
          id,
          title,
          author,
          cover_image
        )
      `)
      .eq("user_id", user.id)
      .is("returned_at", null)
      .order("issued_at", { ascending: false });

    // Get IDs of books currently issued to this user
    const issuedBookIds = issuedBooksData?.map(ib => ib.book_id) || [];

    // Fetch available books (exclude books issued to this user)
    const { data: availableBooksData } = await supabase
      .from("books")
      .select(`
        id,
        title,
        author,
        cover_image,
        status,
        shelf_id,
        shelves (
          shelf_number,
          id
        )
      `)
      .eq("status", "available")
      .order("title", { ascending: true });

    // Filter out any books that are in issued list (double-check)
    const filteredBooks = availableBooksData?.filter(
      book => !issuedBookIds.includes(book.id)
    ) || [];

    if (filteredBooks) setBooks(filteredBooks as Book[]);
    if (issuedBooksData) setIssuedBooks(issuedBooksData as IssuedBook[]);
    setLoading(false);
  };

  const handleScanClick = (book: Book) => {
    if (!book.shelves) {
      toast.error("Shelf information not available");
      return;
    }
    setSelectedBook(book);
    setShowQRScanner(true);
  };

  const handleQRSuccess = () => {
    setShowQRScanner(false);
    setSelectedBook(null);
    toast.success("Door unlocked! Pick up your book within 1 minute.");
  };

  if (loading) {
    return <div className="text-center">Loading...</div>;
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold mb-2">📚 Available Books</h1>
        <p className="text-sm sm:text-base text-muted-foreground">Scan QR code to unlock shelf and pickup book</p>
      </div>

      {/* Available Books Grid */}
      <div className="grid gap-3 sm:gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {books.map((book) => (
          <Card key={book.id} className="overflow-hidden">
            {book.cover_image && (
              <div className="h-40 sm:h-48 overflow-hidden bg-muted">
                <img
                  src={book.cover_image}
                  alt={book.title}
                  className="w-full h-full object-cover"
                />
              </div>
            )}
            <CardContent className="p-3 sm:p-4">
              <h3 className="font-semibold text-base sm:text-lg mb-1 line-clamp-2">{book.title}</h3>
              <p className="text-xs sm:text-sm text-muted-foreground mb-3 line-clamp-1">{book.author}</p>
              <div className="flex items-center justify-between mb-3 gap-2">
                <Badge variant="outline" className="text-xs shrink-0">
                  📍 Shelf {book.shelves?.shelf_number || "N/A"}
                </Badge>
                <Badge variant="default" className="text-xs bg-green-500 shrink-0">
                  Available
                </Badge>
              </div>
              <Button
                className="w-full text-sm"
                size="sm"
                onClick={() => handleScanClick(book)}
              >
                <QrCode className="w-4 h-4 mr-2" />
                Scan QR to Pickup
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>

      {books.length === 0 && !loading && (
        <Card className="p-6 sm:p-8 text-center">
          <p className="text-sm sm:text-base text-muted-foreground">No books available at the moment</p>
        </Card>
      )}

      {/* Currently Borrowed Books */}
      <Card>
        <CardHeader className="p-4 sm:p-6">
          <CardTitle className="flex items-center gap-2 text-lg sm:text-xl">
            <BookOpen className="h-4 w-4 sm:h-5 sm:w-5" />
            Currently Borrowed
          </CardTitle>
          <CardDescription className="text-xs sm:text-sm">Books you have checked out</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2 sm:space-y-3 p-4 sm:p-6 pt-0">
          {issuedBooks.length === 0 ? (
            <p className="text-xs sm:text-sm text-muted-foreground text-center py-4">
              No books currently borrowed
            </p>
          ) : (
            issuedBooks.map((book) => (
              <div key={book.id} className="flex gap-3 sm:gap-4 p-3 sm:p-4 bg-muted/50 rounded-lg">
                <div className="flex-1 min-w-0">
                  <h4 className="font-semibold text-sm sm:text-base line-clamp-1">{book.books.title}</h4>
                  <p className="text-xs sm:text-sm text-muted-foreground line-clamp-1">{book.books.author}</p>
                  <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
                    <Calendar className="h-3 w-3 shrink-0" />
                    <span className="truncate">Due {formatDistanceToNow(new Date(book.due_date), { addSuffix: true })}</span>
                  </div>
                </div>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      {/* QR Scanner Dialog */}
      <Dialog open={showQRScanner} onOpenChange={setShowQRScanner}>
        <DialogContent className="w-[95vw] max-w-md sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="text-base sm:text-lg">Scan Shelf QR Code</DialogTitle>
            <DialogDescription className="text-xs sm:text-sm">
              Point your camera at the QR code on shelf {selectedBook?.shelves?.shelf_number}
            </DialogDescription>
          </DialogHeader>
          {selectedBook && (
            <QRScanner
              shelfId={selectedBook.shelf_id}
              shelfNumber={selectedBook.shelves?.shelf_number || 0}
              bookId={selectedBook.id}
              onSuccess={handleQRSuccess}
            />
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default StudentDashboard;
