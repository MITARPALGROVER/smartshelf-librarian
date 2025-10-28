import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import BookCard from "@/components/BookCard";
import { Input } from "@/components/ui/input";
import { Search } from "lucide-react";

interface Book {
  id: string;
  title: string;
  author: string;
  isbn: string | null;
  status: string;
  cover_image: string | null;
  description: string | null;
  shelves: {
    shelf_number: number;
  } | null;
}

const BooksPage = () => {
  const [books, setBooks] = useState<Book[]>([]);
  const [filteredBooks, setFilteredBooks] = useState<Book[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchBooks();
    
    // Subscribe to real-time book updates
    const booksChannel = supabase
      .channel('books-changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'books'
        },
        () => fetchBooks()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(booksChannel);
    };
  }, []);

  useEffect(() => {
    if (searchQuery.trim() === "") {
      setFilteredBooks(books);
    } else {
      const query = searchQuery.toLowerCase();
      const filtered = books.filter(
        (book) =>
          book.title.toLowerCase().includes(query) ||
          book.author.toLowerCase().includes(query) ||
          book.isbn?.toLowerCase().includes(query)
      );
      setFilteredBooks(filtered);
    }
  }, [searchQuery, books]);

  const fetchBooks = async () => {
    const { data, error } = await supabase
      .from("books")
      .select(`
        id,
        title,
        author,
        isbn,
        status,
        cover_image,
        description,
        shelves (
          shelf_number
        )
      `)
      .order("title");

    if (error) {
      console.error("Error fetching books:", error);
    } else {
      setBooks(data as Book[]);
      setFilteredBooks(data as Book[]);
    }
    setLoading(false);
  };

  if (loading) {
    return (
      <div className="text-center py-12">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
        <p className="text-muted-foreground">Loading books...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6 sm:space-y-8">
      <div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold mb-2">Book Catalog</h1>
        <p className="text-sm sm:text-base text-muted-foreground">Browse and reserve books from our collection</p>
      </div>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground h-4 w-4" />
        <Input
          type="text"
          placeholder="Search by title, author, or ISBN..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10 text-sm sm:text-base"
        />
      </div>

      {filteredBooks.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-sm sm:text-base text-muted-foreground">
            {searchQuery ? "No books found matching your search" : "No books available in the catalog"}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 sm:gap-4 lg:gap-6">
          {filteredBooks.map((book) => (
            <BookCard key={book.id} book={book} onReservationChange={fetchBooks} />
          ))}
        </div>
      )}
    </div>
  );
};

export default BooksPage;
