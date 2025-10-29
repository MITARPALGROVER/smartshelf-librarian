import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Bell, X, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import { formatDistanceToNow } from "date-fns";
import { toast } from "sonner";
import type { Notification } from "@/lib/notifications";
import { markNotificationRead, markAllNotificationsRead } from "@/lib/notifications";

const NotificationBell = () => {
  const { user } = useAuth();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    if (!user) return;

    fetchNotifications();

    // Subscribe to real-time notifications
    const channel = supabase
      .channel('user-notifications')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'notifications',
          filter: `user_id=eq.${user.id}`
        },
        (payload) => {
          console.log('🔔 Realtime notification event:', payload.eventType, payload);
          if (payload.eventType === 'INSERT') {
            const newNotif = payload.new as Notification;
            console.log('📥 Adding notification to state:', newNotif);
            
            setNotifications(prev => {
              const updated = [newNotif, ...prev];
              console.log('📊 Updated notifications array:', updated.length, 'items');
              return updated;
            });
            
            setUnreadCount(prev => {
              const newCount = prev + 1;
              console.log('🔢 Updated unread count:', newCount);
              return newCount;
            });
            
            // Show toast notification
            console.log('🍞 Showing toast notification');
            toast(newNotif.title, {
              description: newNotif.message,
              duration: 5000,
            });
          } else if (payload.eventType === 'UPDATE') {
            // Handle mark as read updates
            fetchNotifications();
          } else {
            fetchNotifications();
          }
        }
      )
      .subscribe((status) => {
        console.log('🔔 Notification channel status:', status);
        if (status === 'SUBSCRIBED') {
          console.log('✅ Successfully subscribed to real-time notifications');
        } else if (status === 'CHANNEL_ERROR') {
          console.error('❌ Error subscribing to notifications channel');
        }
      });

    return () => {
      console.log('🔔 Unsubscribing from notifications channel');
      supabase.removeChannel(channel);
    };
  }, [user]);

  const fetchNotifications = async () => {
    if (!user) return;

    const { data, error } = await (supabase as any)
      .from('notifications')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) {
      console.error('Error fetching notifications:', error);
      return;
    }

    setNotifications(data || []);
    setUnreadCount(data?.filter((n: any) => !n.is_read).length || 0);
  };

  const handleMarkAsRead = async (notificationId: string) => {
    await markNotificationRead(notificationId);
    setNotifications(prev =>
      prev.map(n => n.id === notificationId ? { ...n, is_read: true } : n)
    );
    setUnreadCount(prev => Math.max(0, prev - 1));
  };

  const handleMarkAllAsRead = async () => {
    if (!user) return;
    await markAllNotificationsRead(user.id);
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
    setUnreadCount(0);
    toast.success('All notifications marked as read');
  };

  const getNotificationIcon = (type: Notification['type']) => {
    switch (type) {
      case 'wrong_shelf':
        return '⚠️';
      case 'unknown_object':
        return '❓';
      case 'expired_reservation':
        return '⏰';
      case 'error':
        return '❌';
      case 'warning':
        return '⚠️';
      default:
        return '📖';
    }
  };

  const getNotificationColor = (type: Notification['type']) => {
    switch (type) {
      case 'wrong_shelf':
      case 'warning':
        return 'border-l-warning bg-warning/5';
      case 'unknown_object':
      case 'error':
        return 'border-l-destructive bg-destructive/5';
      default:
        return 'border-l-primary bg-primary/5';
    }
  };

  const renderNotificationDetails = (notification: Notification) => {
    const metadata = notification.metadata as any;
    
    if (!metadata) return null;

    return (
      <div className="mt-2 space-y-1 text-xs bg-muted/50 rounded p-2">
        {metadata.book_title && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Book:</span>
            <span className="font-medium">{metadata.book_title}</span>
          </div>
        )}
        {metadata.book_author && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Author:</span>
            <span>{metadata.book_author}</span>
          </div>
        )}
        {metadata.shelf_number !== undefined && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Shelf:</span>
            <span className="font-medium">Shelf {metadata.shelf_number}</span>
          </div>
        )}
        {metadata.student_name && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Student:</span>
            <span className="font-medium">{metadata.student_name}</span>
          </div>
        )}
        {metadata.student_email && !metadata.student_name && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Student:</span>
            <span className="font-medium text-xs">{metadata.student_email}</span>
          </div>
        )}
        {metadata.correct_shelf && metadata.wrong_shelf && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Expected:</span>
            <span className="font-medium text-green-600">Shelf {metadata.correct_shelf}</span>
            <span className="text-muted-foreground">→</span>
            <span className="font-medium text-red-600">Got: Shelf {metadata.wrong_shelf}</span>
          </div>
        )}
        {metadata.weight && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Weight:</span>
            <span className="font-medium">{metadata.weight}g</span>
          </div>
        )}
        {metadata.due_date && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Due:</span>
            <span className="font-medium">
              {new Date(metadata.due_date).toLocaleDateString('en-US', { 
                month: 'short', 
                day: 'numeric', 
                year: 'numeric' 
              })}
            </span>
          </div>
        )}
        {metadata.expires_at && (
          <div className="flex gap-2">
            <span className="text-muted-foreground">Expires:</span>
            <span className="font-medium text-orange-600">
              {new Date(metadata.expires_at).toLocaleTimeString('en-US', { 
                hour: '2-digit', 
                minute: '2-digit' 
              })}
            </span>
          </div>
        )}
      </div>
    );
  };

  if (!user) return null;

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="relative h-9 w-9 sm:h-10 sm:w-10"
        >
          <Bell className="h-4 w-4 sm:h-5 sm:w-5" />
          {unreadCount > 0 && (
            <Badge
              variant="destructive"
              className="absolute -top-1 -right-1 h-5 w-5 rounded-full p-0 flex items-center justify-center text-xs"
            >
              {unreadCount > 9 ? '9+' : unreadCount}
            </Badge>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 sm:w-96 p-0" align="end">
        <div className="flex items-center justify-between p-4 border-b">
          <h3 className="font-semibold text-sm sm:text-base">Notifications</h3>
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleMarkAllAsRead}
              className="text-xs"
            >
              <Check className="h-3 w-3 mr-1" />
              Mark all read
            </Button>
          )}
        </div>

        <ScrollArea className="h-[400px]">
          {notifications.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground text-sm">
              <Bell className="h-12 w-12 mx-auto mb-2 opacity-20" />
              <p>No notifications</p>
            </div>
          ) : (
            <div className="divide-y">
              {notifications.map((notification) => (
                <div
                  key={notification.id}
                  className={`p-4 border-l-4 transition-colors ${
                    getNotificationColor(notification.type)
                  } ${!notification.is_read ? 'bg-muted/30' : ''}`}
                >
                  <div className="flex items-start gap-3">
                    <div className="text-xl flex-shrink-0">
                      {getNotificationIcon(notification.type)}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2 mb-1">
                        <h4 className="font-semibold text-sm">
                          {notification.title}
                        </h4>
                        {!notification.is_read && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-6 w-6 flex-shrink-0"
                            onClick={() => handleMarkAsRead(notification.id)}
                          >
                            <X className="h-3 w-3" />
                          </Button>
                        )}
                      </div>
                      <p className="text-xs sm:text-sm text-muted-foreground mb-2">
                        {notification.message}
                      </p>
                      {renderNotificationDetails(notification)}
                      <p className="text-xs text-muted-foreground mt-2">
                        {formatDistanceToNow(new Date(notification.created_at), {
                          addSuffix: true,
                        })}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </ScrollArea>
      </PopoverContent>
    </Popover>
  );
};

export default NotificationBell;
