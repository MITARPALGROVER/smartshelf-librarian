/*
 * Smart Shelf - Weight Change Detection (Simplified)
 * 
 * Logic:
 * - No calibration needed - just detects weight CHANGES
 * - On unlock: Records baseline weight
 * - During 1-minute window: Monitors for significant weight change
 * - Weight DECREASE (>100g) = Book taken (Issue)
 * - Weight INCREASE (>100g) = Book returned (Return)
 * 
 * Wiring:
 * Servo SG90 -> D7 (GPIO13)
 * HX711 DT   -> D6 (GPIO12)
 * HX711 SCK  -> D5 (GPIO14)
 */

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <ESP8266WebServer.h>
#include <ArduinoJson.h>
#include <Servo.h>
#include <HX711.h>

// ============ Configuration ============
const char* ssid = "MG";
const char* password = "9041815554";
const char* supabase_url = "https://ekzxfrqtaietacxeasnd.supabase.co";
const char* supabase_anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVrenhmcnF0YWlldGFjeGVhc25kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mjk5MzkyNjcsImV4cCI6MjA0NTUxNTI2N30.5j1LlHxb1x0k8xtIC6KCE2kIF-ezW15NPcVxz2DW1cg";
const char* shelf_id = "de6735db-f9b2-45db-81b7-275cbc211735";

// Pin Configuration
const int SERVO_PIN = D7;
const int LOADCELL_DOUT_PIN = D6;
const int LOADCELL_SCK_PIN = D5;

// Servo Positions
const int LOCKED_POSITION = 90;
const int UNLOCKED_POSITION = 0;

// Weight Detection Settings
const float WEIGHT_CHANGE_THRESHOLD = 100.0;  // Minimum change in grams to detect book movement
const unsigned long UNLOCK_DURATION = 60000;  // 1 minute window

// Objects
Servo doorServo;
HX711 scale;
ESP8266WebServer server(80);

// State Variables
bool doorUnlocked = false;
unsigned long unlockStartTime = 0;
float baselineWeight = 0.0;
bool weightSensorAvailable = false;
String currentUnlockEventId = "";
String currentUserId = "";
bool isReturnMode = false;  // true = expecting return, false = expecting issue

// ============ Setup ============
void setup() {
  Serial.begin(115200);
  Serial.println("\n\n=== Smart Shelf - Weight Change Detection ===");
  
  // Initialize Servo
  doorServo.attach(SERVO_PIN);
  doorServo.write(LOCKED_POSITION);
  Serial.println("✓ Servo initialized (locked)");
  
  // Initialize Weight Sensor
  Serial.println("Initializing weight sensor...");
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  
  bool sensor_found = false;
  for (int i = 0; i < 10; i++) {
    if (scale.is_ready()) {
      sensor_found = true;
      break;
    }
    delay(100);
  }
  
  if (sensor_found) {
    scale.set_scale(-1850);  // Calibration factor for your specific sensor
    scale.tare();  // Zero the scale
    weightSensorAvailable = true;
    Serial.println("✓ Weight sensor ready (calibration factor: -1850)");
  } else {
    weightSensorAvailable = false;
    Serial.println("⚠ Weight sensor not found - running without weight detection");
  }
  
  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✓ WiFi connected");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n✗ WiFi connection failed");
  }
  
  // Setup HTTP Server
  setupServer();
  server.begin();
  Serial.println("✓ HTTP server started\n");
  Serial.println("=== System Ready ===\n");
}

// ============ Main Loop ============
void loop() {
  server.handleClient();
  
  // Check if door should auto-lock
  if (doorUnlocked && (millis() - unlockStartTime > UNLOCK_DURATION)) {
    Serial.println("\n⏱ 1-minute window expired - Auto-locking");
    lockDoor();
    
    // If no weight change detected, mark as expired
    if (!currentUnlockEventId.isEmpty()) {
      updateReservationStatus("expired");
    }
  }
  
  // Monitor weight changes during unlock window
  if (doorUnlocked && weightSensorAvailable) {
    checkWeightChange();
  }
  
  delay(100);
}

// ============ Server Routes ============
void setupServer() {
  // CORS Options Handler
  server.on("/unlock", HTTP_OPTIONS, handleCORS);
  server.on("/lock", HTTP_OPTIONS, handleCORS);
  server.on("/status", HTTP_OPTIONS, handleCORS);
  
  // Main Routes
  server.on("/", HTTP_GET, handleRoot);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/unlock", HTTP_POST, handleUnlock);
  server.on("/lock", HTTP_POST, handleLock);
  
  server.onNotFound(handleNotFound);
}

