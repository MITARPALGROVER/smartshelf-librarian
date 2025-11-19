/*
 * Simple HX711 Weight Sensor Testing & Calibration
 * 
 * Wiring:
 * HX711 DT  -> D6 (GPIO12)
 * HX711 SCK -> D5 (GPIO14)
 * HX711 VCC -> 5V
 * HX711 GND -> GND
 * 
 * Instructions:
 * 1. Upload this code
 * 2. Open Serial Monitor (115200 baud)
 * 3. Follow the on-screen instructions
 */

#include <HX711.h>

// Pin Configuration
const int LOADCELL_DOUT_PIN = D6;  // GPIO12
const int LOADCELL_SCK_PIN = D5;   // GPIO14

HX711 scale;

// Calibration factor - adjust this value
float calibration_factor = -7050;  // Start with this, will be auto-calculated

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n========================================");
  Serial.println("  HX711 Weight Sensor Tester");
  Serial.println("========================================\n");
  
  // Initialize HX711
  Serial.println("Initializing HX711...");
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  
  // Check if HX711 is ready
  Serial.print("Checking sensor connection");
  bool sensor_found = false;
  for (int i = 0; i < 10; i++) {
    if (scale.is_ready()) {
      sensor_found = true;
      break;
    }
    Serial.print(".");
    delay(100);
  }
  Serial.println();
  
  if (sensor_found) {
    Serial.println("✓ HX711 sensor detected!");
  } else {
    Serial.println("✗ HX711 sensor NOT found!");
    Serial.println("\nCheck wiring:");
    Serial.println("  HX711 DT  -> D6 (GPIO12)");
    Serial.println("  HX711 SCK -> D5 (GPIO14)");
    Serial.println("  HX711 VCC -> 5V");
    Serial.println("  HX711 GND -> GND");
    Serial.println("\nPress RESET button to try again.");
    while(1) { delay(100); }
  }
  
  // Set initial calibration factor
  scale.set_scale(calibration_factor);
  
  // Tare (zero the scale)
  Serial.println("\nPlease remove all items from the scale...");
  Serial.println("Taring in 3 seconds...");
  delay(3000);
  
  Serial.print("Taring");
  scale.tare();
  for (int i = 0; i < 5; i++) {
    Serial.print(".");
    delay(200);
  }
  Serial.println();
  Serial.println("✓ Scale zeroed!\n");
  
  // Show menu
  showMenu();
}

void loop() {
  // Check if data is available from Serial
  if (Serial.available() > 0) {
    char command = Serial.read();
    
    switch(command) {
      case '1':
        readWeight();
        break;
      case '2':
        continuousReading();
        break;
      case '3':
        calibrateScale();
        break;
      case '4':
        tareScale();
        break;
      case '5':
        readRawValue();
        break;
      case '6':
        changeCalibrationFactor();
        break;
      case 'm':
      case 'M':
        showMenu();
        break;
      default:
        // Ignore other characters
        break;
    }
  }
  
  delay(10);
}

void showMenu() {
  Serial.println("\n========================================");
  Serial.println("           MAIN MENU");
  Serial.println("========================================");
  Serial.println("1 - Read Weight Once");
  Serial.println("2 - Continuous Reading (press any key to stop)");
  Serial.println("3 - Calibrate with Known Weight");
  Serial.println("4 - Tare (Zero) the Scale");
  Serial.println("5 - Read Raw Value");
  Serial.println("6 - Change Calibration Factor");
  Serial.println("M - Show this Menu");
  Serial.println("========================================");
  Serial.print("\nCurrent calibration factor: ");
  Serial.println(calibration_factor);
  Serial.println("\nEnter command (1-6 or M): ");
}

void readWeight() {
  Serial.println("\n--- Single Weight Reading ---");
  
  if (!scale.is_ready()) {
    Serial.println("✗ Sensor not ready!");
    return;
  }
  
  Serial.print("Reading");
  for (int i = 0; i < 3; i++) {
    Serial.print(".");
    delay(100);
  }
  Serial.println();
  
  float weight = scale.get_units(10);  // Average of 10 readings
  
  Serial.print("Weight: ");
  Serial.print(weight, 1);
  Serial.println(" g");
  Serial.println();
}

void continuousReading() {
  Serial.println("\n--- Continuous Reading Mode ---");
  Serial.println("Press any key to stop...\n");
  
  unsigned long lastPrint = 0;
  
  while (!Serial.available()) {
    if (millis() - lastPrint > 500) {  // Update every 500ms
      if (scale.is_ready()) {
        float weight = scale.get_units(5);  // Average of 5 readings
        
        Serial.print("Weight: ");
        Serial.print(weight, 1);
        Serial.print(" g");
        
        // Show visual bar
        int bars = abs(weight) / 50;
        if (bars > 0) {
          Serial.print("  [");
          for (int i = 0; i < bars && i < 20; i++) {
            Serial.print("=");
          }
          Serial.print("]");
        }
        
        Serial.println();
      } else {
        Serial.println("Sensor not ready...");
      }
      
      lastPrint = millis();
    }
  }
  
  // Clear serial buffer
  while (Serial.available()) Serial.read();
  
  Serial.println("\nContinuous reading stopped.\n");
}

