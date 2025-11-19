import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { Scale, RefreshCw, Activity, TrendingDown, TrendingUp } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

interface Shelf {
  id: string;
  shelf_number: number;
  esp_ip_address: string | null;
}

interface WeightEvent {
  id: string;
  action: string;
  current_weight: number;
  previous_weight: number;
  weight_change: number;
  detected_at: string;
  profiles: {
    full_name: string;
    email: string;
  } | null;
}

interface WeightReading {
  weight: number;
  weight_change: number;
  empty_shelf_weight: number;
  calibration_factor: number;
  stable: boolean;
  sensor_status: string;
  error?: string;
}

const WeightSensorTester = () => {
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [selectedShelf, setSelectedShelf] = useState<Shelf | null>(null);
  const [weightReading, setWeightReading] = useState<WeightReading | null>(null);
  const [weightEvents, setWeightEvents] = useState<WeightEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(false);

  useEffect(() => {
    fetchShelves();
  }, []);

  useEffect(() => {
    if (selectedShelf) {
      fetchWeightEvents(selectedShelf.id);
    }
  }, [selectedShelf]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (autoRefresh && selectedShelf) {
      interval = setInterval(() => {
        fetchCurrentWeight(selectedShelf);
      }, 2000); // Refresh every 2 seconds
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [autoRefresh, selectedShelf]);

  const fetchShelves = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("shelves")
      .select("id, shelf_number, esp_ip_address")
      .not("esp_ip_address", "is", null)
      .order("shelf_number");

    if (error) {
      console.error("Error fetching shelves:", error);
      toast.error("Failed to load shelves");
    } else {
      setShelves(data as Shelf[]);
      if (data && data.length > 0) {
        setSelectedShelf(data[0]);
      }
    }
    setLoading(false);
  };

  const fetchWeightEvents = async (shelfId: string) => {
    // Weight events table doesn't exist in simplified system
    // Just show empty for now
    setWeightEvents([]);
  };

  const fetchCurrentWeight = async (shelf: Shelf) => {
    if (!shelf.esp_ip_address) {
      toast.error("No IP address configured for this shelf");
      return;
    }

    setTesting(true);

    try {
      const response = await fetch(`http://${shelf.esp_ip_address}/status`, {
        method: "GET",
        signal: AbortSignal.timeout(5000),
      });

      if (response.ok) {
        const data = await response.json();
        // Convert status response to weight reading format
        setWeightReading({
          weight: data.current_weight || 0,
          weight_change: data.weight_change || 0,
          empty_shelf_weight: data.baseline_weight || 0,
          calibration_factor: -1850,
          stable: true,
          sensor_status: data.weight_sensor ? "connected" : "disconnected"
        });
        
        if (!data.weight_sensor) {
          toast.error("Weight sensor not connected!");
        }
      } else {
        toast.error(`Failed to read weight: ${response.status}`);
        setWeightReading(null);
      }
    } catch (error) {
      console.error("Weight reading error:", error);
      toast.error("Cannot reach ESP8266. Check if it's powered on.");
      setWeightReading(null);
    }

    setTesting(false);
  };

  const testConnection = async (shelf: Shelf) => {
    if (!shelf.esp_ip_address) {
      toast.error("No IP address configured");
      return;
    }

    toast.loading("Testing connection...", { id: "test-weight" });

    try {
      const response = await fetch(`http://${shelf.esp_ip_address}/status`, {
        method: "GET",
        signal: AbortSignal.timeout(5000),
      });

      if (response.ok) {
        const data = await response.json();
        toast.success(
          `Connected! Status: ${data.status}, Uptime: ${data.uptime}s`,
          { id: "test-weight" }
        );
        fetchCurrentWeight(shelf);
      } else {
        toast.error(`Connection failed: ${response.status}`, { id: "test-weight" });
      }
    } catch (error) {
      toast.error("Cannot reach ESP8266", { id: "test-weight" });
    }
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

  if (shelves.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
            <Scale className="h-4 w-4 sm:h-5 sm:w-5 text-primary" />
            Weight Sensor Testing
          </CardTitle>
          <CardDescription className="text-xs sm:text-sm">
            No shelves with IP addresses configured. Please configure shelf IP addresses first.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Shelf Selection */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
            <Scale className="h-4 w-4 sm:h-5 sm:w-5 text-primary" />
            Weight Sensor Testing
          </CardTitle>
          <CardDescription className="text-xs sm:text-sm">
            Test weight sensors and monitor pickup/return events
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-wrap gap-2">
            {shelves.map((shelf) => (
              <Button
                key={shelf.id}
                variant={selectedShelf?.id === shelf.id ? "default" : "outline"}
                size="sm"
                onClick={() => setSelectedShelf(shelf)}
                className="text-xs sm:text-sm"
              >
                Shelf {shelf.shelf_number}
              </Button>
            ))}
          </div>

          {selectedShelf && (
            <div className="space-y-3 pt-4 border-t">
              <div className="flex flex-col sm:flex-row gap-2">
                <Button
                  onClick={() => testConnection(selectedShelf)}
                  disabled={testing}
                  className="flex-1 text-xs sm:text-sm"
                >
                  <Activity className="mr-2 h-3 w-3 sm:h-4 sm:w-4" />
                  Test Connection
                </Button>
                <Button
                  onClick={() => fetchCurrentWeight(selectedShelf)}
                  disabled={testing}
                  variant="outline"
                  className="flex-1 text-xs sm:text-sm"
                >
                  <RefreshCw className={`mr-2 h-3 w-3 sm:h-4 sm:w-4 ${testing ? "animate-spin" : ""}`} />
                  Read Weight
                </Button>
                <Button
                  onClick={() => setAutoRefresh(!autoRefresh)}
                  variant={autoRefresh ? "destructive" : "secondary"}
                  className="flex-1 text-xs sm:text-sm"
                >
                  {autoRefresh ? "Stop" : "Start"} Auto-Refresh
                </Button>
              </div>

              <div className="text-xs text-muted-foreground">
                IP: {selectedShelf.esp_ip_address}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Current Weight Reading */}
      {weightReading && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base sm:text-lg">Current Weight Reading</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Current Weight</p>
                <p className="text-xl sm:text-2xl font-bold">
                  {weightReading.weight.toFixed(1)} g
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Weight Change</p>
                <p className="text-xl sm:text-2xl font-bold">
                  {weightReading.weight_change.toFixed(1)} g
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Empty Shelf</p>
                <p className="text-base sm:text-lg font-semibold">
                  {weightReading.empty_shelf_weight.toFixed(1)} g
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Status</p>
                <Badge
                  variant={
                    weightReading.sensor_status === "connected"
                      ? "success"
                      : "destructive"
                  }
                  className="text-xs"
                >
                  {weightReading.sensor_status}
                </Badge>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 pt-2 border-t">
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Calibration Factor</p>
                <p className="text-sm font-mono">{weightReading.calibration_factor}</p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground">Stable</p>
                <Badge variant={weightReading.stable ? "success" : "secondary"} className="text-xs">
                  {weightReading.stable ? "Yes" : "No"}
                </Badge>
              </div>
            </div>

            {weightReading.error && (
              <div className="p-3 bg-destructive/10 border border-destructive/20 rounded text-xs text-destructive">
                {weightReading.error}
              </div>
            )}

            <div className="p-3 bg-muted/50 rounded text-xs space-y-1">
              <p className="font-semibold">Testing Tips:</p>
              <ul className="list-disc list-inside space-y-1 text-muted-foreground">
                <li>Place a book on the shelf to simulate pickup</li>
                <li>Remove the book to test return detection</li>
                <li>Watch for weight change events below</li>
                <li>Threshold: 50g minimum for detection</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Recent Weight Events */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <div>
            <CardTitle className="text-base sm:text-lg">Recent Weight Events</CardTitle>
            <CardDescription className="text-xs sm:text-sm">
              Last 10 pickup/return events for this shelf
            </CardDescription>
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => selectedShelf && fetchWeightEvents(selectedShelf.id)}
          >
            <RefreshCw className="h-3 w-3 sm:h-4 sm:w-4" />
          </Button>
        </CardHeader>
        <CardContent>
          {weightEvents.length === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-6">
              No weight events recorded yet. Test the sensor by placing or removing a book!
            </p>
          ) : (
            <div className="space-y-2">
              {weightEvents.map((event) => (
                <div
                  key={event.id}
                  className="p-3 border rounded-lg hover:bg-muted/50 transition-colors"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex items-start gap-2 flex-1">
                      {event.action === "pickup" ? (
                        <TrendingDown className="h-4 w-4 text-destructive mt-0.5 flex-shrink-0" />
                      ) : (
                        <TrendingUp className="h-4 w-4 text-success mt-0.5 flex-shrink-0" />
                      )}
                      <div className="space-y-1 flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <Badge
                            variant={event.action === "pickup" ? "destructive" : "success"}
                            className="text-xs"
                          >
                            {event.action.toUpperCase()}
                          </Badge>
                          <span className="text-xs text-muted-foreground truncate">
                            {formatDistanceToNow(new Date(event.detected_at), {
                              addSuffix: true,
                            })}
                          </span>
                        </div>
                        {event.profiles && (
                          <p className="text-xs text-muted-foreground truncate">
                            User: {event.profiles.full_name || event.profiles.email}
                          </p>
                        )}
                      </div>
                    </div>
                    <div className="text-right flex-shrink-0">
                      <p className="text-sm font-semibold">
                        {event.weight_change > 0 ? "+" : ""}
                        {event.weight_change.toFixed(1)}g
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {event.current_weight.toFixed(1)}g
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default WeightSensorTester;