void handleCORS() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  server.send(200, "text/plain", "");
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head><title>Smart Shelf</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;max-width:600px;margin:50px auto;padding:20px;}";
  html += "h1{color:#333;}.status{padding:15px;margin:10px 0;border-radius:8px;}";
  html += ".locked{background:#ffebee;color:#c62828;}.unlocked{background:#e8f5e9;color:#2e7d32;}";
  html += ".info{background:#e3f2fd;padding:10px;border-radius:5px;margin:10px 0;}";
  html += "button{padding:12px 24px;margin:5px;border:none;border-radius:5px;cursor:pointer;font-size:16px;}";
  html += ".btn-success{background:#4CAF50;color:white;}.btn-danger{background:#f44336;color:white;}</style></head><body>";
  html += "<h1>🔒 Smart Shelf Control</h1>";
  
  html += "<div class='status " + String(doorUnlocked ? "unlocked" : "locked") + "'>";
  html += "<strong>Door Status:</strong> " + String(doorUnlocked ? "UNLOCKED 🔓" : "LOCKED 🔒") + "<br>";
  if (doorUnlocked) {
    unsigned long remaining = (UNLOCK_DURATION - (millis() - unlockStartTime)) / 1000;
    html += "<strong>Time Remaining:</strong> " + String(remaining) + "s<br>";
    html += "<strong>Mode:</strong> " + String(isReturnMode ? "RETURN" : "ISSUE") + "<br>";
    html += "<strong>Baseline Weight:</strong> " + String(baselineWeight, 1) + " units";
  }
  html += "</div>";
  
  if (weightSensorAvailable) {
    float currentWeight = scale.get_units(5);
    html += "<div class='info'>";
    html += "<strong>Current Weight:</strong> " + String(currentWeight, 1) + " units<br>";
    if (doorUnlocked) {
      float change = currentWeight - baselineWeight;
      html += "<strong>Weight Change:</strong> " + String(change, 1) + " units";
      if (abs(change) > WEIGHT_CHANGE_THRESHOLD) {
        html += " ⚠️ <strong>SIGNIFICANT CHANGE!</strong>";
      }
    }
    html += "</div>";
  }
  
  html += "<div><button class='btn-success' onclick='testUnlock()'>Test Unlock</button>";
  html += "<button class='btn-danger' onclick='testLock()'>Test Lock</button></div>";
  
  html += "<script>function testUnlock(){fetch('/unlock',{method:'POST',headers:{'Content-Type':'application/json'},";
  html += "body:JSON.stringify({user_id:'test-user',is_return:false})}).then(()=>location.reload());}";
  html += "function testLock(){fetch('/lock',{method:'POST'}).then(()=>location.reload());}</script>";
  html += "</body></html>";
  
  server.send(200, "text/html", html);
}

void handleStatus() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  StaticJsonDocument<512> doc;
  doc["door_status"] = doorUnlocked ? "unlocked" : "locked";
  doc["weight_sensor"] = weightSensorAvailable;
  
  if (weightSensorAvailable) {
    float currentWeight = scale.get_units(5);
    doc["current_weight"] = currentWeight;
    
    if (doorUnlocked) {
      doc["baseline_weight"] = baselineWeight;
      doc["weight_change"] = currentWeight - baselineWeight;
      doc["time_remaining"] = (UNLOCK_DURATION - (millis() - unlockStartTime)) / 1000;
      doc["mode"] = isReturnMode ? "return" : "issue";
    }
  }
  
  doc["unlock_event_id"] = currentUnlockEventId;
  doc["shelf_id"] = shelf_id;
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleUnlock() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"error\":\"No body\"}");
    return;
  }
  
  StaticJsonDocument<512> doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }
  
  // Extract parameters
  String userId = doc["user_id"] | "";
  String unlockEventId = doc["unlock_event_id"] | "";
  bool returnMode = doc["is_return"] | false;
  
  if (userId.isEmpty()) {
    server.send(400, "application/json", "{\"error\":\"user_id required\"}");
    return;
  }
  
  // Unlock the door
  currentUserId = userId;
  currentUnlockEventId = unlockEventId;
  isReturnMode = returnMode;
  
  unlockDoor();
  
  // Create reservation if unlock_event_id provided
  if (!unlockEventId.isEmpty()) {
    createReservation(unlockEventId, userId);
  }
  
  server.send(200, "application/json", "{\"success\":true,\"message\":\"Door unlocked\",\"mode\":\"" + String(returnMode ? "return" : "issue") + "\"}");
}

void handleLock() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  lockDoor();
  server.send(200, "application/json", "{\"success\":true,\"message\":\"Door locked\"}");
}

void handleNotFound() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(404, "application/json", "{\"error\":\"Not found\"}");
}

// ============ Door Control ============
void unlockDoor() {
  Serial.println("\n🔓 UNLOCKING DOOR");
  doorServo.write(UNLOCKED_POSITION);
  doorUnlocked = true;
  unlockStartTime = millis();
  
  // Record baseline weight
  if (weightSensorAvailable && scale.is_ready()) {
    baselineWeight = scale.get_units(10);
    Serial.print("📊 Baseline weight: ");
    Serial.print(baselineWeight, 1);
    Serial.println(" units");
  }
  
  Serial.println("⏱ 1-minute reservation window started");
  Serial.println("Mode: " + String(isReturnMode ? "RETURN" : "ISSUE"));
}