void calibrateScale() {
  Serial.println("\n========================================");
  Serial.println("         CALIBRATION WIZARD");
  Serial.println("========================================\n");
  
  // Step 1: Tare
  Serial.println("STEP 1: Remove all weight from scale");
  Serial.println("Press 'Y' when ready to tare...");
  waitForKey('Y');
  
  Serial.print("Taring");
  scale.tare();
  for (int i = 0; i < 5; i++) {
    Serial.print(".");
    delay(200);
  }
  Serial.println("\n✓ Scale zeroed!");
  
  // Step 2: Place known weight
  Serial.println("\nSTEP 2: Place a known weight on the scale");
  Serial.println("Enter the weight in GRAMS (e.g., 225): ");
  
  float known_weight = readNumber();
  
  if (known_weight <= 0) {
    Serial.println("✗ Invalid weight! Calibration cancelled.");
    return;
  }
  
  Serial.print("\nYou entered: ");
  Serial.print(known_weight, 1);
  Serial.println(" g");
  Serial.println("\nPlace the weight on scale now...");
  Serial.println("Press 'Y' when ready to calibrate...");
  waitForKey('Y');
  
  // Read raw value
  Serial.print("Reading");
  for (int i = 0; i < 5; i++) {
    Serial.print(".");
    delay(200);
  }
  Serial.println();
  
  float reading = scale.get_units(10);  // Average of 10 readings
  
  // Calculate new calibration factor
  // reading = raw_value / old_factor
  // new_factor = raw_value / known_weight
  float raw_value = reading * calibration_factor;
  calibration_factor = raw_value / known_weight;
  
  scale.set_scale(calibration_factor);
  
  Serial.println("\n========================================");
  Serial.println("✓ CALIBRATION COMPLETE!");
  Serial.println("========================================");
  Serial.print("New calibration factor: ");
  Serial.println(calibration_factor, 2);
  
  // Verify
  Serial.println("\nVerifying...");
  delay(500);
  float verify_weight = scale.get_units(10);
  Serial.print("Scale now reads: ");
  Serial.print(verify_weight, 1);
  Serial.println(" g");
  
  float error = abs(verify_weight - known_weight);
  float error_percent = (error / known_weight) * 100;
  
  Serial.print("Error: ");
  Serial.print(error, 1);
  Serial.print(" g (");
  Serial.print(error_percent, 1);
  Serial.println("%)");
  
  if (error_percent < 5) {
    Serial.println("✓ Excellent calibration!");
  } else if (error_percent < 10) {
    Serial.println("✓ Good calibration");
  } else {
    Serial.println("⚠ Try calibrating again for better accuracy");
  }
  
  Serial.println("\n*** IMPORTANT ***");
  Serial.println("To save this calibration permanently:");
  Serial.print("Update line 21 in code to: calibration_factor = ");
  Serial.print(calibration_factor, 2);
  Serial.println(";");
  Serial.println("Then re-upload to ESP8266");
  Serial.println("========================================\n");
}

void tareScale() {
  Serial.println("\n--- Tare (Zero) Scale ---");
  Serial.println("Remove all weight from scale...");
  Serial.println("Press 'Y' when ready...");
  waitForKey('Y');
  
  Serial.print("Taring");
  scale.tare();
  for (int i = 0; i < 5; i++) {
    Serial.print(".");
    delay(200);
  }
  Serial.println("\n✓ Scale zeroed!\n");
}

void readRawValue() {
  Serial.println("\n--- Raw Value Reading ---");
  
  if (!scale.is_ready()) {
    Serial.println("✗ Sensor not ready!");
    return;
  }
  
  Serial.print("Reading raw value");
  for (int i = 0; i < 3; i++) {
    Serial.print(".");
    delay(100);
  }
  Serial.println();
  
  long raw = scale.read_average(10);
  
  Serial.print("Raw value: ");
  Serial.println(raw);
  Serial.print("With current calibration (");
  Serial.print(calibration_factor, 2);
  Serial.print("): ");
  Serial.print(raw / calibration_factor, 1);
  Serial.println(" g\n");
}

void changeCalibrationFactor() {
  Serial.println("\n--- Change Calibration Factor ---");
  Serial.print("Current factor: ");
  Serial.println(calibration_factor, 2);
  Serial.println("\nEnter new calibration factor: ");
  
  float new_factor = readNumber();
  
  if (new_factor == 0) {
    Serial.println("✗ Invalid factor! No changes made.");
    return;
  }
  
  calibration_factor = new_factor;
  scale.set_scale(calibration_factor);
  
  Serial.print("\n✓ Calibration factor updated to: ");
  Serial.println(calibration_factor, 2);
  Serial.println();
}

// Helper function: Wait for specific key
void waitForKey(char key) {
  while (true) {
    if (Serial.available() > 0) {
      char c = Serial.read();
      if (c == key || c == tolower(key)) {
        // Clear remaining characters
        while (Serial.available()) Serial.read();
        return;
      }
    }
    delay(10);
  }
}

// Helper function: Read a number from serial
float readNumber() {
  String input = "";
  
  while (true) {
    if (Serial.available() > 0) {
      char c = Serial.read();
      
      if (c == '\n' || c == '\r') {
        if (input.length() > 0) {
          return input.toFloat();
        }
      } else if (isDigit(c) || c == '.' || c == '-') {
        input += c;
        Serial.print(c);  // Echo character
      }
    }
    delay(10);
  }
}
