#include <WiFiS3.h>

const char WIFI_NAME[] = "Medication-Pill-Box";
const char WIFI_PASSWORD[] = "pillbox21";

// 10 compartments: 2 rows x 5 columns.
constexpr uint8_t LED_ROWS[] = {2, 3};
constexpr uint8_t LED_COLUMNS[] = {A0, A1, A2, A3, A4};

// Switch rows D4-D5 and columns D6-D10. D11 is unused.
constexpr uint8_t SWITCH_ROWS[] = {4, 5};
constexpr uint8_t SWITCH_COLUMNS[] = {6, 7, 8, 9, 10};
constexpr uint8_t BUZZER_PIN = A5;
constexpr uint8_t ROWS = 2;
constexpr uint8_t COLUMNS = 5;
constexpr uint8_t SLOT_COUNT = 10;
constexpr unsigned long BLINK_MS = 500;
constexpr unsigned long DEBOUNCE_MS = 35;

WiFiServer server(80);
int targetSlot = -1;
bool correctLidOpen = false;
bool blinkOn = false;
unsigned long lastBlinkAt = 0;
bool lastRaw[SLOT_COUNT] = {};
bool stableOpen[SLOT_COUNT] = {};
unsigned long rawChangedAt[SLOT_COUNT] = {};

void ledsOff() {
  for (uint8_t r = 0; r < ROWS; r++) digitalWrite(LED_ROWS[r], HIGH);
  for (uint8_t c = 0; c < COLUMNS; c++) digitalWrite(LED_COLUMNS[c], LOW);
}

void showLed(int slot, bool on) {
  ledsOff();
  if (!on || slot < 0 || slot >= SLOT_COUNT) return;
  digitalWrite(LED_COLUMNS[slot % COLUMNS], HIGH);
  digitalWrite(LED_ROWS[slot / COLUMNS], LOW);
}

void updateLed() {
  if (targetSlot < 0) {
    showLed(-1, false);
    return;
  }
  if (correctLidOpen) {
    showLed(targetSlot, true);
    return;
  }
  unsigned long now = millis();
  if (now - lastBlinkAt >= BLINK_MS) {
    lastBlinkAt = now;
    blinkOn = !blinkOn;
  }
  showLed(targetSlot, blinkOn);
}

void wrongLidAlarm() {
  for (uint8_t i = 0; i < 3; i++) {
    tone(BUZZER_PIN, 2200);
    delay(140);
    noTone(BUZZER_PIN);
    delay(110);
  }
}

void lidOpened(uint8_t slot) {
  if (targetSlot < 0) return;
  if (slot == targetSlot) {
    correctLidOpen = true;
    blinkOn = true;
    showLed(targetSlot, true);
  } else {
    wrongLidAlarm();
  }
}

void lidClosed(uint8_t slot) {
  if (slot == targetSlot && correctLidOpen) {
    targetSlot = -1;
    correctLidOpen = false;
    blinkOn = false;
    ledsOff();
  }
}

void scanSwitches() {
  bool raw[SLOT_COUNT] = {};
  for (uint8_t row = 0; row < ROWS; row++) {
    for (uint8_t other = 0; other < ROWS; other++) pinMode(SWITCH_ROWS[other], INPUT);
    pinMode(SWITCH_ROWS[row], OUTPUT);
    digitalWrite(SWITCH_ROWS[row], LOW);
    delayMicroseconds(60);
    for (uint8_t col = 0; col < COLUMNS; col++) {
      raw[row * COLUMNS + col] = digitalRead(SWITCH_COLUMNS[col]) == LOW;
    }
    pinMode(SWITCH_ROWS[row], INPUT);
  }

  unsigned long now = millis();
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    if (raw[slot] != lastRaw[slot]) {
      lastRaw[slot] = raw[slot];
      rawChangedAt[slot] = now;
    }
    if (raw[slot] != stableOpen[slot] && now - rawChangedAt[slot] >= DEBOUNCE_MS) {
      stableOpen[slot] = raw[slot];
      if (stableOpen[slot]) lidOpened(slot);
      else lidClosed(slot);
    }
  }
}

