/*
 * Smart Shelf - ESP8266 Door Control System
 * 
 * Hardware Setup:
 * - ESP8266 (NodeMCU or similar)
 * - Servo Motor (SG90 or similar)
 * - HX711 Weight Sensor (Load Cell Amplifier)
 * - Power supply (5V recommended for servo)
 * 
 * Connections:
 * - Servo Signal Pin -> D7 (GPIO13)
 * - Servo VCC -> 5V (or external 5V supply)
 * - Servo GND -> GND
 * 
 * - HX711 DT (Data) -> D6 (GPIO12)
 * - HX711 SCK (Clock) -> D5 (GPIO14)
 * - HX711 VCC -> 5V
 * - HX711 GND -> GND
 * 
 * Features:
 * - Connects to WiFi
 * - Opens HTTP server for unlock commands
 * - Controls servo motor to lock/unlock door
 * - Reads weight sensor to detect book pickup/return
 * - Auto-locks after 60 seconds
 * - LED indicator for status
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Servo.h>
#include <ArduinoJson.h>
#include <HX711.h>

// ===== CONFIGURATION - CHANGE THESE VALUES =====
const char* ssid = "MG";                  // Replace with your WiFi name
const char* password = "9041815554";           // Replace with your WiFi password

// Supabase Configuration
const char* SUPABASE_URL = "https://ekzxfrqtaietacxeasnd.supabase.co";  // Your Supabase URL
const char* SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVrenhmcnF0YWlldGFjeGVhc25kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE0ODgxNTcsImV4cCI6MjA3NzA2NDE1N30.0H5WlQfRm8AjgPGlDN7B-YopP9mOzn5bOfgEmf8FAw8";                // Your Supabase anon key
const char* SHELF_ID = "de6735db-f9b2-45db-81b7-275cbc211735";     

// ===============================================

// Servo configuration
Servo doorServo;
const int SERVO_PIN = D7;           // GPIO13 - Servo signal pin
const int LOCKED_POSITION = 90;     // Servo angle when locked (90 degrees)
const int UNLOCKED_POSITION = 0;    // Servo angle when unlocked (0 degrees)

// Weight sensor configuration (HX711)
HX711 scale;
const int LOADCELL_DOUT_PIN = D6;   // GPIO12 - HX711 Data pin
const int LOADCELL_SCK_PIN = D5;    // GPIO14 - HX711 Clock pin
float calibration_factor = -7050;   // Adjust this value after calibration
float weight_threshold = 50.0;      // Weight change threshold in grams to detect book pickup/return
float last_weight = 0.0;            // Store last weight reading
float empty_shelf_weight = 0.0;     // Weight of empty shelf (calibrated at startup)

// Door state
bool isDoorUnlocked = false;
unsigned long unlockTime = 0;
const unsigned long AUTO_LOCK_DELAY = 60000;  // 60 seconds
String currentUserId = "";                     // Store user who unlocked the door
String currentUnlockEventId = "";              // Store unlock event ID

// LED for status indication (built-in LED)
const int LED_PIN = LED_BUILTIN;  // D0 on most ESP8266 boards

// Web server
ESP8266WebServer server(80);

// HTTPS client for Supabase
WiFiClientSecure wifiClient;

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  delay(100);
  
  Serial.println("\n\n=================================");
  Serial.println("Smart Shelf System Starting...");
  Serial.println("=================================");
  
  // Initialize LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);  // LED off (inverted on ESP8266)
  
  // Initialize servo
  doorServo.attach(SERVO_PIN);
  doorServo.write(LOCKED_POSITION);  // Start in locked position
  Serial.println("✓ Servo initialized (LOCKED)");
  
  // Initialize weight sensor
  Serial.println("Initializing weight sensor...");
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  
  // Check if HX711 is connected
  Serial.println("Checking HX711 connection...");
  bool hx711_ready = false;
  for (int i = 0; i < 10; i++) {
    if (scale.is_ready()) {
      hx711_ready = true;
      break;
    }
    Serial.print(".");
    delay(100);
  }
  
  if (hx711_ready) {
    Serial.println("\n✓ HX711 detected!");
    scale.set_scale(calibration_factor);
    scale.tare();  // Reset scale to 0
    
    // Wait for stable reading
    delay(500);
    empty_shelf_weight = scale.get_units(5);  // Average of 5 readings
    last_weight = empty_shelf_weight;
    
    Serial.print("✓ Weight sensor initialized (Empty shelf: ");
    Serial.print(empty_shelf_weight);
    Serial.println(" g)");
  } else {
    Serial.println("\n⚠️  WARNING: HX711 not detected!");
    Serial.println("Check wiring:");
    Serial.println("  - HX711 DT  -> D6 (GPIO12)");
    Serial.println("  - HX711 SCK -> D5 (GPIO14)");
    Serial.println("  - HX711 VCC -> 5V");
    Serial.println("  - HX711 GND -> GND");
    Serial.println("System will continue without weight sensor...");
    empty_shelf_weight = 0;
    last_weight = 0;
  }
  
  // Connect to WiFi
  connectToWiFi();
  
  // Setup HTTPS client (disable certificate validation for simplicity)
  wifiClient.setInsecure();
  
  // Setup web server routes
  setupServerRoutes();
  
  // Start server
  server.begin();
  Serial.println("✓ HTTP server started");
  Serial.println("=================================");
  Serial.println("System Ready!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  Serial.println("=================================\n");
  
  // Blink LED 3 times to indicate ready
  blinkLED(3);
}

// ===== MAIN LOOP =====
void loop() {
  // Handle web server requests
  server.handleClient();
  
  // Read weight sensor periodically
  static unsigned long lastWeightCheck = 0;
  if (millis() - lastWeightCheck > 500) {  // Check every 500ms
    lastWeightCheck = millis();
    checkWeightChange();
  }
  
  // Auto-lock door after timeout
  if (isDoorUnlocked && (millis() - unlockTime > AUTO_LOCK_DELAY)) {
    lockDoor();
  }
  
  // Keep WiFi connected
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected! Reconnecting...");
    connectToWiFi();
  }
}

// ===== WiFi CONNECTION =====
void connectToWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));  // Blink while connecting
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    digitalWrite(LED_PIN, HIGH);  // LED off when connected
    Serial.println("\n✓ WiFi connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
    Serial.print("MAC Address: ");
    Serial.println(WiFi.macAddress());
  } else {
    Serial.println("\n✗ WiFi connection failed!");
    Serial.println("Please check your SSID and password");
    // Keep trying in background
    WiFi.reconnect();
  }
}

// ===== WEB SERVER ROUTES =====
void setupServerRoutes() {
  // Root endpoint - status check
  server.on("/", HTTP_GET, handleRoot);
  
  // Status endpoint
  server.on("/status", HTTP_GET, handleStatus);
  
  // Weight endpoint
  server.on("/weight", HTTP_GET, handleWeight);
  
  // Calibrate weight sensor endpoint
  server.on("/calibrate", HTTP_POST, handleCalibrate);
  
  // Unlock endpoint (POST)
  server.on("/unlock", HTTP_POST, handleUnlock);
  server.on("/unlock", HTTP_OPTIONS, handleUnlock);  // Handle OPTIONS for CORS
  
  // Lock endpoint (POST)
  server.on("/lock", HTTP_POST, handleLock);
  server.on("/lock", HTTP_OPTIONS, handleLock);  // Handle OPTIONS for CORS
  
  // Handle 404
  server.onNotFound(handleNotFound);
}

// ===== ROUTE HANDLERS =====

// Root endpoint
void handleRoot() {
  String html = "<html><head><title>Smart Shelf</title>";
  html += "<style>body{font-family:Arial;padding:20px;background:#f0f0f0;}";
  html += ".container{max-width:600px;margin:0 auto;background:white;padding:30px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.1);}";
  html += "h1{color:#333;}";
  html += ".status{padding:15px;margin:20px 0;border-radius:5px;font-weight:bold;}";
  html += ".locked{background:#ffebee;color:#c62828;}";
  html += ".unlocked{background:#e8f5e9;color:#2e7d32;}";
  html += "button{padding:12px 24px;font-size:16px;margin:5px;border:none;border-radius:5px;cursor:pointer;}";
  html += ".btn-unlock{background:#4caf50;color:white;}";
  html += ".btn-lock{background:#f44336;color:white;}";
  html += "</style></head><body>";
  html += "<div class='container'>";
  html += "<h1>🔐 Smart Shelf System</h1>";
  html += "<div class='status " + String(isDoorUnlocked ? "unlocked" : "locked") + "'>";
  html += "Status: " + String(isDoorUnlocked ? "🔓 UNLOCKED" : "🔒 LOCKED");
  html += "</div>";
  html += "<p><strong>IP Address:</strong> " + WiFi.localIP().toString() + "</p>";
  html += "<p><strong>WiFi:</strong> " + String(ssid) + "</p>";
  html += "<p><strong>Signal:</strong> " + String(WiFi.RSSI()) + " dBm</p>";
  html += "<hr>";
  html += "<h3>Manual Control (Testing Only):</h3>";
  html += "<button class='btn-unlock' onclick=\"fetch('/unlock',{method:'POST'}).then(()=>location.reload())\">Unlock Door</button>";
  html += "<button class='btn-lock' onclick=\"fetch('/lock',{method:'POST'}).then(()=>location.reload())\">Lock Door</button>";
  html += "</div></body></html>";
  
  server.send(200, "text/html", html);
}

// Status endpoint (JSON)
void handleStatus() {
  StaticJsonDocument<300> doc;
  doc["status"] = isDoorUnlocked ? "unlocked" : "locked";
  doc["ip"] = WiFi.localIP().toString();
  doc["wifi_ssid"] = ssid;
  doc["wifi_rssi"] = WiFi.RSSI();
  doc["uptime"] = millis() / 1000;
  doc["weight"] = scale.is_ready() ? scale.get_units(3) : 0;  // Quick reading (3 samples)
  doc["weight_stable"] = scale.is_ready() ? isWeightStable() : false;
  
  if (isDoorUnlocked) {
    doc["auto_lock_in"] = (AUTO_LOCK_DELAY - (millis() - unlockTime)) / 1000;
  }
  
  String response;
  serializeJson(doc, response);
  
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", response);
}

// Weight endpoint (JSON)
void handleWeight() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  StaticJsonDocument<200> doc;
  
  if (scale.is_ready()) {
    float current_weight = scale.get_units(10);  // Average of 10 readings for accuracy
    doc["weight"] = current_weight;
    doc["weight_change"] = current_weight - empty_shelf_weight;
    doc["empty_shelf_weight"] = empty_shelf_weight;
    doc["calibration_factor"] = calibration_factor;
    doc["stable"] = isWeightStable();
    doc["sensor_status"] = "connected";
  } else {
    doc["weight"] = 0;
    doc["weight_change"] = 0;
    doc["empty_shelf_weight"] = 0;
    doc["calibration_factor"] = calibration_factor;
    doc["stable"] = false;
    doc["sensor_status"] = "disconnected";
    doc["error"] = "HX711 not responding - check wiring";
  }
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Calibrate endpoint
void handleCalibrate() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  Serial.println("\n=== CALIBRATION REQUEST ===");
  
  // Parse JSON body
  if (server.hasArg("plain")) {
    String body = server.arg("plain");
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, body);
    
    if (!error && doc.containsKey("known_weight")) {
      float known_weight = doc["known_weight"];
      
      // Tare the scale
      scale.tare();
      delay(1000);
      
      // Read current value
      float reading = scale.get_units(10);
      
      // Calculate calibration factor
      calibration_factor = reading / known_weight;
      scale.set_scale(calibration_factor);
      
      Serial.print("New calibration factor: ");
      Serial.println(calibration_factor);
      
      // Reset empty shelf weight
      scale.tare();
      delay(500);
      empty_shelf_weight = scale.get_units(10);
      last_weight = empty_shelf_weight;
      
      StaticJsonDocument<200> responseDoc;
      responseDoc["success"] = true;
      responseDoc["calibration_factor"] = calibration_factor;
      responseDoc["message"] = "Calibration successful";
      
      String response;
      serializeJson(responseDoc, response);
      server.send(200, "application/json", response);
      
      Serial.println("Calibration complete!");
      return;
    }
  }
  
  // If no valid data
  StaticJsonDocument<100> errorDoc;
  errorDoc["success"] = false;
  errorDoc["message"] = "Please provide known_weight in grams";
  
  String response;
  serializeJson(errorDoc, response);
  server.send(400, "application/json", response);
}

// Unlock endpoint
void handleUnlock() {
  // Enable CORS for all requests
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  server.sendHeader("Access-Control-Max-Age", "86400");
  
  // Handle OPTIONS request (CORS preflight)
  if (server.method() == HTTP_OPTIONS) {
    server.send(200);  // Changed from 204 to 200
    return;
  }
  
  Serial.println("\n=== UNLOCK REQUEST RECEIVED ===");
  
  // Parse JSON body
  String userId = "";
  if (server.hasArg("plain")) {
    String body = server.arg("plain");
    Serial.println("Request body: " + body);
    
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, body);
    
    if (!error) {
      const char* qr_code = doc["qr_code"];
      const char* user_id = doc["user_id"];
      Serial.print("QR Code: ");
      Serial.println(qr_code);
      Serial.print("User ID: ");
      Serial.println(user_id);
      userId = String(user_id);
    }
  }
  
  // Record unlock event in Supabase
  String unlockEventId = recordDoorUnlock(userId);
  
  // Unlock the door
  unlockDoor();
  currentUserId = userId;
  currentUnlockEventId = unlockEventId;
  
  // Send success response
  StaticJsonDocument<100> responseDoc;
  responseDoc["success"] = true;
  responseDoc["message"] = "Door unlocked successfully";
  responseDoc["auto_lock_in_seconds"] = AUTO_LOCK_DELAY / 1000;
  
  String response;
  serializeJson(responseDoc, response);
  
  server.send(200, "application/json", response);
  Serial.println("Response sent: Door unlocked");
  Serial.println("===============================\n");
}

// Lock endpoint
void handleLock() {
  // Enable CORS
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  
  // Handle OPTIONS request (CORS preflight)
  if (server.method() == HTTP_OPTIONS) {
    server.send(200);
    return;
  }
  
  Serial.println("\n=== LOCK REQUEST RECEIVED ===");
  lockDoor();
  
  StaticJsonDocument<100> doc;
  doc["success"] = true;
  doc["message"] = "Door locked successfully";
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
  Serial.println("Response sent: Door locked");
  Serial.println("=============================\n");
}

// 404 handler
void handleNotFound() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  StaticJsonDocument<100> doc;
  doc["error"] = "Not Found";
  doc["message"] = "The requested endpoint does not exist";
  
  String response;
  serializeJson(doc, response);
  
  server.send(404, "application/json", response);
}

// ===== DOOR CONTROL FUNCTIONS =====

void unlockDoor() {
  if (!isDoorUnlocked) {
    Serial.println("🔓 UNLOCKING DOOR...");
    doorServo.write(UNLOCKED_POSITION);
    isDoorUnlocked = true;
    unlockTime = millis();
    
    // Blink LED to indicate unlock
    blinkLED(2);
    digitalWrite(LED_PIN, LOW);  // Keep LED on while unlocked
    
    Serial.println("✓ Door UNLOCKED");
    Serial.print("Auto-lock in ");
    Serial.print(AUTO_LOCK_DELAY / 1000);
    Serial.println(" seconds");
  } else {
    Serial.println("⚠ Door already unlocked");
  }
}

void lockDoor() {
  if (isDoorUnlocked) {
    Serial.println("🔒 LOCKING DOOR...");
    doorServo.write(LOCKED_POSITION);
    isDoorUnlocked = false;
    
    // Clear user info
    currentUserId = "";
    currentUnlockEventId = "";
    
    // Turn off LED
    digitalWrite(LED_PIN, HIGH);
    
    Serial.println("✓ Door LOCKED");
  } else {
    Serial.println("⚠ Door already locked");
  }
}

// ===== WEIGHT SENSOR FUNCTIONS =====

void checkWeightChange() {
  // Only check if door is unlocked (book pickup/return window)
  if (!isDoorUnlocked) {
    return;
  }
  
  // Check if HX711 is ready
  if (!scale.is_ready()) {
    return;
  }
  
  float current_weight = scale.get_units(5);  // Average of 5 readings
  float weight_change = abs(current_weight - last_weight);
  
  // Detect significant weight change
  if (weight_change > weight_threshold) {
    Serial.println("\n⚖️  WEIGHT CHANGE DETECTED!");
    Serial.print("Previous: ");
    Serial.print(last_weight);
    Serial.println(" g");
    Serial.print("Current: ");
    Serial.print(current_weight);
    Serial.println(" g");
    Serial.print("Change: ");
    Serial.print(current_weight - last_weight);
    Serial.println(" g");
    
    // Determine if book was added or removed
    if (current_weight < last_weight) {
      Serial.println("📤 BOOK REMOVED (Pickup detected)");
      // Send pickup event to Supabase
      sendWeightChangeToSupabase("pickup", current_weight, last_weight);
    } else {
      Serial.println("📥 BOOK ADDED (Return detected)");
      // Send return event to Supabase
      sendWeightChangeToSupabase("return", current_weight, last_weight);
    }
    
    last_weight = current_weight;
    
    // Blink LED to indicate detection
    blinkLED(3);
  }
}

bool isWeightStable() {
  float current = scale.get_units(3);
  float diff = abs(current - last_weight);
  return diff < (weight_threshold / 2);  // Stable if change is less than half threshold
}

// ===== SUPABASE INTEGRATION FUNCTIONS =====

String recordDoorUnlock(String userId) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("⚠️  WiFi not connected - cannot send to Supabase");
    return "";
  }
  
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/door_unlock_events";
  
  Serial.println("\n📤 Sending unlock event to Supabase...");
  http.begin(wifiClient, url);
  
  // Set headers
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  http.addHeader("Prefer", "return=representation");
  
  // Create JSON payload
  StaticJsonDocument<300> doc;
  doc["shelf_id"] = SHELF_ID;
  doc["user_id"] = userId;
  doc["unlocked_at"] = "now()";
  doc["book_issued"] = false;
  
  String payload;
  serializeJson(doc, payload);
  
  Serial.print("Request: ");
  Serial.println(payload);
  
  // Send POST request
  int httpCode = http.POST(payload);
  
  String eventId = "";
  if (httpCode > 0) {
    String response = http.getString();
    Serial.print("Response code: ");
    Serial.println(httpCode);
    Serial.print("Response: ");
    Serial.println(response);
    
    if (httpCode == 201) {
      // Parse response to get event ID
      StaticJsonDocument<500> responseDoc;
      DeserializationError error = deserializeJson(responseDoc, response);
      if (!error && responseDoc.is<JsonArray>() && responseDoc.size() > 0) {
        eventId = responseDoc[0]["id"].as<String>();
        Serial.print("✓ Unlock event recorded! ID: ");
        Serial.println(eventId);
      }
    }
  } else {
    Serial.print("✗ HTTP Error: ");
    Serial.println(http.errorToString(httpCode));
  }
  
  http.end();
  return eventId;
}

void sendWeightChangeToSupabase(String action, float currentWeight, float previousWeight) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("⚠️  WiFi not connected - cannot send to Supabase");
    return;
  }
  
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/shelf_weight_events";
  
  Serial.print("\n📤 Sending weight change (");
  Serial.print(action);
  Serial.println(") to Supabase...");
  
  http.begin(wifiClient, url);
  
  // Set headers
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  
  // Create JSON payload
  StaticJsonDocument<400> doc;
  doc["shelf_id"] = SHELF_ID;
  doc["action"] = action;
  doc["current_weight"] = currentWeight;
  doc["previous_weight"] = previousWeight;
  doc["weight_change"] = currentWeight - previousWeight;
  doc["user_id"] = currentUserId.length() > 0 ? currentUserId : JsonVariant();
  doc["unlock_event_id"] = currentUnlockEventId.length() > 0 ? currentUnlockEventId : JsonVariant();
  
  String payload;
  serializeJson(doc, payload);
  
  Serial.print("Request: ");
  Serial.println(payload);
  
  // Send POST request
  int httpCode = http.POST(payload);
  
  if (httpCode > 0) {
    String response = http.getString();
    Serial.print("Response code: ");
    Serial.println(httpCode);
    
    if (httpCode == 201) {
      Serial.println("✓ Weight change recorded in Supabase!");
    } else {
      Serial.print("Response: ");
      Serial.println(response);
    }
  } else {
    Serial.print("✗ HTTP Error: ");
    Serial.println(http.errorToString(httpCode));
  }
  
  http.end();
}

void sendShelfAlertToSupabase(String alertType, String message) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("⚠️  WiFi not connected - cannot send to Supabase");
    return;
  }
  
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/shelf_alerts";
  
  Serial.print("\n🚨 Sending alert (");
  Serial.print(alertType);
  Serial.println(") to Supabase...");
  
  http.begin(wifiClient, url);
  
  // Set headers
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  
  // Create JSON payload
  StaticJsonDocument<300> doc;
  doc["shelf_id"] = SHELF_ID;
  doc["alert_type"] = alertType;
  doc["message"] = message;
  
  String payload;
  serializeJson(doc, payload);
  
  // Send POST request
  int httpCode = http.POST(payload);
  
  if (httpCode > 0) {
    if (httpCode == 201) {
      Serial.println("✓ Alert sent to Supabase!");
    } else {
      Serial.print("Response code: ");
      Serial.println(httpCode);
    }
  } else {
    Serial.print("✗ HTTP Error: ");
    Serial.println(http.errorToString(httpCode));
  }
  
  http.end();
}

// ===== UTILITY FUNCTIONS =====

void blinkLED(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, LOW);   // On
    delay(100);
    digitalWrite(LED_PIN, HIGH);  // Off
    delay(100);
  }
}
