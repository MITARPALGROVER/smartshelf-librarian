import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { QrCode, Lock, Unlock, Loader2, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';

interface Shelf {
  id: string;
  shelf_number: number;
  current_weight: number;
  esp_ip_address?: string | null;
}

interface ShelfStatus {
  shelf_number: number;
  door_locked: boolean;
  current_weight: number;
  online: boolean;
}

export const ShelfDoorControl: React.FC = () => {
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [shelfStatuses, setShelfStatuses] = useState<Map<number, ShelfStatus>>(new Map());
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<number | null>(null);

  useEffect(() => {
    fetchShelves();
    const interval = setInterval(fetchShelfStatuses, 5000); // Poll every 5 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchShelves = async () => {
    try {
      const { data, error } = await supabase
        .from('shelves')
        .select('*')
        .order('shelf_number');

      if (error) throw error;
      setShelves(data || []);
      fetchShelfStatuses(data);
    } catch (error) {
      console.error('Error fetching shelves:', error);
      toast.error('Failed to load shelves');
    } finally {
      setLoading(false);
    }
  };

  const fetchShelfStatuses = async (shelvesData?: Shelf[]) => {
    const currentShelves = shelvesData || shelves;
    const statusMap = new Map<number, ShelfStatus>();

    for (const shelf of currentShelves) {
      if (shelf.esp_ip_address) {
        try {
          const response = await fetch(`http://${shelf.esp_ip_address}/status`, {
            method: 'GET',
            signal: AbortSignal.timeout(3000), // 3 second timeout
          });

          if (response.ok) {
            const data = await response.json();
            statusMap.set(shelf.shelf_number, {
              shelf_number: shelf.shelf_number,
              door_locked: data.door_locked,
              current_weight: data.current_weight,
              online: true,
            });
          } else {
            statusMap.set(shelf.shelf_number, {
              shelf_number: shelf.shelf_number,
              door_locked: true,
              current_weight: shelf.current_weight,
              online: false,
            });
          }
        } catch (error) {
          statusMap.set(shelf.shelf_number, {
            shelf_number: shelf.shelf_number,
            door_locked: true,
            current_weight: shelf.current_weight,
            online: false,
          });
        }
      }
    }

    setShelfStatuses(statusMap);
  };

  const handleDoorAction = async (shelf: Shelf, action: 'unlock' | 'lock') => {
    if (!shelf.esp_ip_address) {
      toast.error('ESP8266 not configured for this shelf');
      return;
    }

    setActionLoading(shelf.shelf_number);

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      const response = await fetch(`http://${shelf.esp_ip_address}/${action}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          qr_code: shelf.id,
          user_id: user?.id,
        }),
      });

      if (response.ok) {
        toast.success(`Door ${action}ed successfully!`);
        await fetchShelfStatuses();
      } else {
        throw new Error(`Failed to ${action} door`);
      }
    } catch (error) {
      console.error(`Error ${action}ing door:`, error);
      toast.error(`Failed to ${action} door. Check if shelf is online.`);
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loader2 className="w-8 h-8 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Shelf Door Control</h2>
        <Button onClick={() => fetchShelfStatuses()} variant="outline" size="sm">
          <RefreshCw className="w-4 h-4 mr-2" />
          Refresh
        </Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {shelves.map((shelf) => {
          const status = shelfStatuses.get(shelf.shelf_number);
          return (
            <Card key={shelf.id}>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  <span>Shelf {shelf.shelf_number}</span>
                  <Badge variant={status?.online ? 'default' : 'destructive'}>
                    {status?.online ? 'Online' : 'Offline'}
                  </Badge>
                </CardTitle>
                <CardDescription>
                  {shelf.esp_ip_address ? (
                    <span className="font-mono text-xs">{shelf.esp_ip_address}</span>
                  ) : (
                    <span className="text-red-500">No IP configured</span>
                  )}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600">Door Status:</span>
                  <Badge variant={status?.door_locked ? 'secondary' : 'default'}>
                    {status?.door_locked ? (
                      <>
                        <Lock className="w-3 h-3 mr-1" />
                        Locked
                      </>
                    ) : (
                      <>
                        <Unlock className="w-3 h-3 mr-1" />
                        Unlocked
                      </>
                    )}
                  </Badge>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600">Weight:</span>
                  <span className="font-semibold">{status?.current_weight?.toFixed(1) || '0.0'}g</span>
                </div>

                <div className="flex gap-2">
                  <Button
                    onClick={() => handleDoorAction(shelf, 'unlock')}
                    disabled={
                      !status?.online ||
                      !shelf.esp_ip_address ||
                      actionLoading === shelf.shelf_number
                    }
                    className="flex-1"
                    variant="default"
                  >
                    {actionLoading === shelf.shelf_number ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <>
                        <Unlock className="w-4 h-4 mr-2" />
                        Unlock
                      </>
                    )}
                  </Button>
                  <Button
                    onClick={() => handleDoorAction(shelf, 'lock')}
                    disabled={
                      !status?.online ||
                      !shelf.esp_ip_address ||
                      actionLoading === shelf.shelf_number
                    }
                    className="flex-1"
                    variant="outline"
                  >
                    <Lock className="w-4 h-4 mr-2" />
                    Lock
                  </Button>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
};