void lockDoor() {
  Serial.println("\n🔒 LOCKING DOOR");
  doorServo.write(LOCKED_POSITION);
  doorUnlocked = false;
  
  // Clear state
  currentUnlockEventId = "";
  currentUserId = "";
  isReturnMode = false;
  baselineWeight = 0;
}

// ============ Weight Detection ============
void checkWeightChange() {
  static unsigned long lastCheck = 0;
  
  // Check every 2 seconds
  if (millis() - lastCheck < 2000) return;
  lastCheck = millis();
  
  if (!scale.is_ready()) return;
  
  float currentWeight = scale.get_units(10);
  float weightChange = currentWeight - baselineWeight;
  
  Serial.print("Weight: ");
  Serial.print(currentWeight, 1);
  Serial.print(" | Change: ");
  Serial.print(weightChange, 1);
  Serial.println(" units");
  
  // Detect significant weight DECREASE (book taken)
  if (!isReturnMode && weightChange < -WEIGHT_CHANGE_THRESHOLD) {
    Serial.println("\n📤 BOOK TAKEN DETECTED!");
    Serial.print("Weight decreased by ");
    Serial.print(abs(weightChange), 1);
    Serial.println(" units");
    
    // Process book issue
    processBookIssue();
    lockDoor();
  }
  
  // Detect significant weight INCREASE (book returned)
  else if (isReturnMode && weightChange > WEIGHT_CHANGE_THRESHOLD) {
    Serial.println("\n📥 BOOK RETURNED DETECTED!");
    Serial.print("Weight increased by ");
    Serial.print(weightChange, 1);
    Serial.println(" units");
    
    // Process book return
    processBookReturn();
    lockDoor();
  }
}

// ============ Book Processing ============
void processBookIssue() {
  if (currentUnlockEventId.isEmpty() || currentUserId.isEmpty()) {
    Serial.println("⚠ No unlock event - skipping issue");
    return;
  }
  
  Serial.println("📝 Creating book issue transaction...");
  
  // Call Supabase function to process issue
  callSupabaseFunction("process_book_issue", currentUnlockEventId, currentUserId, "pickup");
  
  // Update reservation
  updateReservationStatus("completed");
}

void processBookReturn() {
  if (currentUnlockEventId.isEmpty() || currentUserId.isEmpty()) {
    Serial.println("⚠ No unlock event - skipping return");
    return;
  }
  
  Serial.println("📝 Processing book return...");
  
  // Call Supabase function to process return
  callSupabaseFunction("process_book_return", currentUnlockEventId, currentUserId, "return");
  
  // Update reservation
  updateReservationStatus("completed");
}

// ============ Supabase Integration ============
void createReservation(String unlockEventId, String userId) {
  if (WiFi.status() != WL_CONNECTED) return;
  
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabase_url) + "/rest/v1/shelf_reservations";
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabase_anon_key);
  http.addHeader("Authorization", "Bearer " + String(supabase_anon_key));
  http.addHeader("Prefer", "return=minimal");
  
  StaticJsonDocument<256> doc;
  doc["unlock_event_id"] = unlockEventId;
  doc["user_id"] = userId;
  doc["status"] = "active";
  doc["expires_at"] = "now() + interval '1 minute'";
  
  String payload;
  serializeJson(doc, payload);
  
  int httpCode = http.POST(payload);
  Serial.print("Create reservation: ");
  Serial.println(httpCode);
  
  http.end();
}

void updateReservationStatus(String status) {
  if (WiFi.status() != WL_CONNECTED || currentUnlockEventId.isEmpty()) return;
  
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabase_url) + "/rest/v1/shelf_reservations?unlock_event_id=eq." + currentUnlockEventId;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabase_anon_key);
  http.addHeader("Authorization", "Bearer " + String(supabase_anon_key));
  http.addHeader("Prefer", "return=minimal");
  
  String payload = "{\"status\":\"" + status + "\"}";
  
  int httpCode = http.PATCH(payload);
  Serial.print("Update reservation (" + status + "): ");
  Serial.println(httpCode);
  
  http.end();
}

void callSupabaseFunction(String functionName, String unlockEventId, String userId, String action) {
  if (WiFi.status() != WL_CONNECTED) return;
  
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabase_url) + "/rest/v1/rpc/" + functionName;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabase_anon_key);
  http.addHeader("Authorization", "Bearer " + String(supabase_anon_key));
  
  StaticJsonDocument<256> doc;
  doc["p_unlock_event_id"] = unlockEventId;
  doc["p_user_id"] = userId;
  doc["p_action"] = action;
  
  String payload;
  serializeJson(doc, payload);
  
  int httpCode = http.POST(payload);
  Serial.print("Call " + functionName + ": ");
  Serial.println(httpCode);
  
  if (httpCode > 0) {
    String response = http.getString();
    Serial.println("Response: " + response);
  }
  
  http.end();
}
