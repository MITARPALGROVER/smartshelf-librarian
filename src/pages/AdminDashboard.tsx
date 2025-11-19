import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { BookOpen, Plus, Trash2, Users, BarChart } from "lucide-react";
import { toast } from "sonner";
import ShelfMonitor from "@/components/ShelfMonitor";

interface Book {
  id: string;
  title: string;
  author: string;
  isbn: string | null;
  status: string;
  shelf_id: string | null;
  shelves: {
    shelf_number: number;
  } | null;
}

interface Shelf {
  id: string;
  shelf_number: number;
  current_weight: number;
  max_weight: number;
  is_active: boolean;
}

const AdminDashboard = () => {
  const [books, setBooks] = useState<Book[]>([]);
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [isAddBookOpen, setIsAddBookOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  
  // Form state for adding book
  const [newBook, setNewBook] = useState({
    title: "",
    author: "",
    isbn: "",
    description: "",
    shelf_id: "",
    weight: "",
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    // Fetch all books
    const { data: booksData } = await supabase
      .from("books")
      .select(`
        id,
        title,
        author,
        isbn,
        status,
        shelf_id,
        shelves!books_shelf_id_fkey (
          shelf_number
        )
      `)
      .order("title");

    // Fetch all shelves
    const { data: shelvesData } = await supabase
      .from("shelves")
      .select("*")
      .order("shelf_number");

    if (booksData) setBooks(booksData as Book[]);
    if (shelvesData) setShelves(shelvesData);
    setLoading(false);
  };

  const handleAddBook = async () => {
    if (!newBook.title || !newBook.author || !newBook.shelf_id) {
      toast.error("Please fill in all required fields");
      return;
    }

    const { error } = await supabase.from("books").insert({
      title: newBook.title,
      author: newBook.author,
      isbn: newBook.isbn || null,
      description: newBook.description || null,
      shelf_id: newBook.shelf_id,
      weight: newBook.weight ? parseFloat(newBook.weight) : null,
      status: "available",
    });

    if (error) {
      toast.error("Failed to add book");
      console.error(error);
    } else {
      toast.success("Book added successfully");
      setIsAddBookOpen(false);
      setNewBook({
        title: "",
        author: "",
        isbn: "",
        description: "",
        shelf_id: "",
        weight: "",
      });
      fetchData();
    }
  };

  const handleDeleteBook = async (bookId: string, bookTitle: string) => {
    if (!confirm(`Are you sure you want to delete "${bookTitle}"?`)) {
      return;
    }

    const { error } = await supabase
      .from("books")
      .delete()
      .eq("id", bookId);

    if (error) {
      toast.error("Failed to delete book");
    } else {
      toast.success("Book deleted successfully");
      fetchData();
    }
  };

  if (loading) {
    return <div className="text-center">Loading...</div>;
  }

  return (
    <div className="space-y-6 sm:space-y-8">
      <div className="flex flex-col sm:flex-row sm:justify-between sm:items-start gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold mb-2">Admin Dashboard</h1>
          <p className="text-sm sm:text-base text-muted-foreground">Manage books, shelves, and system settings</p>
        </div>
        <Dialog open={isAddBookOpen} onOpenChange={setIsAddBookOpen}>
          <DialogTrigger asChild>
            <Button variant="accent" size="sm" className="w-full sm:w-auto">
              <Plus className="mr-2 h-4 w-4" />
              Add Book
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-md">
            <DialogHeader>
              <DialogTitle>Add New Book</DialogTitle>
              <DialogDescription>Add a new book to the library catalog</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="title">Title *</Label>
                <Input
                  id="title"
                  value={newBook.title}
                  onChange={(e) => setNewBook({ ...newBook, title: e.target.value })}
                  placeholder="Book title"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="author">Author *</Label>
                <Input
                  id="author"
                  value={newBook.author}
                  onChange={(e) => setNewBook({ ...newBook, author: e.target.value })}
                  placeholder="Author name"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="isbn">ISBN</Label>
                <Input
                  id="isbn"
                  value={newBook.isbn}
                  onChange={(e) => setNewBook({ ...newBook, isbn: e.target.value })}
                  placeholder="ISBN number"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="shelf">Shelf *</Label>
                <Select
                  value={newBook.shelf_id}
                  onValueChange={(value) => setNewBook({ ...newBook, shelf_id: value })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select a shelf" />
                  </SelectTrigger>
                  <SelectContent>
                    {shelves.map((shelf) => (
                      <SelectItem key={shelf.id} value={shelf.id}>
                        Shelf {shelf.shelf_number}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="weight">Weight (grams)</Label>
                <Input
                  id="weight"
                  type="number"
                  value={newBook.weight}
                  onChange={(e) => setNewBook({ ...newBook, weight: e.target.value })}
                  placeholder="Book weight in grams"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  value={newBook.description}
                  onChange={(e) => setNewBook({ ...newBook, description: e.target.value })}
                  placeholder="Book description"
                  rows={3}
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setIsAddBookOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleAddBook} variant="accent">
                Add Book
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid gap-3 sm:gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
        <Card className="shadow-card">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Books</CardTitle>
            <BookOpen className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{books.length}</div>
            <p className="text-xs text-muted-foreground">In library catalog</p>
          </CardContent>
        </Card>

        <Card className="shadow-card">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Available Books</CardTitle>
            <BarChart className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-success">
              {books.filter((b) => b.status === "available").length}
            </div>
            <p className="text-xs text-muted-foreground">Ready to be borrowed</p>
          </CardContent>
        </Card>

        <Card className="shadow-card sm:col-span-2 lg:col-span-1">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Shelves</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{shelves.filter((s) => s.is_active).length}</div>
            <p className="text-xs text-muted-foreground">With weight sensors</p>
          </CardContent>
        </Card>
      </div>

      <Card className="shadow-card">
        <CardHeader>
          <CardTitle className="text-lg sm:text-xl">Book Catalog</CardTitle>
          <CardDescription className="text-sm">All books in the library system</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-3 sm:space-y-4">
            {books.length === 0 ? (
              <p className="text-muted-foreground text-center py-8 text-sm sm:text-base">
                No books in the catalog. Click "Add Book" to get started.
              </p>
            ) : (
              <div className="grid gap-3 sm:gap-4">
                {books.map((book) => (
                  <div key={book.id} className="flex items-start sm:items-center justify-between p-3 sm:p-4 bg-muted/50 rounded-lg gap-3">
                    <div className="flex-1 min-w-0">
                      <h4 className="font-semibold text-sm sm:text-base truncate">{book.title}</h4>
                      <p className="text-xs sm:text-sm text-muted-foreground truncate">{book.author}</p>
                      <div className="flex flex-wrap items-center gap-2 sm:gap-4 mt-1">
                        {book.isbn && (
                          <span className="text-xs text-muted-foreground">ISBN: {book.isbn}</span>
                        )}
                        {book.shelves && (
                          <span className="text-xs text-muted-foreground">
                            Shelf {book.shelves.shelf_number}
                          </span>
                        )}
                        <span className={`text-xs capitalize ${
                          book.status === 'available' ? 'text-success' :
                          book.status === 'reserved' ? 'text-warning' :
                          'text-destructive'
                        }`}>
                          {book.status}
                        </span>
                      </div>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleDeleteBook(book.id, book.title)}
                      className="text-destructive hover:text-destructive hover:bg-destructive/10 flex-shrink-0"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Real-time IoT Shelf Monitor */}
      <ShelfMonitor />
    </div>
  );
};

export default AdminDashboard;