void selectSlot(int slot) {
  targetSlot = slot;
  correctLidOpen = stableOpen[slot];
  blinkOn = true;
  lastBlinkAt = millis();
  showLed(targetSlot, true);
}

void clearReminder() {
  targetSlot = -1;
  correctLidOpen = false;
  blinkOn = false;
  noTone(BUZZER_PIN);
  ledsOff();
}

void sendJson(WiFiClient &client, int code, const String &message) {
  String body = "{\"ok\":";
  body += code == 200 ? "true" : "false";
  body += ",\"message\":\"" + message + "\",\"activeSlot\":" + String(targetSlot);
  body += ",\"correctLidOpen\":";
  body += correctLidOpen ? "true" : "false";
  body += "}";
  client.print("HTTP/1.1 ");
  client.print(code);
  client.println(code == 200 ? " OK" : " Bad Request");
  client.println("Content-Type: application/json");
  client.println("Access-Control-Allow-Origin: *");
  client.println("Connection: close");
  client.print("Content-Length: ");
  client.println(body.length());
  client.println();
  client.print(body);
}

bool getSlot(const String &line, int &slot) {
  int start = line.indexOf('=') + 1;
  int finish = line.indexOf(' ', start);
  if (start <= 0 || finish <= start) return false;
  String value = line.substring(start, finish);
  if (value.length() == 0) return false;
  for (unsigned int i = 0; i < value.length(); i++) if (!isDigit(value[i])) return false;
  slot = value.toInt();
  return slot >= 0 && slot < SLOT_COUNT;
}

void handleRequest() {
  WiFiClient client = server.available();
  if (!client) return;
  client.setTimeout(1000);
  String request = client.readStringUntil('\r');
  client.readStringUntil('\n');
  while (client.connected()) {
    String header = client.readStringUntil('\n');
    if (header == "\r" || header.length() == 0) break;
  }
  if (request.startsWith("GET /status ")) {
    sendJson(client, 200, "Pill box connected.");
  } else if (request.startsWith("GET /off ")) {
    clearReminder();
    sendJson(client, 200, "Reminder off.");
  } else if (request.startsWith("GET /slot?index=")) {
    int slot = -1;
    if (getSlot(request, slot)) {
      selectSlot(slot);
      sendJson(client, 200, "Correct compartment blinking.");
    } else {
      sendJson(client, 400, "Slot must be 0 to 9.");
    }
  } else {
    sendJson(client, 400, "Unknown command.");
  }
  delay(2);
  client.stop();
}

void configureHardware() {
  for (uint8_t r = 0; r < ROWS; r++) {
    digitalWrite(LED_ROWS[r], HIGH);
    pinMode(LED_ROWS[r], OUTPUT);
    pinMode(SWITCH_ROWS[r], INPUT);
  }
  for (uint8_t c = 0; c < COLUMNS; c++) {
    digitalWrite(LED_COLUMNS[c], LOW);
    pinMode(LED_COLUMNS[c], OUTPUT);
    pinMode(SWITCH_COLUMNS[c], INPUT_PULLUP);
  }
  pinMode(BUZZER_PIN, OUTPUT);
  noTone(BUZZER_PIN);
  ledsOff();
}

void startupTest() {
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    showLed(slot, true);
    delay(100);
  }
  ledsOff();
}

void startNetwork() {
  Serial.print("Starting Wi-Fi: ");
  Serial.println(WIFI_NAME);
  if (WiFi.beginAP(WIFI_NAME, WIFI_PASSWORD) != WL_AP_LISTENING) {
    Serial.println("Wi-Fi failed. Restart board.");
    while (true) delay(1000);
  }
  delay(3000);
  Serial.print("Arduino address: ");
  Serial.println(WiFi.localIP());
}

void setup() {
  Serial.begin(115200);
  configureHardware();
  startupTest();
  startNetwork();
  server.begin();
  Serial.println("10-compartment pill box ready.");
}

void loop() {
  scanSwitches();
  updateLed();
  handleRequest();
}
