import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Scale, Activity, Clock, BookOpen } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

interface Shelf {
  id: string;
  shelf_number: number;
  current_weight: number;
  max_weight: number;
  is_active: boolean;
  last_sensor_update: string | null;
}

interface Book {
  id: string;
  title: string;
  author: string;
  weight: number;
}

const ShelfMonitor = () => {
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [shelfBooks, setShelfBooks] = useState<Record<string, Book[]>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchShelves();
    
    // Subscribe to real-time updates
    const shelvesChannel = supabase
      .channel('shelves-monitor')
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'shelves'
        },
        (payload) => {
          console.log('Shelf updated:', payload);
          setShelves(current => 
            current.map(shelf => 
              shelf.id === payload.new.id 
                ? { ...shelf, ...payload.new }
                : shelf
            )
          );
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(shelvesChannel);
    };
  }, []);

  const fetchShelves = async () => {
    // Fetch shelves
    const { data: shelvesData, error: shelvesError } = await supabase
      .from('shelves')
      .select('*')
      .order('shelf_number');

    if (shelvesError) {
      console.error('Error fetching shelves:', shelvesError);
      setLoading(false);
      return;
    }

    if (shelvesData) {
      setShelves(shelvesData);

      // Fetch books for each shelf
      const { data: booksData } = await supabase
        .from('books')
        .select('id, title, author, weight, shelf_id')
        .not('shelf_id', 'is', null);

      if (booksData) {
        const booksByShelf: Record<string, Book[]> = {};
        booksData.forEach((book: any) => {
          if (!booksByShelf[book.shelf_id]) {
            booksByShelf[book.shelf_id] = [];
          }
          booksByShelf[book.shelf_id].push(book);
        });
        setShelfBooks(booksByShelf);
      }
    }

    setLoading(false);
  };

  const getShelfStatus = (shelf: Shelf) => {
    if (!shelf.is_active) return { color: "destructive", text: "Inactive" };
    
    const now = new Date();
    const lastUpdate = shelf.last_sensor_update ? new Date(shelf.last_sensor_update) : null;
    
    if (!lastUpdate) return { color: "secondary", text: "No Data" };
    
    const timeDiff = now.getTime() - lastUpdate.getTime();
    const minutesAgo = timeDiff / (1000 * 60);
    
    if (minutesAgo > 5) return { color: "warning", text: "Offline" };
    if (minutesAgo > 1) return { color: "secondary", text: "Delayed" };
    return { color: "success", text: "Online" };
  };

  const getCapacityPercentage = (shelf: Shelf) => {
    return Math.min((shelf.current_weight / shelf.max_weight) * 100, 100);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-center">
          <Activity className="h-12 w-12 animate-pulse mx-auto mb-4 text-primary" />
          <p className="text-muted-foreground">Loading shelf data...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <div>
        <h2 className="text-xl sm:text-2xl font-bold mb-2">Smart Shelf Monitor</h2>
        <p className="text-sm sm:text-base text-muted-foreground">Real-time weight sensor data from IoT shelves</p>
      </div>

      <div className="grid gap-3 sm:gap-4 grid-cols-1 lg:grid-cols-2">
        {shelves.map((shelf) => {
          const status = getShelfStatus(shelf);
          const capacityPercent = getCapacityPercentage(shelf);
          const books = shelfBooks[shelf.id] || [];
          const totalBookWeight = books.reduce((sum, book) => sum + (book.weight || 0), 0);

          return (
            <Card key={shelf.id} className="shadow-card hover:shadow-lg transition-shadow">
              <CardHeader>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-2 sm:gap-3 flex-1 min-w-0">
                    <div className="gradient-primary p-2 sm:p-3 rounded-lg flex-shrink-0">
                      <Scale className="h-4 w-4 sm:h-5 md:h-6 text-white" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <CardTitle className="text-base sm:text-lg">Shelf {shelf.shelf_number}</CardTitle>
                      <CardDescription className="text-xs sm:text-sm truncate">
                        {books.length} book{books.length !== 1 ? 's' : ''} registered
                      </CardDescription>
                    </div>
                  </div>
                  <Badge variant={status.color as any} className="flex-shrink-0 text-xs">
                    {status.text}
                  </Badge>
                </div>
              </CardHeader>
              
              <CardContent className="space-y-3 sm:space-y-4">
                {/* Current Weight */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs sm:text-sm font-medium">Current Weight</span>
                    <span className="text-xl sm:text-2xl font-bold text-primary">
                      {shelf.current_weight.toFixed(1)}g
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-muted-foreground mb-1">
                    <span>Capacity</span>
                    <span>{shelf.max_weight}g max</span>
                  </div>
                  <Progress value={capacityPercent} className="h-2" />
                </div>

                {/* Expected vs Actual */}
                {books.length > 0 && (
                  <div className="bg-muted/50 rounded-lg p-2 sm:p-3 space-y-1.5 sm:space-y-2">
                    <div className="flex items-center justify-between text-xs sm:text-sm">
                      <span className="text-muted-foreground">Expected weight:</span>
                      <span className="font-medium">{totalBookWeight}g</span>
                    </div>
                    <div className="flex items-center justify-between text-xs sm:text-sm">
                      <span className="text-muted-foreground">Actual weight:</span>
                      <span className="font-medium">{shelf.current_weight.toFixed(1)}g</span>
                    </div>
                    <div className="flex items-center justify-between text-xs sm:text-sm">
                      <span className="text-muted-foreground">Difference:</span>
                      <span className={`font-medium ${
                        Math.abs(totalBookWeight - shelf.current_weight) > 50 
                          ? 'text-warning' 
                          : 'text-success'
                      }`}>
                        {Math.abs(totalBookWeight - shelf.current_weight).toFixed(1)}g
                      </span>
                    </div>
                  </div>
                )}

                {/* Books on Shelf */}
                {books.length > 0 && (
                  <div className="space-y-2">
                    <div className="flex items-center gap-2 text-xs sm:text-sm font-medium">
                      <BookOpen className="h-3 w-3 sm:h-4 sm:w-4" />
                      <span>Books on this shelf</span>
                    </div>
                    <div className="space-y-1 max-h-24 sm:max-h-32 overflow-y-auto">
                      {books.map((book) => (
                        <div 
                          key={book.id} 
                          className="text-xs bg-muted/30 rounded px-2 py-1.5 flex justify-between gap-2"
                        >
                          <span className="truncate flex-1">{book.title}</span>
                          {book.weight && (
                            <span className="text-muted-foreground ml-2 flex-shrink-0">{book.weight}g</span>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Last Update */}
                <div className="flex items-center gap-2 text-xs text-muted-foreground pt-2 border-t">
                  <Clock className="h-3 w-3" />
                  <span className="truncate">
                    {shelf.last_sensor_update 
                      ? `Updated ${formatDistanceToNow(new Date(shelf.last_sensor_update), { addSuffix: true })}`
                      : 'No updates yet'
                    }
                  </span>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {shelves.length === 0 && (
        <Card className="shadow-card">
          <CardContent className="py-12 text-center">
            <Scale className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
            <p className="text-muted-foreground">No shelves configured</p>
            <p className="text-sm text-muted-foreground mt-2">
              Shelves are automatically created when you run the database migration
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

export default ShelfMonitor;
