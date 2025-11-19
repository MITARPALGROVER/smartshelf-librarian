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
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";
import { BookPlus, Pencil, Trash2, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

interface Book {
  id: string;
  title: string;
  author: string;
  isbn: string | null;
  status: string;
  cover_image: string | null;
  description: string | null;
  shelf_id: string | null;
  shelves?: {
    shelf_number: number;
  } | null;
}

interface Shelf {
  id: string;
  shelf_number: number;
}

const BookManager = () => {
  const [books, setBooks] = useState<Book[]>([]);
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [filteredBooks, setFilteredBooks] = useState<Book[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [selectedBook, setSelectedBook] = useState<Book | null>(null);
  const [formData, setFormData] = useState({
    title: "",
    author: "",
    isbn: "",
    description: "",
    cover_image: "",
    shelf_id: "",
    status: "available",
  });

  useEffect(() => {
    fetchData();
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

  const fetchData = async () => {
    setLoading(true);

    // Fetch books
    const { data: booksData, error: booksError } = await supabase
      .from("books")
      .select(`
        id,
        title,
        author,
        isbn,
        status,
        cover_image,
        description,
        shelf_id,
        shelves!books_shelf_id_fkey (
          shelf_number
        )
      `)
      .order("title");

    if (booksError) {
      console.error("Error fetching books:", booksError);
      toast.error("Failed to load books");
    } else {
      setBooks(booksData as Book[]);
      setFilteredBooks(booksData as Book[]);
    }

    // Fetch shelves
    const { data: shelvesData, error: shelvesError } = await supabase
      .from("shelves")
      .select("id, shelf_number")
      .order("shelf_number");

    if (shelvesError) {
      console.error("Error fetching shelves:", shelvesError);
      toast.error("Failed to load shelves");
    } else {
      setShelves(shelvesData as Shelf[]);
    }

    setLoading(false);
  };

  const resetForm = () => {
    setFormData({
      title: "",
      author: "",
      isbn: "",
      description: "",
      cover_image: "",
      shelf_id: "",
      status: "available",
    });
  };

  const handleAddBook = async () => {
    if (!formData.title || !formData.author) {
      toast.error("Title and author are required");
      return;
    }

    const { error } = await supabase.from("books").insert([
      {
        title: formData.title,
        author: formData.author,
        isbn: formData.isbn || null,
        description: formData.description || null,
        cover_image: formData.cover_image || null,
        shelf_id: formData.shelf_id || null,
        status: formData.status,
      },
    ]);

    if (error) {
      console.error("Error adding book:", error);
      toast.error("Failed to add book");
    } else {
      toast.success("Book added successfully");
      setIsAddDialogOpen(false);
      resetForm();
      fetchData();
    }
  };

  const handleEditBook = async () => {
    if (!selectedBook || !formData.title || !formData.author) {
      toast.error("Title and author are required");
      return;
    }

    const { error } = await supabase
      .from("books")
      .update({
        title: formData.title,
        author: formData.author,
        isbn: formData.isbn || null,
        description: formData.description || null,
        cover_image: formData.cover_image || null,
        shelf_id: formData.shelf_id || null,
        status: formData.status,
      })
      .eq("id", selectedBook.id);

    if (error) {
      console.error("Error updating book:", error);
      toast.error("Failed to update book");
    } else {
      toast.success("Book updated successfully");
      setIsEditDialogOpen(false);
      setSelectedBook(null);
      resetForm();
      fetchData();
    }
  };

  const handleDeleteBook = async () => {
    if (!selectedBook) return;

    const { error } = await supabase
      .from("books")
      .delete()
      .eq("id", selectedBook.id);

    if (error) {
      console.error("Error deleting book:", error);
      toast.error("Failed to delete book");
    } else {
      toast.success("Book deleted successfully");
      setIsDeleteDialogOpen(false);
      setSelectedBook(null);
      fetchData();
    }
  };

  const openEditDialog = (book: Book) => {
    setSelectedBook(book);
    setFormData({
      title: book.title,
      author: book.author,
      isbn: book.isbn || "",
      description: book.description || "",
      cover_image: book.cover_image || "",
      shelf_id: book.shelf_id || "",
      status: book.status,
    });
    setIsEditDialogOpen(true);
  };

  const openDeleteDialog = (book: Book) => {
    setSelectedBook(book);
    setIsDeleteDialogOpen(true);
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
              <BookPlus className="h-4 w-4 sm:h-5 sm:w-5 text-primary" />
              Book Management
            </CardTitle>
            <CardDescription className="text-xs sm:text-sm">Add, edit, or remove books from the catalog</CardDescription>
          </div>
          <Dialog open={isAddDialogOpen} onOpenChange={setIsAddDialogOpen}>
            <DialogTrigger asChild>
              <Button onClick={resetForm} className="w-full sm:w-auto text-sm">
                <BookPlus className="mr-2 h-4 w-4" />
                Add Book
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto w-[95vw] sm:w-full">
              <DialogHeader>
                <DialogTitle className="text-base sm:text-lg">Add New Book</DialogTitle>
                <DialogDescription className="text-xs sm:text-sm">Enter the details of the new book</DialogDescription>
              </DialogHeader>
              <div className="grid gap-3 sm:gap-4 py-3 sm:py-4">
                <div className="grid gap-1.5 sm:gap-2">
                  <Label htmlFor="title" className="text-xs sm:text-sm">Title *</Label>
                  <Input
                    id="title"
                    value={formData.title}
                    onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                    placeholder="Enter book title"
                    className="text-xs sm:text-sm"
                  />
                </div>
                <div className="grid gap-1.5 sm:gap-2">
                  <Label htmlFor="author" className="text-xs sm:text-sm">Author *</Label>
                  <Input
                    id="author"
                    value={formData.author}
                    onChange={(e) => setFormData({ ...formData, author: e.target.value })}
                    placeholder="Enter author name"
                    className="text-xs sm:text-sm"
                  />
                </div>
                <div className="grid gap-1.5 sm:gap-2">
                  <Label htmlFor="isbn" className="text-xs sm:text-sm">ISBN</Label>
                  <Input
                    id="isbn"
                    value={formData.isbn}
                    onChange={(e) => setFormData({ ...formData, isbn: e.target.value })}
                    placeholder="Enter ISBN"
                    className="text-xs sm:text-sm"
                  />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="description">Description</Label>
                  <Textarea
                    id="description"
                    value={formData.description}
                    onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                    placeholder="Enter book description"
                    rows={3}
                  />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="cover_image">Cover Image URL</Label>
                  <Input
                    id="cover_image"
                    value={formData.cover_image}
                    onChange={(e) => setFormData({ ...formData, cover_image: e.target.value })}
                    placeholder="Enter image URL"
                  />
                </div>
                <div className="grid gap-1.5 sm:gap-2">
                  <Label htmlFor="shelf" className="text-xs sm:text-sm">Shelf (Optional)</Label>
                  <Select value={formData.shelf_id || undefined} onValueChange={(value) => setFormData({ ...formData, shelf_id: value || "" })}>
                    <SelectTrigger>
                      <SelectValue placeholder="No shelf assigned" />
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
                <div className="grid gap-2">
                  <Label htmlFor="status">Status</Label>
                  <Select value={formData.status} onValueChange={(value) => setFormData({ ...formData, status: value })}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="available">Available</SelectItem>
                      <SelectItem value="issued">Issued</SelectItem>
                      <SelectItem value="reserved">Reserved</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <DialogFooter className="flex-col sm:flex-row gap-2">
                <Button variant="outline" onClick={() => setIsAddDialogOpen(false)} className="w-full sm:w-auto text-xs sm:text-sm">
                  Cancel
                </Button>
                <Button onClick={handleAddBook} className="w-full sm:w-auto text-xs sm:text-sm">Add Book</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-3 sm:space-y-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground h-3 w-3 sm:h-4 sm:w-4" />
            <Input
              type="text"
              placeholder="Search by title, author, or ISBN..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9 sm:pl-10 text-xs sm:text-sm"
            />
          </div>

          {filteredBooks.length === 0 ? (
            <p className="text-muted-foreground text-center py-6 sm:py-8 text-sm">
              {searchQuery ? "No books found matching your search" : "No books in catalog"}
            </p>
          ) : (
            <div className="space-y-2">
              {filteredBooks.map((book) => (
                <div
                  key={book.id}
                  className="flex flex-col sm:flex-row sm:items-center sm:justify-between p-3 sm:p-4 border rounded-lg hover:bg-muted/50 transition-colors gap-3"
                >
                  <div className="flex-1 min-w-0">
                    <h3 className="font-semibold text-sm sm:text-base truncate">{book.title}</h3>
                    <p className="text-xs sm:text-sm text-muted-foreground truncate">{book.author}</p>
                    <div className="flex flex-wrap items-center gap-1.5 sm:gap-2 mt-2">
                      <Badge
                        variant={
                          book.status === "available"
                            ? "success"
                            : book.status === "issued"
                            ? "destructive"
                            : "default"
                        }
                        className="text-xs"
                      >
                        {book.status}
                      </Badge>
                      {book.shelves && (
                        <Badge variant="outline" className="text-xs">
                          Shelf {book.shelves.shelf_number}
                        </Badge>
                      )}
                      {book.isbn && (
                        <span className="text-xs text-muted-foreground truncate">ISBN: {book.isbn}</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 sm:ml-4">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => openEditDialog(book)}
                      className="flex-1 sm:flex-none"
                    >
                      <Pencil className="h-3 w-3 sm:h-4 sm:w-4 sm:mr-0" />
                      <span className="ml-2 sm:hidden">Edit</span>
                    </Button>
                    <Button
                      size="sm"
                      variant="destructive"
                      onClick={() => openDeleteDialog(book)}
                      className="flex-1 sm:flex-none"
                    >
                      <Trash2 className="h-3 w-3 sm:h-4 sm:w-4 sm:mr-0" />
                      <span className="ml-2 sm:hidden">Delete</span>
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </CardContent>

      {/* Edit Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto w-[95vw] sm:w-full">
          <DialogHeader>
            <DialogTitle className="text-base sm:text-lg">Edit Book</DialogTitle>
            <DialogDescription className="text-xs sm:text-sm">Update the book details</DialogDescription>
          </DialogHeader>
          <div className="grid gap-3 sm:gap-4 py-3 sm:py-4">
            <div className="grid gap-2">
              <Label htmlFor="edit-title">Title *</Label>
              <Input
                id="edit-title"
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                placeholder="Enter book title"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="edit-author">Author *</Label>
              <Input
                id="edit-author"
                value={formData.author}
                onChange={(e) => setFormData({ ...formData, author: e.target.value })}
                placeholder="Enter author name"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="edit-isbn">ISBN</Label>
              <Input
                id="edit-isbn"
                value={formData.isbn}
                onChange={(e) => setFormData({ ...formData, isbn: e.target.value })}
                placeholder="Enter ISBN"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="edit-description">Description</Label>
              <Textarea
                id="edit-description"
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                placeholder="Enter book description"
                rows={3}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="edit-cover">Cover Image URL</Label>
              <Input
                id="edit-cover"
                value={formData.cover_image}
                onChange={(e) => setFormData({ ...formData, cover_image: e.target.value })}
                placeholder="Enter image URL"
              />
            </div>
            <div className="grid gap-1.5 sm:gap-2">
              <Label htmlFor="edit-shelf" className="text-xs sm:text-sm">Shelf (Optional)</Label>
              <Select value={formData.shelf_id || undefined} onValueChange={(value) => setFormData({ ...formData, shelf_id: value || "" })}>
                <SelectTrigger>
                  <SelectValue placeholder="No shelf assigned" />
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
            <div className="grid gap-2">
              <Label htmlFor="edit-status">Status</Label>
              <Select value={formData.status} onValueChange={(value) => setFormData({ ...formData, status: value })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="available">Available</SelectItem>
                  <SelectItem value="issued">Issued</SelectItem>
                  <SelectItem value="reserved">Reserved</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter className="flex-col sm:flex-row gap-2">
            <Button variant="outline" onClick={() => setIsEditDialogOpen(false)} className="w-full sm:w-auto text-xs sm:text-sm">
              Cancel
            </Button>
            <Button onClick={handleEditBook} className="w-full sm:w-auto text-xs sm:text-sm">Save Changes</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={isDeleteDialogOpen} onOpenChange={setIsDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete "{selectedBook?.title}" from the catalog.
              This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteBook} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
};

export default BookManager;
