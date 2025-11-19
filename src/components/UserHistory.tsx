import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { BookOpen, ArrowDownToLine, ArrowUpFromLine, Clock } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

interface HistoryEvent {
  id: string;
  created_at: string;
  event_type: 'book_pickup' | 'book_return';
  user_name: string;
  user_email: string;
  student_id: string | null;
  book_title: string;
  book_author: string;
  shelf_number: number;
}

const UserHistory = () => {
  const [history, setHistory] = useState<HistoryEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchHistory();
    
    // Subscribe to real-time updates
    const channel = supabase
      .channel('user-history')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'issued_books'
        },
        () => fetchHistory()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchHistory = async () => {
    try {
      // Fetch issued books (pickups and returns)
      const { data: issuedData, error: issuedError } = await supabase
        .from("issued_books")
        .select(`
          id,
          issued_at,
          returned_at,
          book_id,
          user_id,
          books!inner (
            title,
            author,
            shelf_id,
            shelves!books_shelf_id_fkey (
              shelf_number
            )
          ),
          profiles!inner (
            full_name,
            email,
            student_id
          )
        `)
        .order("issued_at", { ascending: false })
        .limit(50);

      if (issuedError) {
        console.error('Error fetching history:', issuedError);
        setLoading(false);
        return;
      }

      // Transform data into history events
      const events: HistoryEvent[] = [];
      
      if (issuedData) {
        issuedData.forEach((record: any) => {
          // Add pickup event
          events.push({
            id: `${record.id}-pickup`,
            created_at: record.issued_at,
            event_type: 'book_pickup',
            user_name: record.profiles?.full_name || 'Unknown User',
            user_email: record.profiles?.email || '',
            student_id: record.profiles?.student_id || null,
            book_title: record.books?.title || 'Unknown Book',
            book_author: record.books?.author || 'Unknown Author',
            shelf_number: record.books?.shelves?.shelf_number || 0,
          });

          // Add return event if returned
          if (record.returned_at) {
            events.push({
              id: `${record.id}-return`,
              created_at: record.returned_at,
              event_type: 'book_return',
              user_name: record.profiles?.full_name || 'Unknown User',
              user_email: record.profiles?.email || '',
              student_id: record.profiles?.student_id || null,
              book_title: record.books?.title || 'Unknown Book',
              book_author: record.books?.author || 'Unknown Author',
              shelf_number: record.books?.shelves?.shelf_number || 0,
            });
          }
        });
      }

      // Sort by date (most recent first)
      events.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

      setHistory(events);
      setLoading(false);
    } catch (error) {
      console.error('Error in fetchHistory:', error);
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-center">
          <Clock className="h-12 w-12 animate-pulse mx-auto mb-4 text-primary" />
          <p className="text-muted-foreground">Loading history...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <div>
        <h2 className="text-xl sm:text-2xl font-bold mb-2">User Activity History</h2>
        <p className="text-sm sm:text-base text-muted-foreground">Recent book pickups and returns</p>
      </div>

      <Card className="shadow-card">
        <CardHeader>
          <CardTitle className="text-lg sm:text-xl flex items-center gap-2">
            <BookOpen className="h-5 w-5" />
            Activity Timeline
          </CardTitle>
          <CardDescription>All user interactions with the library system</CardDescription>
        </CardHeader>
        <CardContent>
          {history.length === 0 ? (
            <div className="text-center py-12">
              <BookOpen className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
              <p className="text-muted-foreground">No activity history yet</p>
            </div>
          ) : (
            <div className="space-y-3">
              {history.map((event) => {
                const isPickup = event.event_type === 'book_pickup';
                return (
                  <div
                    key={event.id}
                    className={`p-4 rounded-lg border ${
                      isPickup 
                        ? 'bg-blue-50 dark:bg-blue-950/20 border-blue-200 dark:border-blue-800' 
                        : 'bg-green-50 dark:bg-green-950/20 border-green-200 dark:border-green-800'
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      {/* Icon */}
                      <div className={`p-2 rounded-lg ${
                        isPickup 
                          ? 'bg-blue-500 text-white' 
                          : 'bg-green-500 text-white'
                      }`}>
                        {isPickup ? (
                          <ArrowDownToLine className="h-4 w-4" />
                        ) : (
                          <ArrowUpFromLine className="h-4 w-4" />
                        )}
                      </div>

                      {/* Content */}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start justify-between gap-2 mb-1">
                          <div className="flex-1 min-w-0">
                            <h4 className="font-semibold text-sm sm:text-base">
                              {isPickup ? 'Book Picked Up' : 'Book Returned'}
                            </h4>
                            <p className="text-sm text-muted-foreground truncate">
                              {event.book_title}
                              <span className="text-xs"> by {event.book_author}</span>
                            </p>
                          </div>
                          <Badge 
                            variant={isPickup ? 'default' : 'success'}
                            className="flex-shrink-0"
                          >
                            Shelf {event.shelf_number}
                          </Badge>
                        </div>
                        
                        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground mt-2">
                          <span className="font-medium">{event.user_name}</span>
                          {event.student_id && (
                            <span className="text-xs bg-muted px-2 py-0.5 rounded">
                              ID: {event.student_id}
                            </span>
                          )}
                          <span>•</span>
                          <span className="truncate">{event.user_email}</span>
                        </div>
                        
                        <div className="flex items-center gap-1 text-xs text-muted-foreground mt-1">
                          <Clock className="h-3 w-3" />
                          <span>
                            {formatDistanceToNow(new Date(event.created_at), { addSuffix: true })}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default UserHistory;
