import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "sonner";
import { Wifi, Save, RefreshCw } from "lucide-react";
import { Badge } from "@/components/ui/badge";

interface Shelf {
  id: string;
  shelf_number: number;
  esp_ip_address: string | null;
}

const ShelfIPManager = () => {
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [ipAddresses, setIpAddresses] = useState<{ [key: string]: string }>({});

  useEffect(() => {
    fetchShelves();
  }, []);

  const fetchShelves = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("shelves")
      .select("*")
      .order("shelf_number");

    if (error) {
      console.error("Error fetching shelves:", error);
      toast.error("Failed to load shelves");
    } else {
      setShelves(data as Shelf[]);
      
      // Initialize IP addresses state
      const ips: { [key: string]: string } = {};
      data.forEach((shelf) => {
        ips[shelf.id] = shelf.esp_ip_address || "";
      });
      setIpAddresses(ips);
    }
    setLoading(false);
  };

  const handleIPChange = (shelfId: string, value: string) => {
    setIpAddresses({
      ...ipAddresses,
      [shelfId]: value,
    });
  };

  const handleSaveIP = async (shelfId: string) => {
    const ipAddress = ipAddresses[shelfId];
    
    // Validate IP address format
    const ipPattern = /^(\d{1,3}\.){3}\d{1,3}$/;
    if (ipAddress && !ipPattern.test(ipAddress)) {
      toast.error("Invalid IP address format. Use format: 192.168.1.100");
      return;
    }

    setSaving(shelfId);
    
    const { error } = await supabase
      .from("shelves")
      .update({ esp_ip_address: ipAddress || null })
      .eq("id", shelfId);

    if (error) {
      console.error("Error updating IP address:", error);
      toast.error("Failed to update IP address");
    } else {
      toast.success("IP address updated successfully");
      fetchShelves(); // Refresh the list
    }
    
    setSaving(null);
  };

  const testConnection = async (ipAddress: string | null) => {
    if (!ipAddress) {
      toast.error("No IP address configured");
      return;
    }

    toast.loading("Testing connection...", { id: "test-connection" });

    try {
      const response = await fetch(`http://${ipAddress}/status`, {
        method: "GET",
        signal: AbortSignal.timeout(5000), // 5 second timeout
      });

      if (response.ok) {
        const data = await response.json();
        toast.success(
          `Connected! Status: ${data.status || "OK"}`,
          { id: "test-connection" }
        );
      } else {
        toast.error(
          `Connection failed: ${response.status}`,
          { id: "test-connection" }
        );
      }
    } catch (error) {
      console.error("Connection test error:", error);
      toast.error(
        "Cannot reach ESP8266. Check if it's powered on and connected to WiFi.",
        { id: "test-connection" }
      );
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

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
          <Wifi className="h-4 w-4 sm:h-5 sm:w-5 text-primary" />
          Shelf Hardware Configuration
        </CardTitle>
        <CardDescription className="text-xs sm:text-sm">
          Configure ESP8266 IP addresses for each smart shelf
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3 sm:space-y-4">
        {shelves.length === 0 ? (
          <p className="text-muted-foreground text-center py-4 text-sm">No shelves configured</p>
        ) : (
          shelves.map((shelf) => (
            <div
              key={shelf.id}
              className="p-3 sm:p-4 border rounded-lg space-y-2 sm:space-y-3 hover:bg-muted/50 transition-colors"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <h3 className="font-semibold text-base sm:text-lg truncate">
                    Shelf {shelf.shelf_number}
                  </h3>
                </div>
                {shelf.esp_ip_address ? (
                  <Badge variant="success" className="text-xs">
                    ✓ Configured
                  </Badge>
                ) : (
                  <Badge variant="secondary" className="text-xs">
                    Not Configured
                  </Badge>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor={`ip-${shelf.id}`} className="text-xs sm:text-sm">
                  ESP8266 IP Address
                </Label>
                <div className="flex flex-col sm:flex-row gap-2">
                  <Input
                    id={`ip-${shelf.id}`}
                    type="text"
                    placeholder="192.168.1.100"
                    value={ipAddresses[shelf.id] || ""}
                    onChange={(e) => handleIPChange(shelf.id, e.target.value)}
                    className="font-mono text-xs sm:text-sm flex-1"
                  />
                  <Button
                    onClick={() => handleSaveIP(shelf.id)}
                    disabled={
                      saving === shelf.id ||
                      ipAddresses[shelf.id] === shelf.esp_ip_address
                    }
                    size="sm"
                    className="w-full sm:w-auto"
                  >
                    {saving === shelf.id ? (
                      <>
                        <RefreshCw className="mr-2 h-3 w-3 sm:h-4 sm:w-4 animate-spin" />
                        <span className="text-xs sm:text-sm">Saving</span>
                      </>
                    ) : (
                      <>
                        <Save className="mr-2 h-3 w-3 sm:h-4 sm:w-4" />
                        <span className="text-xs sm:text-sm">Save</span>
                      </>
                    )}
                  </Button>
                </div>
                <p className="text-xs text-muted-foreground leading-tight">
                  Find the IP address in the Arduino Serial Monitor when the ESP8266 connects to WiFi
                </p>
              </div>

              {shelf.esp_ip_address && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => testConnection(shelf.esp_ip_address)}
                  className="w-full text-xs sm:text-sm"
                >
                  <Wifi className="mr-2 h-3 w-3 sm:h-4 sm:w-4" />
                  Test Connection
                </Button>
              )}
            </div>
          ))
        )}

        <div className="mt-4 sm:mt-6 p-3 sm:p-4 bg-muted/50 rounded-lg">
          <h4 className="font-semibold text-xs sm:text-sm mb-2">How to find your ESP8266 IP address:</h4>
          <ol className="text-xs text-muted-foreground space-y-1 list-decimal list-inside leading-relaxed">
            <li>Upload the Smart Shelf code to your ESP8266</li>
            <li>Open Arduino IDE Serial Monitor (115200 baud)</li>
            <li>Look for "IP Address: 192.168.x.x" in the startup logs</li>
            <li>Copy that IP address and paste it here</li>
            <li>Click "Test Connection" to verify it works</li>
          </ol>
        </div>
      </CardContent>
    </Card>
  );
};

export default ShelfIPManager;
