import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Card, CardContent, CardFooter } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { BookOpen, MapPin, Clock } from "lucide-react";
import { toast } from "sonner";
import { useNavigate } from "react-router-dom";

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

interface BookCardProps {
  book: Book;
  onReservationChange?: () => void;
}

const BookCard = ({ book, onReservationChange }: BookCardProps) => {
  const { user, role } = useAuth();
  const navigate = useNavigate();
  const [reserving, setReserving] = useState(false);

  const handleReserve = async () => {
    if (!user) {
      toast.error("Please login to reserve books");
      navigate("/auth");
      return;
    }

    if (role !== "student") {
      toast.error("Only students can reserve books");
      return;
    }

    setReserving(true);

    try {
      // Check if user already has an active reservation for this book
      const { data: existingReservation } = await supabase
        .from("reservations")
        .select("id, expires_at")
        .eq("book_id", book.id)
        .eq("user_id", user.id)
        .eq("status", "active")
        .maybeSingle();

      if (existingReservation) {
        // Check if reservation is actually expired
        const expiryTime = new Date(existingReservation.expires_at);
        const now = new Date();
        
        if (expiryTime > now) {
          // Still active and not expired
          toast.error("You already have an active reservation for this book");
          setReserving(false);
          return;
        } else {
          // Expired - update it to expired status
          await supabase
            .from("reservations")
            .update({ status: "expired" })
            .eq("id", existingReservation.id);
          
          // Also set book back to available if it's still reserved
          await supabase
            .from("books")
            .update({ status: "available" })
            .eq("id", book.id)
            .eq("status", "reserved");
        }
      }

      // Create reservation (expires in 5 minutes)
      const expiresAt = new Date();
      expiresAt.setMinutes(expiresAt.getMinutes() + 5);

      const { error: reservationError } = await supabase
        .from("reservations")
        .insert({
          book_id: book.id,
          user_id: user.id,
          expires_at: expiresAt.toISOString(),
          status: "active"
        });

      if (reservationError) throw reservationError;

      // Update book status to reserved
      const { error: updateError } = await supabase
        .from("books")
        .update({ status: "reserved" })
        .eq("id", book.id);

      if (updateError) throw updateError;

      toast.success(
        `Book reserved! You have 5 minutes to pick it up from Shelf ${book.shelves?.shelf_number}`,
        { duration: 5000 }
      );

      if (onReservationChange) {
        onReservationChange();
      }

      navigate("/student");
    } catch (error: any) {
      console.error("Reservation error:", error);
      toast.error(error.message || "Failed to reserve book");
    } finally {
      setReserving(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case "available":
        return "success";
      case "reserved":
        return "warning";
      case "issued":
        return "destructive";
      default:
        return "secondary";
    }
  };

  return (
    <Card className="shadow-card hover:shadow-elegant transition-smooth overflow-hidden flex flex-col">
      <div className="aspect-[3/4] bg-muted relative overflow-hidden">
        {book.cover_image ? (
          <img
            src={book.cover_image}
            alt={book.title}
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center gradient-primary">
            <BookOpen className="h-12 w-12 sm:h-16 sm:w-16 text-white opacity-50" />
          </div>
        )}
        <div className="absolute top-2 right-2">
          <Badge variant={getStatusColor(book.status)} className="capitalize text-xs">
            {book.status}
          </Badge>
        </div>
      </div>
      
      <CardContent className="p-3 sm:p-4 flex-1">
        <h3 className="font-bold text-base sm:text-lg line-clamp-1 mb-1">{book.title}</h3>
        <p className="text-xs sm:text-sm text-muted-foreground mb-2 sm:mb-3 truncate">{book.author}</p>
        
        {book.description && (
          <p className="text-xs sm:text-sm text-muted-foreground line-clamp-2 mb-2 sm:mb-3">
            {book.description}
          </p>
        )}
        
        {book.shelves && (
          <div className="flex items-center gap-2 text-xs sm:text-sm text-muted-foreground">
            <MapPin className="h-3 w-3 sm:h-4 sm:w-4 flex-shrink-0" />
            <span>Shelf {book.shelves.shelf_number}</span>
          </div>
        )}
      </CardContent>
      
      <CardFooter className="p-3 sm:p-4 pt-0">
        {book.status === "available" && role === "student" ? (
          <Button
            onClick={handleReserve}
            disabled={reserving}
            className="w-full h-9 sm:h-10 text-xs sm:text-sm"
            variant="accent"
          >
            {reserving ? (
              <>
                <Clock className="mr-1.5 sm:mr-2 h-3 w-3 sm:h-4 sm:w-4 animate-spin" />
                Reserving...
              </>
            ) : (
              <>
                <Clock className="mr-1.5 sm:mr-2 h-3 w-3 sm:h-4 sm:w-4" />
                Reserve (5 min)
              </>
            )}
          </Button>
        ) : book.status === "available" ? (
          <Button className="w-full h-9 sm:h-10 text-xs sm:text-sm" disabled>
            Available
          </Button>
        ) : (
          <Button className="w-full h-9 sm:h-10 text-xs sm:text-sm" disabled variant="secondary">
            Not Available
          </Button>
        )}
      </CardFooter>
    </Card>
  );
};

export default BookCard;
