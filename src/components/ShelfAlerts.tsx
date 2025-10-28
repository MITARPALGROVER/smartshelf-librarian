import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { AlertTriangle, CheckCircle, BookX, HelpCircle, X } from "lucide-react";
import { formatDistanceToNow } from "date-fns";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";

interface ShelfAlert {
  id: string;
  shelf_id: string;
  shelf_number: number;
  alert_type: string;
  message: string;
  weight_change: number;
  detected_at: string;
  resolved_at: string | null;
  resolved_by: string | null;
}

const ShelfAlerts = () => {
  const { user } = useAuth();
  const [alerts, setAlerts] = useState<ShelfAlert[]>([]);
  const [loading, setLoading] = useState(true);
  const [resolving, setResolving] = useState<string | null>(null);

  useEffect(() => {
    fetchAlerts();
    
    // Subscribe to real-time alert updates
    const alertsChannel = supabase
      .channel('shelf-alerts-monitor')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'shelves' // Listen to shelf changes to trigger refetch
        },
        () => {
          fetchAlerts();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(alertsChannel);
    };
  }, []);

  const fetchAlerts = async () => {
    // Use RPC call to fetch alerts (bypasses TypeScript type issues)
    const { data, error } = await (supabase as any)
      .rpc('get_unresolved_shelf_alerts');

    if (error) {
      console.error('Error fetching alerts:', error);
    } else if (data && Array.isArray(data)) {
      const formattedAlerts = data.map((alert: any) => ({
        id: alert.alert_id,
        shelf_id: '', // Not needed for display
        shelf_number: alert.shelf_number,
        alert_type: alert.alert_type,
        message: alert.message,
        weight_change: alert.weight_change,
        detected_at: alert.detected_at,
        resolved_at: null,
        resolved_by: null
      }));
      setAlerts(formattedAlerts);
    }

    setLoading(false);
  };

  const handleResolve = async (alertId: string) => {
    if (!user) return;
    
    setResolving(alertId);

    // Use RPC call to resolve alert
    const { error } = await (supabase as any)
      .rpc('resolve_shelf_alert', {
        alert_id: alertId,
        resolver_id: user.id
      });

    if (error) {
      toast.error('Failed to resolve alert');
      console.error(error);
    } else {
      toast.success('Alert resolved');
      fetchAlerts();
    }

    setResolving(null);
  };

  const getAlertIcon = (type: string) => {
    switch (type) {
      case 'wrong_shelf':
        return <BookX className="h-5 w-5" />;
      case 'unknown_object':
        return <HelpCircle className="h-5 w-5" />;
      default:
        return <AlertTriangle className="h-5 w-5" />;
    }
  };

  const getAlertColor = (type: string) => {
    switch (type) {
      case 'wrong_shelf':
        return 'warning';
      case 'unknown_object':
        return 'secondary';
      default:
        return 'destructive';
    }
  };

  const getAlertTitle = (type: string) => {
    switch (type) {
      case 'wrong_shelf':
        return 'Book on Wrong Shelf';
      case 'unknown_object':
        return 'Unknown Object Detected';
      default:
        return 'Shelf Alert';
    }
  };

  if (loading) {
    return null;
  }

  if (alerts.length === 0) {
    return null;
  }

  return (
    <Card className="shadow-card border-warning">
      <CardHeader>
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 sm:gap-0">
          <div>
            <CardTitle className="flex items-center gap-2 text-warning text-lg sm:text-xl">
              <AlertTriangle className="h-4 w-4 sm:h-5 sm:w-5" />
              Shelf Alerts
            </CardTitle>
            <CardDescription className="text-xs sm:text-sm">
              Issues detected with shelf contents
            </CardDescription>
          </div>
          <Badge variant="warning" className="text-base sm:text-lg px-2 sm:px-3 py-0.5 sm:py-1 self-start sm:self-auto">
            {alerts.length}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-2 sm:space-y-3">
        {alerts.map((alert) => (
          <Alert key={alert.id} variant={getAlertColor(alert.alert_type) as any}>
            <div className="flex items-start gap-2 sm:gap-3">
              <div className="mt-0.5 flex-shrink-0">
                {getAlertIcon(alert.alert_type)}
              </div>
              <div className="flex-1 min-w-0">
                <AlertTitle className="text-xs sm:text-sm font-semibold mb-1">
                  {getAlertTitle(alert.alert_type)}
                </AlertTitle>
                <AlertDescription className="text-xs sm:text-sm">
                  {alert.message}
                </AlertDescription>
                <div className="flex flex-wrap items-center gap-2 sm:gap-3 mt-2 text-xs text-muted-foreground">
                  <span>Shelf {alert.shelf_number}</span>
                  <span className="hidden sm:inline">•</span>
                  <span className="truncate max-w-[120px] sm:max-w-none">
                    {formatDistanceToNow(new Date(alert.detected_at), { addSuffix: true })}
                  </span>
                  <span className="hidden sm:inline">•</span>
                  <span>{alert.weight_change.toFixed(0)}g</span>
                </div>
              </div>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => handleResolve(alert.id)}
                disabled={resolving === alert.id}
                className="hover:bg-success/10 h-8 w-8 sm:h-9 sm:w-9 flex-shrink-0"
              >
                {resolving === alert.id ? (
                  <X className="h-3 w-3 sm:h-4 sm:w-4 animate-spin" />
                ) : (
                  <CheckCircle className="h-3 w-3 sm:h-4 sm:w-4 text-success" />
                )}
              </Button>
            </div>
          </Alert>
        ))}
      </CardContent>
    </Card>
  );
};

export default ShelfAlerts;
