import React, { useState, useEffect } from 'react';
import { Html5Qrcode } from 'html5-qrcode';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Loader2, QrCode, Lock, Unlock, CheckCircle, XCircle } from 'lucide-react';
import { toast } from 'sonner';

interface QRScannerProps {
  shelfId: string;
  shelfNumber: number;
  bookId?: string;
  onSuccess?: () => void;
}

export const QRScanner: React.FC<QRScannerProps> = ({ shelfId, shelfNumber, bookId, onSuccess }) => {
  const [scanning, setScanning] = useState(false);
  const [scanner, setScanner] = useState<Html5Qrcode | null>(null);
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [doorStatus, setDoorStatus] = useState<'locked' | 'unlocked' | null>(null);

  // Auto-start camera when component mounts
  useEffect(() => {
    let mounted = true;
    const timer = setTimeout(() => {
      if (mounted && !scanner) {
        startScanning();
      }
    }, 100);
    
    return () => {
      mounted = false;
      clearTimeout(timer);
      // Cleanup scanner on unmount - IMPORTANT for camera cleanup
      if (scanner) {
        scanner.stop().catch(() => {}).finally(() => {
          try {
            scanner.clear();
          } catch (e) {
            // Ignore
          }
        });
      }
    };
  }, []);

  const startScanning = async () => {
    try {
      // Check if element exists
      const qrReaderElement = document.getElementById('qr-reader');
      if (!qrReaderElement) {
        throw new Error('QR reader element not found');
      }

      // Stop any existing scanner first
      if (scanner) {
        try {
          await scanner.clear();
        } catch (e) {
          // Ignore
        }
      }

      setScanning(true);
      setResult(null);

      const qrScanner = new Html5Qrcode('qr-reader');
      
      // Request camera permissions explicitly
      const cameras = await Html5Qrcode.getCameras();
      if (!cameras || cameras.length === 0) {
        throw new Error('No cameras found on device');
      }

      await qrScanner.start(
        { facingMode: "environment" }, // Use back camera on mobile
        {
          fps: 10,
          qrbox: { width: 250, height: 250 },
          aspectRatio: 1.0,
        },
        (decodedText) => {
          // Success callback - QR code detected
          setResult(decodedText);
          // Stop scanner and handle result
          qrScanner.stop().then(() => {
            qrScanner.clear();
            setScanning(false);
            setScanner(null);
            handleQRCodeSuccess(decodedText);
          }).catch(() => {
            // Scanner already stopped
            setScanning(false);
            setScanner(null);
            handleQRCodeSuccess(decodedText);
          });
        },
        (errorMessage) => {
          // Error callback (called continuously, so we don't log it)
        }
      );

      setScanner(qrScanner);
    } catch (err: any) {
      console.error('Failed to start scanner:', err);
      const errorMsg = err?.message || 'Unknown error';
      toast.error('Camera Error', {
        description: errorMsg.includes('Permission') || errorMsg.includes('NotAllowed')
          ? 'Camera permission denied. Please allow camera access.'
          : 'Could not access camera. Please check permissions and try again.',
        duration: 5000,
      });
      setScanning(false);
      setScanner(null);
    }
  };

  const stopScanning = async () => {
    if (scanner) {
      try {
        // Stop the scanner
        await scanner.stop();
        // Clear the camera stream
        await scanner.clear();
      } catch (err) {
        // If stop fails, force clear
        try {
          await scanner.clear();
        } catch (clearErr) {
          console.log('Scanner cleanup completed');
        }
      } finally {
        setScanner(null);
        setScanning(false);
      }
    } else {
      setScanning(false);
    }
  };

  const handleQRCodeSuccess = async (qrCode: string) => {
    // Prevent multiple calls
    if (loading) return;
    
    setLoading(true);

    try {
      // Verify QR code matches the shelf
      if (qrCode !== shelfId && qrCode !== shelfNumber.toString()) {
        toast.error('❌ Wrong QR Code!', {
          description: `This is not the QR code for Shelf ${shelfNumber}. Please scan the correct shelf.`,
          duration: 5000,
        });
        setLoading(false);
        setResult(null);
        // Restart scanning after 2 seconds
        setTimeout(async () => {
          await startScanning();
        }, 2000);
        return;
      }

      // Get ESP8266 IP from shelves table
      const { data: shelfData, error: shelfError } = await supabase
        .from('shelves')
        .select('*')
        .eq('shelf_number', shelfNumber)
        .single();

      if (shelfError || !(shelfData as any)?.esp_ip_address) {
        toast.error('Shelf Configuration Error', {
          description: 'ESP8266 IP address not configured for this shelf',
        });
        setLoading(false);
        return;
      }

      const espIP = (shelfData as any).esp_ip_address;
      const actualShelfId = (shelfData as any).id; // Use the actual shelf UUID from database

      // Get current user
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        toast.error('Authentication Error', {
          description: 'Please log in to unlock the door',
        });
        setLoading(false);
        return;
      }

      // Send unlock request to ESP8266
      let hardwareConnected = false;
      
      try {
        const response = await fetch(`http://${espIP}/unlock`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            qr_code: qrCode,
            user_id: user.id,
          }),
        });

        if (response.ok) {
          hardwareConnected = true;
        }
      } catch (error) {
        console.log('Hardware not connected, using DEMO mode');
        hardwareConnected = false;
      }

      // Continue regardless of hardware status (for demo/testing)
      setDoorStatus('unlocked');
      
      // Record door unlock event (critical for auto-issuing books!)
      const { data: unlockData, error: unlockError } = await (supabase as any).from('door_unlock_events').insert({
        shelf_id: actualShelfId, // Use the actual UUID from database query
        user_id: user.id,
        unlocked_at: new Date().toISOString(),
        book_issued: false,
        book_id: bookId || null,
      });

      if (unlockError) {
        console.error('Failed to record unlock event:', unlockError);
        toast.error('Warning: Failed to record unlock event', {
          description: unlockError.message,
        });
      } else {
        console.log('Door unlock event recorded:', unlockData);
      }

      if (hardwareConnected) {
        toast.success('Door Unlocked! 🔓', {
          description: `Shelf ${shelfNumber} door is now unlocked. Pick up your book within 1 minute. It will be auto-issued to you!`,
        });
      } else {
        toast.success('✅ DEMO MODE - Door Unlocked!', {
          description: `Hardware not connected. In real mode, Shelf ${shelfNumber} door would unlock. You can test by clicking "Simulate Book Pickup" below.`,
          duration: 10000,
        });
      }

      // Notify librarian
      await (supabase as any).from('notifications').insert({
        user_id: user.id,
        type: 'info',
        title: hardwareConnected ? '🔓 Door Unlocked' : '🧪 DEMO: Door Unlocked',
        message: `Student accessed Shelf ${shelfNumber}${bookId ? ' to pickup a book' : ''}`,
        metadata: {
          shelf_id: shelfId,
          shelf_number: shelfNumber,
          book_id: bookId,
          action: 'door_unlocked',
          demo_mode: !hardwareConnected,
        },
      });

      if (onSuccess) {
        onSuccess();
      }
    } catch (error) {
      console.error('QR unlock error:', error);
      toast.error('Connection Error', {
        description: 'Could not connect to shelf. Please check if the shelf is online.',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleManualUnlock = async () => {
    await handleQRCodeSuccess(shelfId);
  };

  return (
    <div className="space-y-4 max-h-[70vh] overflow-y-auto">
      {/* QR Scanner */}
      {!loading && !doorStatus && (
        <div className="space-y-3">
          <div id="qr-reader" className="w-full"></div>
        <div className="flex gap-2">
          <Button onClick={stopScanning} variant="outline" className="flex-1" size="sm">
            Cancel
          </Button>
          <Button
            onClick={handleManualUnlock}
            variant="secondary"
            className="flex-1"
            size="sm"
            disabled={loading}
          >
            Unlock Without Scanning
          </Button>
        </div>
        </div>
      )}

      {/* Loading State */}
      {loading && (
        <div className="flex flex-col items-center justify-center py-6 space-y-2">
          <Loader2 className="w-10 h-10 animate-spin text-primary" />
          <p className="text-base font-medium">Unlocking door...</p>
          <p className="text-xs text-muted-foreground">Please wait</p>
        </div>
      )}

      {/* Success State */}
      {doorStatus === 'unlocked' && (
        <Alert className="bg-green-50 border-green-200">
          <Unlock className="w-4 h-4 text-green-600" />
          <AlertDescription className="text-green-800">
            <div className="space-y-1.5">
              <p className="font-semibold text-base">🎉 Door Unlocked!</p>
              <p className="text-sm">You can now pick up your book.</p>
              <p className="text-xs">⏱️ Auto-lock in 1 min • 📚 Auto-issue on pickup</p>
            </div>
          </AlertDescription>
        </Alert>
      )}

      {/* Initializing State */}
      {!scanning && !loading && !doorStatus && (
        <div className="text-center py-3">
          <p className="text-sm text-muted-foreground">Initializing camera...</p>
        </div>
      )}

      {/* Instructions - Compact */}
      {!doorStatus && (
        <div className="p-3 bg-blue-50 rounded-lg border border-blue-200">
          <h4 className="font-semibold text-sm text-blue-900 mb-1.5 flex items-center gap-2">
            <QrCode className="w-4 h-4" />
            Instructions:
          </h4>
          <ol className="text-xs text-blue-800 space-y-0.5 list-decimal list-inside">
            <li>Allow camera access when prompted</li>
            <li>Point your camera at the QR code on Shelf {shelfNumber}</li>
            <li>Wait for the door to unlock (servo motor will move)</li>
            <li>Open the door and pick up the book within 1 minute</li>
            <li>Book will be automatically issued to you!</li>
          </ol>
        </div>
      )}
    </div>
  );
};
