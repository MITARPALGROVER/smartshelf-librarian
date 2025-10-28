import { supabase } from "@/integrations/supabase/client";

/**
 * 🧪 DUMMY IOT SIMULATOR
 * Simulates ESP8266 weight sensor behavior for testing
 * Only for testing - remove before production!
 */

interface ShelfData {
  shelf_id: string;
  shelf_number: number;
  current_weight: number;
}

/**
 * Simulate weight sensor reading for a shelf
 * Mimics what ESP8266 would send
 */
export const simulateWeightReading = async (
  shelfNumber: number,
  weight: number
) => {
  try {
    // Get shelf ID
    const { data: shelf } = await supabase
      .from('shelves')
      .select('id')
      .eq('shelf_number', shelfNumber)
      .single();

    if (!shelf) {
      console.error(`Shelf ${shelfNumber} not found`);
      return { success: false, error: 'Shelf not found' };
    }

    // Update shelf weight (like ESP8266 would do)
    const { error } = await supabase
      .from('shelves')
      .update({
        current_weight: weight,
        last_sensor_update: new Date().toISOString()
      })
      .eq('id', shelf.id);

    if (error) {
      console.error('Error updating weight:', error);
      return { success: false, error: error.message };
    }

    console.log(`✅ Shelf ${shelfNumber} weight updated to ${weight}g`);
    return { success: true, weight, shelfNumber };
  } catch (error: any) {
    console.error('Simulation error:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Simulate book pickup (weight decrease)
 * Call this when you want to test automatic book issuance
 */
export const simulateBookPickup = async (
  shelfNumber: number,
  bookWeight: number
) => {
  try {
    // Get current shelf weight
    const { data: shelf } = await supabase
      .from('shelves')
      .select('id, current_weight')
      .eq('shelf_number', shelfNumber)
      .single();

    if (!shelf) {
      return { success: false, error: 'Shelf not found' };
    }

    // Decrease weight (book removed)
    const newWeight = Math.max(0, shelf.current_weight - bookWeight);
    
    const result = await simulateWeightReading(shelfNumber, newWeight);
    
    console.log(`📖 Simulated book pickup: ${bookWeight}g removed from Shelf ${shelfNumber}`);
    return result;
  } catch (error: any) {
    return { success: false, error: error.message };
  }
};

/**
 * Simulate book return (weight increase)
 * Call this when you want to test book return detection
 */
export const simulateBookReturn = async (
  shelfNumber: number,
  bookWeight: number
) => {
  try {
    // Get current shelf weight
    const { data: shelf } = await supabase
      .from('shelves')
      .select('id, current_weight')
      .eq('shelf_number', shelfNumber)
      .single();

    if (!shelf) {
      return { success: false, error: 'Shelf not found' };
    }

    // Increase weight (book added)
    const newWeight = shelf.current_weight + bookWeight;
    
    const result = await simulateWeightReading(shelfNumber, newWeight);
    
    console.log(`📚 Simulated book return: ${bookWeight}g added to Shelf ${shelfNumber}`);
    return result;
  } catch (error: any) {
    return { success: false, error: error.message };
  }
};

/**
 * Simulate wrong shelf placement
 * Places a book on the wrong shelf to test alert system
 */
export const simulateWrongShelf = async (
  correctShelfNumber: number,
  wrongShelfNumber: number,
  bookWeight: number
) => {
  console.log(`⚠️ Simulating wrong shelf: Book from Shelf ${correctShelfNumber} placed on Shelf ${wrongShelfNumber}`);
  return await simulateBookReturn(wrongShelfNumber, bookWeight);
};

/**
 * Simulate unknown object on shelf
 * Adds random weight that doesn't match any book
 */
export const simulateUnknownObject = async (
  shelfNumber: number,
  randomWeight: number = 123 // Random weight that won't match books
) => {
  console.log(`❓ Simulating unknown object: ${randomWeight}g on Shelf ${shelfNumber}`);
  return await simulateBookReturn(shelfNumber, randomWeight);
};

/**
 * Reset shelf to empty state
 */
export const resetShelf = async (shelfNumber: number) => {
  console.log(`🔄 Resetting Shelf ${shelfNumber} to 0g`);
  return await simulateWeightReading(shelfNumber, 0);
};

/**
 * Auto-simulation: Continuously update weight with random fluctuations
 * Simulates real sensor noise
 */
export const startAutoSimulation = (
  shelfNumber: number,
  baseWeight: number,
  interval: number = 5000 // Update every 5 seconds
) => {
  console.log(`🤖 Starting auto-simulation for Shelf ${shelfNumber}`);
  
  const intervalId = setInterval(() => {
    // Add small random fluctuation (-2g to +2g)
    const fluctuation = (Math.random() - 0.5) * 4;
    const weight = Math.max(0, baseWeight + fluctuation);
    
    simulateWeightReading(shelfNumber, weight);
  }, interval);

  // Return stop function
  return () => {
    clearInterval(intervalId);
    console.log(`⏹️ Stopped auto-simulation for Shelf ${shelfNumber}`);
  };
};

/**
 * Get simulation recommendations based on active reservations
 */
export const getSimulationSuggestions = async () => {
  // Get active reservations
  const { data: reservations } = await supabase
    .from('reservations')
    .select(`
      id,
      books (
        title,
        weight,
        shelf_id,
        shelves (
          shelf_number
        )
      )
    `)
    .eq('status', 'active');

  if (!reservations || reservations.length === 0) {
    console.log('ℹ️ No active reservations. Reserve a book first to test!');
    return [];
  }

  const suggestions = reservations.map((res: any) => ({
    action: 'pickup',
    bookTitle: res.books.title,
    shelfNumber: res.books.shelves.shelf_number,
    weight: res.books.weight || 350,
    command: `simulateBookPickup(${res.books.shelves.shelf_number}, ${res.books.weight || 350})`
  }));

  console.log('💡 Simulation Suggestions:', suggestions);
  return suggestions;
};

// Make functions available globally in browser console for easy testing
if (typeof window !== 'undefined') {
  (window as any).iotSimulator = {
    simulateWeightReading,
    simulateBookPickup,
    simulateBookReturn,
    simulateWrongShelf,
    simulateUnknownObject,
    resetShelf,
    startAutoSimulation,
    getSimulationSuggestions
  };
  
  console.log(`
🧪 IoT Simulator loaded! Use these commands in browser console:

// Basic weight update
iotSimulator.simulateWeightReading(1, 500)

// Simulate book pickup (for testing auto-issuance)
iotSimulator.simulateBookPickup(1, 350)

// Simulate book return
iotSimulator.simulateBookReturn(1, 350)

// Test wrong shelf alert
iotSimulator.simulateWrongShelf(1, 2, 350)

// Test unknown object alert
iotSimulator.simulateUnknownObject(1, 123)

// Reset shelf to empty
iotSimulator.resetShelf(1)

// Get suggestions based on active reservations
iotSimulator.getSimulationSuggestions()

// Auto-simulation with sensor noise
const stopAuto = iotSimulator.startAutoSimulation(1, 500)
// To stop: stopAuto()
  `);
}
