/*
 * Smart Shelf - Advanced QR Door System with HTTP Server
 * ESP8266 + HX711 + Servo + Web Server
 * 
 * API Endpoints:
 * GET  /status        - Get shelf status (weight, door state)
 * POST /unlock        - Unlock door (QR code authentication)
 * POST /lock          - Lock door manually
 * GET  /calibrate     - Start load cell calibration
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPClient.h>
#include <HX711.h>
#include <Servo.h>
#include <ArduinoJson.h>

// ===== PIN DEFINITIONS =====
#define HX711_DT_PIN    D5
#define HX711_SCK_PIN   D6
#define SERVO_PIN       D7

// ===== CONFIGURATION =====
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* supabaseUrl = "YOUR_SUPABASE_URL";
const char* supabaseKey = "YOUR_SUPABASE_ANON_KEY";
const char* shelfId = "YOUR_SHELF_ID";
const int shelfNumber = 1;  // Shelf number (1, 2, 3, etc.)

// ===== HARDWARE =====
HX711 scale;
Servo doorServo;
ESP8266WebServer server(80);

// ===== CONSTANTS =====
const int DOOR_LOCKED = 0;
const int DOOR_UNLOCKED = 90;
const float WEIGHT_THRESHOLD = 10.0;
const unsigned long DOOR_TIMEOUT = 30000;
const unsigned long WEIGHT_CHECK_INTERVAL = 500;
const float CALIBRATION_FACTOR = -7050;
const long ZERO_FACTOR = 50682624;

// ===== STATE VARIABLES =====
float currentWeight = 0;
float previousWeight = 0;
bool doorLocked = true;
unsigned long doorUnlockTime = 0;
unsigned long lastWeightCheck = 0;
String lastQRCode = "";

void setup() {
  Serial.begin(115200);
  Serial.println("\n\n╔═══════════════════════════════════════╗");
  Serial.println("║  Smart Shelf QR Door System v2.0     ║");
  Serial.println("╚═══════════════════════════════════════╝\n");
  
  // Initialize hardware
  initLoadCell();
  initServo();
  connectWiFi();
  setupWebServer();
  
  Serial.println("\n✅ System Ready!");
  Serial.print("📡 HTTP Server: http://");
  Serial.println(WiFi.localIP());
  Serial.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
}

void loop() {
  server.handleClient();  // Handle HTTP requests
  
  if (millis() - lastWeightCheck >= WEIGHT_CHECK_INTERVAL) {
    lastWeightCheck = millis();
    checkWeightChange();
  }
  
  if (!doorLocked && (millis() - doorUnlockTime >= DOOR_TIMEOUT)) {
    lockDoor();
    notifyDoorStatus("auto_locked");
  }
  
  delay(10);
}

// ===== INITIALIZATION =====
void initLoadCell() {
  Serial.print("🔧 Initializing HX711... ");
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  scale.set_scale(CALIBRATION_FACTOR);
  scale.set_offset(ZERO_FACTOR);
  currentWeight = scale.get_units(5);
  previousWeight = currentWeight;
  Serial.println("✅ Done");
  Serial.print("   Initial weight: ");
  Serial.print(currentWeight);
  Serial.println("g");
}

void initServo() {
  Serial.print("🔧 Initializing Servo... ");
  doorServo.attach(SERVO_PIN);
  lockDoor();
  Serial.println("✅ Done (LOCKED)");
}

void connectWiFi() {
  Serial.print("📡 Connecting to WiFi: ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected!");
    Serial.print("   IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n❌ WiFi Failed!");
  }
}

void setupWebServer() {
  // API Endpoints
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/unlock", HTTP_POST, handleUnlock);
  server.on("/lock", HTTP_POST, handleLock);
  server.on("/", HTTP_GET, handleRoot);
  server.onNotFound(handleNotFound);
  
  server.begin();
  Serial.println("🌐 Web server started");
}

// ===== WEB SERVER HANDLERS =====
void handleRoot() {
  String html = "<!DOCTYPE html><html><head>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;margin:20px;background:#f0f0f0;}";
  html += ".card{background:white;padding:20px;border-radius:10px;margin:10px 0;box-shadow:0 2px 5px rgba(0,0,0,0.1);}";
  html += "h1{color:#333;}button{padding:15px 30px;font-size:16px;margin:10px;cursor:pointer;border:none;border-radius:5px;}";
  html += ".unlock{background:#4CAF50;color:white;}.lock{background:#f44336;color:white;}</style></head><body>";
  html += "<h1>🚪 Smart Shelf Door Control</h1>";
  html += "<div class='card'><h2>Shelf #" + String(shelfNumber) + "</h2>";
      <p><strong>Door Status:</strong> " + String(doorLocked ? "🔒 LOCKED" : "🔓 UNLOCKED") + "</p>";
  html += "<p><strong>Weight:</strong> " + String(currentWeight, 1) + "g</p>";
  html += "<p><strong>IP:</strong> " + WiFi.localIP().toString() + "</p>";
  html += "<p><strong>Auto-lock:</strong> 60 seconds (1 minute)</p></div>";
  html += "<div class='card'>";
  html += "<button class='unlock' onclick=\"fetch('/unlock',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({qr_code:'" + shelfId + "'})}).then(()=>location.reload())\">🔓 UNLOCK</button>";
  html += "<button class='lock' onclick=\"fetch('/lock',{method:'POST'}).then(()=>location.reload())\">🔒 LOCK</button>";
  html += "</div></body></html>";
  
  server.send(200, "text/html", html);
}

void handleStatus() {
  StaticJsonDocument<300> doc;
  doc["shelf_id"] = shelfId;
  doc["shelf_number"] = shelfNumber;
  doc["door_locked"] = doorLocked;
  doc["current_weight"] = currentWeight;
  doc["timestamp"] = millis();
  doc["wifi_signal"] = WiFi.RSSI();
  
  String response;
  serializeJson(doc, response);
  
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", response);
  
  Serial.println("📊 Status requested");
}

void handleUnlock() {
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"error\":\"No body\"}");
    return;
  }
  
  String body = server.arg("plain");
  StaticJsonDocument<200> doc;
  deserializeJson(doc, body);
  
  String qrCode = doc["qr_code"] | "";
  String userId = doc["user_id"] | "";
  
  Serial.println("\n🔍 QR UNLOCK REQUEST");
  Serial.print("   QR Code: ");
  Serial.println(qrCode);
  Serial.print("   User ID: ");
  Serial.println(userId);
  
  // Verify QR code matches shelf
  if (qrCode == shelfId || qrCode == String(shelfNumber)) {
    unlockDoor();
    lastQRCode = qrCode;
    
    // Notify librarian via Supabase
    notifyLibrarian(userId, "door_unlocked");
    
    StaticJsonDocument<200> response;
    response["success"] = true;
    response["message"] = "Door unlocked";
    response["door_locked"] = doorLocked;
    
    String responseStr;
    serializeJson(response, responseStr);
    
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", responseStr);
    
    Serial.println("   ✅ Door unlocked via QR");
  } else {
    Serial.println("   ❌ Invalid QR code");
    server.send(403, "application/json", "{\"error\":\"Invalid QR code\"}");
  }
}

void handleLock() {
  lockDoor();
  notifyDoorStatus("manual_locked");
  
  StaticJsonDocument<200> response;
  response["success"] = true;
  response["message"] = "Door locked";
  response["door_locked"] = doorLocked;
  
  String responseStr;
  serializeJson(response, responseStr);
  
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", responseStr);
  
  Serial.println("🔒 Door locked via API");
}

void handleNotFound() {
  server.send(404, "text/plain", "Not Found");
}

// ===== DOOR CONTROL =====
void lockDoor() {
  doorServo.write(DOOR_LOCKED);
  doorLocked = true;
  delay(500);
  Serial.println("🔒 Door LOCKED");
}

void unlockDoor() {
  doorServo.write(DOOR_UNLOCKED);
  doorLocked = false;
  doorUnlockTime = millis();
  delay(500);
  Serial.println("🔓 Door UNLOCKED");
}

// ===== WEIGHT DETECTION =====
void checkWeightChange() {
  currentWeight = scale.get_units(3);
  float weightDiff = abs(currentWeight - previousWeight);
  
  if (weightDiff > WEIGHT_THRESHOLD) {
    Serial.println("\n⚖️  WEIGHT CHANGE DETECTED");
    Serial.printf("   %0.1fg → %0.1fg (Δ %0.1fg)\n", previousWeight, currentWeight, weightDiff);
    
    updateShelfWeight(currentWeight);
    
    // Book removed (weight decreased)
    if (currentWeight < previousWeight && !doorLocked) {
      float removedWeight = previousWeight - currentWeight;
      Serial.printf("📚 Book removed! Weight: %0.1fg\n", removedWeight);
      notifyBookPickup(removedWeight);
    }
    
    previousWeight = currentWeight;
  }
}

// ===== SUPABASE API =====
void updateShelfWeight(float weight) {
  if (WiFi.status() != WL_CONNECTED) return;
  
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabaseUrl) + "/rest/v1/shelves?id=eq." + shelfId;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", String("Bearer ") + supabaseKey);
  http.addHeader("Prefer", "return=minimal");
  
  StaticJsonDocument<200> doc;
  doc["current_weight"] = weight;
  String jsonBody;
  serializeJson(doc, jsonBody);
  
  int httpCode = http.PATCH(jsonBody);
  if (httpCode > 0) {
    Serial.printf("   ✅ Weight updated (HTTP %d)\n", httpCode);
  }
  http.end();
}

void notifyBookPickup(float bookWeight) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabaseUrl) + "/rest/v1/shelf_alerts";
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", String("Bearer ") + supabaseKey);
  
  StaticJsonDocument<300> doc;
  doc["shelf_id"] = shelfId;
  doc["alert_type"] = "book_removed";
  doc["message"] = "Book removed (" + String(bookWeight, 1) + "g) - Door was unlocked";
  
  String jsonBody;
  serializeJson(doc, jsonBody);
  http.POST(jsonBody);
  http.end();
  
  Serial.println("   📤 Pickup notification sent");
}

void notifyLibrarian(String userId, String eventType) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(supabaseUrl) + "/rest/v1/notifications";
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", String("Bearer ") + supabaseKey);
  
  StaticJsonDocument<400> doc;
  doc["user_id"] = userId;
  doc["type"] = eventType;
  doc["message"] = "Student scanned QR code at Shelf #" + String(shelfNumber);
  doc["is_read"] = false;
  
  String jsonBody;
  serializeJson(doc, jsonBody);
  http.POST(jsonBody);
  http.end();
  
  Serial.println("   📬 Librarian notified");
}

void notifyDoorStatus(String status) {
  Serial.printf("   🚪 Door status: %s\n", status.c_str());
}
