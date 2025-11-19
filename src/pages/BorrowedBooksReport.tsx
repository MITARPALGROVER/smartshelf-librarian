import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from "@/components/ui/table";
import { 
  BookOpen, 
  Users, 
  Search, 
  Download,
  CheckCircle,
  Clock,
  AlertCircle
} from "lucide-react";
import { formatDistanceToNow, format } from "date-fns";
import { toast } from "sonner";

interface BorrowedBookRecord {
  id: string;
  book_id: string;
  user_id: string;
  issued_at: string;
  due_date: string;
  returned_at: string | null;
  book_title: string;
  book_author: string;
  student_name: string;
  student_email: string;
  student_id: string | null;
  shelf_number: number | null;
  is_overdue: boolean;
}

interface StudentSummary {
  user_id: string;
  student_name: string;
  student_email: string;
  student_id: string | null;
  total_borrowed: number;
  currently_borrowed: number;
  overdue_count: number;
}

const BorrowedBooksReport = () => {
  const [allRecords, setAllRecords] = useState<BorrowedBookRecord[]>([]);
  const [filteredRecords, setFilteredRecords] = useState<BorrowedBookRecord[]>([]);
  const [studentSummaries, setStudentSummaries] = useState<StudentSummary[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [filterType, setFilterType] = useState<"all" | "active" | "returned" | "overdue">("active");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchAllBorrowedBooks();
    
    // Real-time subscription
    const channel = supabase
      .channel('borrowed-books-updates')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'issued_books'
        },
        () => fetchAllBorrowedBooks()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  useEffect(() => {
    filterRecords();
  }, [searchQuery, filterType, allRecords]);

  const fetchAllBorrowedBooks = async () => {
    console.log('📚 Fetching all borrowed books...');
    
    const { data, error } = await supabase
      .from("issued_books")
      .select(`
        id,
        book_id,
        user_id,
        issued_at,
        due_date,
        returned_at,
        books (
          title,
          author,
          shelves!books_shelf_id_fkey (
            shelf_number
          )
        ),
        profiles (
          full_name,
          email,
          student_id
        )
      `)
      .order("issued_at", { ascending: false });

    if (error) {
      console.error('❌ Error:', error);
      toast.error("Failed to load borrowed books");
      setLoading(false);
      return;
    }

    console.log('✅ Fetched records:', data);

    // Transform data
    const now = new Date();
    const records: BorrowedBookRecord[] = (data || []).map((record: any) => ({
      id: record.id,
      book_id: record.book_id,
      user_id: record.user_id,
      issued_at: record.issued_at,
      due_date: record.due_date,
      returned_at: record.returned_at,
      book_title: record.books?.title || 'Unknown Book',
      book_author: record.books?.author || 'Unknown Author',
      student_name: record.profiles?.full_name || 'Unknown User',
      student_email: record.profiles?.email || 'N/A',
      student_id: record.profiles?.student_id,
      shelf_number: record.books?.shelves?.shelf_number,
      is_overdue: !record.returned_at && new Date(record.due_date) < now
    }));

    setAllRecords(records);

    // Calculate student summaries
    const summaryMap = new Map<string, StudentSummary>();
    
    records.forEach(record => {
      const existing = summaryMap.get(record.user_id);
      
      if (existing) {
        existing.total_borrowed++;
        if (!record.returned_at) existing.currently_borrowed++;
        if (record.is_overdue) existing.overdue_count++;
      } else {
        summaryMap.set(record.user_id, {
          user_id: record.user_id,
          student_name: record.student_name,
          student_email: record.student_email,
          student_id: record.student_id,
          total_borrowed: 1,
          currently_borrowed: record.returned_at ? 0 : 1,
          overdue_count: record.is_overdue ? 1 : 0
        });
      }
    });

    setStudentSummaries(Array.from(summaryMap.values()));
    setLoading(false);
  };

  const filterRecords = () => {
    let filtered = [...allRecords];

    // Apply type filter
    if (filterType === "active") {
      filtered = filtered.filter(r => !r.returned_at);
    } else if (filterType === "returned") {
      filtered = filtered.filter(r => r.returned_at);
    } else if (filterType === "overdue") {
      filtered = filtered.filter(r => r.is_overdue);
    }

    // Apply search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(r =>
        r.book_title.toLowerCase().includes(query) ||
        r.book_author.toLowerCase().includes(query) ||
        r.student_name.toLowerCase().includes(query) ||
        r.student_email.toLowerCase().includes(query) ||
        r.student_id?.toLowerCase().includes(query)
      );
    }

    setFilteredRecords(filtered);
  };

  const handleMarkReturned = async (recordId: string) => {
    const { error } = await supabase
      .from("issued_books")
      .update({ returned_at: new Date().toISOString() })
      .eq("id", recordId);

    if (error) {
      toast.error("Failed to mark as returned");
    } else {
      toast.success("Book marked as returned");
      fetchAllBorrowedBooks();
    }
  };

  const exportToCSV = () => {
    const headers = [
      "Book Title",
      "Author",
      "Student Name",
      "Student Email",
      "Student ID",
      "Shelf",
      "Issued Date",
      "Due Date",
      "Returned Date",
      "Status"
    ];

    const rows = filteredRecords.map(r => [
      r.book_title,
      r.book_author,
      r.student_name,
      r.student_email,
      r.student_id || "N/A",
      r.shelf_number || "N/A",
      format(new Date(r.issued_at), "yyyy-MM-dd HH:mm"),
      format(new Date(r.due_date), "yyyy-MM-dd HH:mm"),
      r.returned_at ? format(new Date(r.returned_at), "yyyy-MM-dd HH:mm") : "Not Returned",
      r.is_overdue ? "OVERDUE" : r.returned_at ? "Returned" : "Active"
    ]);

    const csv = [headers, ...rows].map(row => row.join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `borrowed-books-${format(new Date(), "yyyy-MM-dd")}.csv`;
    a.click();
    
    toast.success("Report exported successfully");
  };

  if (loading) {
    return <div className="text-center py-8">Loading...</div>;
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 sm:gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold">Borrowed Books Report</h1>
          <p className="text-sm sm:text-base text-muted-foreground">Complete list of all book borrowing activities</p>
        </div>
        <Button onClick={exportToCSV} variant="outline" size="sm" className="w-full sm:w-auto">
          <Download className="mr-2 h-4 w-4" />
          Export CSV
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-3 sm:gap-4 grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="p-3 sm:p-6 pb-2">
            <CardTitle className="text-xs sm:text-sm font-medium flex items-center gap-1 sm:gap-2">
              <Users className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">Total Students</span>
              <span className="sm:hidden">Students</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="p-3 sm:p-6 pt-0">
            <div className="text-xl sm:text-2xl font-bold">{studentSummaries.length}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <BookOpen className="h-4 w-4" />
              Currently Borrowed
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {allRecords.filter(r => !r.returned_at).length}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <CheckCircle className="h-4 w-4 text-green-600" />
              Total Returned
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">
              {allRecords.filter(r => r.returned_at).length}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <AlertCircle className="h-4 w-4 text-red-600" />
              Overdue Books
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {allRecords.filter(r => r.is_overdue).length}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardHeader className="p-4 sm:p-6">
          <CardTitle className="text-base sm:text-lg">Filter & Search</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3 sm:space-y-4 p-4 sm:p-6 pt-0">
          <div className="space-y-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search by book, student name, email..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-9 text-sm"
              />
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <Button
                variant={filterType === "all" ? "default" : "outline"}
                onClick={() => setFilterType("all")}
                size="sm"
                className="text-xs"
              >
                All ({allRecords.length})
              </Button>
              <Button
                variant={filterType === "active" ? "default" : "outline"}
                onClick={() => setFilterType("active")}
                size="sm"
                className="text-xs"
              >
                <Clock className="mr-1 h-3 w-3" />
                Active ({allRecords.filter(r => !r.returned_at).length})
              </Button>
              <Button
                variant={filterType === "returned" ? "default" : "outline"}
                onClick={() => setFilterType("returned")}
                size="sm"
                className="text-xs"
              >
                <CheckCircle className="mr-1 h-3 w-3" />
                Returned ({allRecords.filter(r => r.returned_at).length})
              </Button>
              <Button
                variant={filterType === "overdue" ? "default" : "outline"}
                onClick={() => setFilterType("overdue")}
                size="sm"
                className="text-xs"
              >
                <AlertCircle className="mr-1 h-3 w-3" />
                Overdue ({allRecords.filter(r => r.is_overdue).length})
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Records Table */}
      <Card>
        <CardHeader>
          <CardTitle>Borrowing Records ({filteredRecords.length})</CardTitle>
          <CardDescription>
            {filterType === "all" && "All borrowing records"}
            {filterType === "active" && "Currently borrowed books"}
            {filterType === "returned" && "Returned books"}
            {filterType === "overdue" && "Overdue books needing attention"}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Book</TableHead>
                  <TableHead>Student</TableHead>
                  <TableHead>Shelf</TableHead>
                  <TableHead>Issued</TableHead>
                  <TableHead>Due Date</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredRecords.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center text-muted-foreground py-8">
                      No records found
                    </TableCell>
                  </TableRow>
                ) : (
                  filteredRecords.map((record) => (
                    <TableRow key={record.id}>
                      <TableCell>
                        <div>
                          <div className="font-medium">{record.book_title}</div>
                          <div className="text-sm text-muted-foreground">{record.book_author}</div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div>
                          <div className="font-medium">{record.student_name}</div>
                          <div className="text-sm text-muted-foreground">{record.student_email}</div>
                          {record.student_id && (
                            <div className="text-xs text-muted-foreground">ID: {record.student_id}</div>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">
                          Shelf {record.shelf_number || 'N/A'}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-sm">
                        {format(new Date(record.issued_at), "MMM dd, yyyy")}
                      </TableCell>
                      <TableCell className="text-sm">
                        <div className={record.is_overdue ? "text-red-600 font-medium" : ""}>
                          {format(new Date(record.due_date), "MMM dd, yyyy")}
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {formatDistanceToNow(new Date(record.due_date), { addSuffix: true })}
                        </div>
                      </TableCell>
                      <TableCell>
                        {record.returned_at ? (
                          <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
                            Returned
                          </Badge>
                        ) : record.is_overdue ? (
                          <Badge variant="destructive">
                            OVERDUE
                          </Badge>
                        ) : (
                          <Badge variant="default">
                            Active
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        {!record.returned_at && (
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => handleMarkReturned(record.id)}
                          >
                            <CheckCircle className="mr-1 h-3 w-3" />
                            Return
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Student Summary */}
      <Card>
        <CardHeader>
          <CardTitle>Student Summary</CardTitle>
          <CardDescription>Overview of borrowing activity by student</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Student</TableHead>
                  <TableHead className="text-right">Total Borrowed</TableHead>
                  <TableHead className="text-right">Currently Borrowed</TableHead>
                  <TableHead className="text-right">Overdue</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {studentSummaries.map((summary) => (
                  <TableRow key={summary.user_id}>
                    <TableCell>
                      <div>
                        <div className="font-medium">{summary.student_name}</div>
                        <div className="text-sm text-muted-foreground">{summary.student_email}</div>
                        {summary.student_id && (
                          <div className="text-xs text-muted-foreground">ID: {summary.student_id}</div>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="text-right font-medium">
                      {summary.total_borrowed}
                    </TableCell>
                    <TableCell className="text-right">
                      {summary.currently_borrowed > 0 ? (
                        <Badge variant="default">{summary.currently_borrowed}</Badge>
                      ) : (
                        <span className="text-muted-foreground">0</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      {summary.overdue_count > 0 ? (
                        <Badge variant="destructive">{summary.overdue_count}</Badge>
                      ) : (
                        <span className="text-muted-foreground">0</span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default BorrowedBooksReport;
