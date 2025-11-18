import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Card, CardContent, CardFooter } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { BookOpen, MapPin, QrCode } from "lucide-react";
import { toast } from "sonner";
import { useNavigate } from "react-router-dom";
import { QRScanner } from "./QRScanner";

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
  const [showQRScanner, setShowQRScanner] = useState(false);

  const handlePickup = () => {
    if (!user) {
      toast.error("Please login to pickup books");
      navigate("/auth");
      return;
    }

    if (role !== "student") {
      toast.error("Only students can pickup books");
      return;
    }

    // Get shelf information
    if (!book.shelves) {
      toast.error("Shelf information not available for this book");
      return;
    }

    // Open QR scanner dialog
    setShowQRScanner(true);
  };

  const handleQRSuccess = async () => {
    setShowQRScanner(false);
    
    // Book will be issued automatically by weight sensor
    toast.success(
      `Door unlocked! You have 1 minute to pick up "${book.title}" from Shelf ${book.shelves?.shelf_number}`,
      { duration: 8000 }
    );

    if (onReservationChange) {
      onReservationChange();
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
          <>
            <Button
              onClick={handlePickup}
              className="w-full h-9 sm:h-10 text-xs sm:text-sm"
              variant="accent"
            >
              <QrCode className="mr-1.5 sm:mr-2 h-3 w-3 sm:h-4 sm:w-4" />
              Scan QR to Pickup
            </Button>

            <Dialog open={showQRScanner} onOpenChange={setShowQRScanner}>
              <DialogContent className="sm:max-w-md">
                <DialogHeader>
                  <DialogTitle>Scan Shelf QR Code</DialogTitle>
                  <DialogDescription>
                    Scan the QR code on Shelf {book.shelves?.shelf_number} to unlock the door and pickup "{book.title}"
                  </DialogDescription>
                </DialogHeader>
                <QRScanner
                  shelfId={book.shelves?.shelf_number?.toString() || ""}
                  shelfNumber={book.shelves?.shelf_number || 0}
                  bookId={book.id}
                  onSuccess={handleQRSuccess}
                />
              </DialogContent>
            </Dialog>
          </>
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
