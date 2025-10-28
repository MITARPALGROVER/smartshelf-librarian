import { useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { 
  Activity, 
  BookOpen, 
  Scale, 
  AlertTriangle, 
  RotateCcw,
  Play,
  StopCircle
} from "lucide-react";
import { toast } from "sonner";
import {
  simulateWeightReading,
  simulateBookPickup,
  simulateBookReturn,
  simulateWrongShelf,
  simulateUnknownObject,
  resetShelf,
  startAutoSimulation,
  getSimulationSuggestions
} from "@/lib/dummyIoT";

/**
 * 🧪 TESTING PANEL
 * UI for testing IoT features without physical hardware
 * 
 * ⚠️ REMOVE THIS PAGE BEFORE PRODUCTION DEPLOYMENT!
 */

const TestingPanel = () => {
  const [shelfNumber, setShelfNumber] = useState(1);
  const [weight, setWeight] = useState(350);
  const [autoSimRunning, setAutoSimRunning] = useState(false);
  const [stopAutoSim, setStopAutoSim] = useState<(() => void) | null>(null);

  const handleSimulateWeight = async () => {
    const result = await simulateWeightReading(shelfNumber, weight);
    if (result.success) {
      toast.success(`Shelf ${shelfNumber} updated to ${weight}g`);
    } else {
      toast.error(result.error || 'Failed to simulate');
    }
  };

  const handleBookPickup = async () => {
    const result = await simulateBookPickup(shelfNumber, weight);
    if (result.success) {
      toast.success(`Simulated book pickup from Shelf ${shelfNumber}`);
    } else {
      toast.error(result.error || 'Failed to simulate');
    }
  };

  const handleBookReturn = async () => {
    const result = await simulateBookReturn(shelfNumber, weight);
    if (result.success) {
      toast.success(`Simulated book return to Shelf ${shelfNumber}`);
    } else {
      toast.error(result.error || 'Failed to simulate');
    }
  };

  const handleWrongShelf = async () => {
    const correctShelf = shelfNumber === 1 ? 2 : 1;
    const result = await simulateWrongShelf(correctShelf, shelfNumber, weight);
    if (result.success) {
      toast.warning(`Simulated wrong shelf placement on Shelf ${shelfNumber}`);
    } else {
      toast.error(result.error || 'Failed to simulate');
    }
  };

  const handleUnknownObject = async () => {
    const result = await simulateUnknownObject(shelfNumber, 123);
    if (result.success) {
      toast.warning(`Simulated unknown object on Shelf ${shelfNumber}`);
    } else {
      toast.error(result.error || 'Failed to simulate');
    }
  };

  const handleReset = async () => {
    const result = await resetShelf(shelfNumber);
    if (result.success) {
      toast.success(`Shelf ${shelfNumber} reset to 0g`);
    } else {
      toast.error(result.error || 'Failed to reset');
    }
  };

  const handleAutoSimToggle = () => {
    if (autoSimRunning && stopAutoSim) {
      stopAutoSim();
      setStopAutoSim(null);
      setAutoSimRunning(false);
      toast.info('Auto-simulation stopped');
    } else {
      const stopFn = startAutoSimulation(shelfNumber, weight);
      setStopAutoSim(() => stopFn);
      setAutoSimRunning(true);
      toast.info('Auto-simulation started');
    }
  };

  const handleGetSuggestions = async () => {
    const suggestions = await getSimulationSuggestions();
    if (suggestions.length > 0) {
      toast.info(`Found ${suggestions.length} test suggestion(s)`, {
        description: 'Check browser console for details'
      });
    } else {
      toast.info('No active reservations to test');
    }
  };

  return (
    <div className="space-y-6 sm:space-y-8">
      <div>
        <div className="flex items-center gap-3 mb-2">
          <Activity className="h-8 w-8 text-warning" />
          <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold">IoT Testing Panel</h1>
        </div>
        <p className="text-sm sm:text-base text-muted-foreground">
          Simulate ESP8266 sensor behavior without physical hardware
        </p>
        <Badge variant="destructive" className="mt-2">
          Development Only - Remove Before Production
        </Badge>
      </div>

      {/* Quick Test Scenarios */}
      <Card className="shadow-card border-warning">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg sm:text-xl">
            <BookOpen className="h-5 w-5" />
            Quick Test Scenarios
          </CardTitle>
          <CardDescription className="text-xs sm:text-sm">
            Common testing workflows
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="bg-muted/50 rounded-lg p-4 space-y-2 text-sm">
            <h4 className="font-semibold">📋 Test Flow:</h4>
            <ol className="list-decimal list-inside space-y-1 text-xs sm:text-sm">
              <li>Create books and assign to shelves (Admin Dashboard)</li>
              <li>Reserve a book as student (Student Dashboard)</li>
              <li>Use "Get Test Suggestions" below</li>
              <li>Simulate book pickup to auto-issue the book</li>
              <li>Check issued books in Student/Librarian Dashboard</li>
            </ol>
          </div>

          <Button 
            onClick={handleGetSuggestions}
            variant="outline"
            className="w-full"
          >
            💡 Get Test Suggestions (Based on Active Reservations)
          </Button>
        </CardContent>
      </Card>

      {/* Control Panel */}
      <div className="grid gap-4 sm:gap-6 grid-cols-1 lg:grid-cols-2">
        {/* Basic Controls */}
        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="text-base sm:text-lg">Basic Simulation</CardTitle>
            <CardDescription className="text-xs sm:text-sm">
              Manual weight control
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="shelf" className="text-xs sm:text-sm">Shelf Number</Label>
              <Input
                id="shelf"
                type="number"
                min={1}
                max={10}
                value={shelfNumber}
                onChange={(e) => setShelfNumber(parseInt(e.target.value) || 1)}
                className="text-sm"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="weight" className="text-xs sm:text-sm">Weight (grams)</Label>
              <Input
                id="weight"
                type="number"
                min={0}
                max={5000}
                value={weight}
                onChange={(e) => setWeight(parseInt(e.target.value) || 0)}
                className="text-sm"
              />
            </div>

            <Button 
              onClick={handleSimulateWeight}
              className="w-full"
              variant="accent"
            >
              <Scale className="h-4 w-4 mr-2" />
              Set Weight
            </Button>

            <div className="grid grid-cols-2 gap-2">
              <Button 
                onClick={handleBookPickup}
                size="sm"
                variant="outline"
                className="text-xs"
              >
                📖 Pickup
              </Button>
              <Button 
                onClick={handleBookReturn}
                size="sm"
                variant="outline"
                className="text-xs"
              >
                📚 Return
              </Button>
            </div>

            <Button 
              onClick={handleReset}
              variant="ghost"
              className="w-full text-xs"
            >
              <RotateCcw className="h-3 w-3 mr-2" />
              Reset to 0g
            </Button>
          </CardContent>
        </Card>

        {/* Advanced Tests */}
        <Card className="shadow-card">
          <CardHeader>
            <CardTitle className="text-base sm:text-lg">Advanced Tests</CardTitle>
            <CardDescription className="text-xs sm:text-sm">
              Test error detection
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button 
              onClick={handleWrongShelf}
              variant="outline"
              className="w-full text-sm"
            >
              <AlertTriangle className="h-4 w-4 mr-2 text-warning" />
              Simulate Wrong Shelf
            </Button>

            <Button 
              onClick={handleUnknownObject}
              variant="outline"
              className="w-full text-sm"
            >
              <AlertTriangle className="h-4 w-4 mr-2 text-destructive" />
              Simulate Unknown Object
            </Button>

            <div className="border-t pt-3 mt-3">
              <Button 
                onClick={handleAutoSimToggle}
                variant={autoSimRunning ? "destructive" : "default"}
                className="w-full text-sm"
              >
                {autoSimRunning ? (
                  <>
                    <StopCircle className="h-4 w-4 mr-2" />
                    Stop Auto-Simulation
                  </>
                ) : (
                  <>
                    <Play className="h-4 w-4 mr-2" />
                    Start Auto-Simulation
                  </>
                )}
              </Button>
              <p className="text-xs text-muted-foreground mt-2 text-center">
                Simulates sensor with random fluctuations
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Console Instructions */}
      <Card className="shadow-card bg-muted/30">
        <CardHeader>
          <CardTitle className="text-base sm:text-lg">Browser Console Commands</CardTitle>
          <CardDescription className="text-xs sm:text-sm">
            Advanced testing via console (F12)
          </CardDescription>
        </CardHeader>
        <CardContent>
          <pre className="text-xs bg-black/80 text-green-400 p-3 sm:p-4 rounded-lg overflow-x-auto">
{`// Update weight
iotSimulator.simulateWeightReading(1, 500)

// Simulate pickup (reduces weight)
iotSimulator.simulateBookPickup(1, 350)

// Simulate return (increases weight)
iotSimulator.simulateBookReturn(1, 350)

// Test wrong shelf
iotSimulator.simulateWrongShelf(1, 2, 350)

// Test unknown object
iotSimulator.simulateUnknownObject(1)

// Reset shelf
iotSimulator.resetShelf(1)
`}
          </pre>
        </CardContent>
      </Card>
    </div>
  );
};

export default TestingPanel;
