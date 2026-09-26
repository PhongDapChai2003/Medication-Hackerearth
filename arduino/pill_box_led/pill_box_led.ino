#include <ArduinoBLE.h>

const char DEVICE_NAME[] = "Medication Pill Box";
const char SERVICE_UUID[] = "7b9a0001-9f6b-4c2a-8b8f-6d0c0a000001";
const char COMMAND_UUID[] = "7b9a0002-9f6b-4c2a-8b8f-6d0c0a000001";
const char RESPONSE_UUID[] = "7b9a0003-9f6b-4c2a-8b8f-6d0c0a000001";

// 3 x 7 shared matrix from the wiring drawing:
// D2 = red cathode row, D3 = green cathode row, D4 = reed-sensor row,
// and D5-D11 = the seven common-anode/sensor columns. Each reed-switch branch
// requires a 1N4148 isolation diode, with its stripe facing the column.
constexpr uint8_t RED_ROW_PIN = 2;
constexpr uint8_t GREEN_ROW_PIN = 3;
constexpr uint8_t SENSOR_ROW_PIN = 4;
constexpr uint8_t COLUMN_PINS[] = {5, 6, 7, 8, 9, 10, 11};
constexpr uint8_t BUZZER_PIN = 12;
constexpr uint8_t SLOT_COUNT = 7;
constexpr uint8_t MAX_SCHEDULES = 28;
constexpr unsigned long BLINK_MS = 500;
constexpr unsigned long DISPLAY_SLICE_MS = 3;
constexpr unsigned long DEBOUNCE_MS = 35;
// Six short syllable-like pulses. An active buzzer has one fixed pitch, so
// this creates a gentle original rhythm rather than copying a song melody.
constexpr uint16_t BUZZER_STEP_MS[] = {
  70, 70, 140, 80, 220, 180, 120, 70, 140, 70, 220, 900
};

struct ScheduledDose {
  uint8_t slot;
  uint16_t minuteOfDay;
};

BLEService pillBoxService(SERVICE_UUID);
BLEStringCharacteristic commandCharacteristic(COMMAND_UUID, BLEWrite, 64);
BLEStringCharacteristic responseCharacteristic(
    RESPONSE_UUID, BLERead | BLENotify, 128);
int targetSlot = -1;
bool pendingSlots[SLOT_COUNT] = {};
bool correctLidOpen = false;
bool blinkOn = false;
unsigned long lastBlinkAt = 0;
bool showWrongSlice = false;
unsigned long lastDisplaySliceAt = 0;
bool buzzerPatternRunning = false;
uint8_t buzzerPatternStep = 0;
unsigned long buzzerPatternChangedAt = 0;
bool lastRaw[SLOT_COUNT] = {};
bool stableOpen[SLOT_COUNT] = {};
bool lidArmed[SLOT_COUNT] = {};
unsigned long rawChangedAt[SLOT_COUNT] = {};
ScheduledDose schedules[MAX_SCHEDULES] = {};
uint8_t scheduleCount = 0;
bool clockSynchronized = false;
uint32_t clockStartSecondOfDay = 0;
unsigned long clockStartedAt = 0;
int lastScheduleMinute = -1;

enum class LedColor : uint8_t { red, green };

void releaseColumns() {
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    pinMode(COLUMN_PINS[slot], INPUT);
  }
}

void ledsOff() {
  digitalWrite(RED_ROW_PIN, HIGH);
  digitalWrite(GREEN_ROW_PIN, HIGH);
  releaseColumns();
}

void showLed(int slot, LedColor color, bool on) {
  ledsOff();
  if (!on || slot < 0 || slot >= SLOT_COUNT) return;
  pinMode(COLUMN_PINS[slot], OUTPUT);
  digitalWrite(COLUMN_PINS[slot], HIGH);
  digitalWrite(
      color == LedColor::red ? RED_ROW_PIN : GREEN_ROW_PIN,
      LOW);
}

int firstOpenWrongLid() {
  if (targetSlot < 0) return -1;
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    if (slot != targetSlot && lidArmed[slot] && stableOpen[slot]) return slot;
  }
  return -1;
}

void setBuzzer(bool on) {
  // The selected active-buzzer module is low-level triggered.
  digitalWrite(BUZZER_PIN, on ? LOW : HIGH);
}

void updateBuzzerPattern(bool alarmActive) {
  if (!alarmActive) {
    buzzerPatternRunning = false;
    buzzerPatternStep = 0;
    setBuzzer(false);
    return;
  }

  const unsigned long now = millis();
  if (!buzzerPatternRunning) {
    buzzerPatternRunning = true;
    buzzerPatternStep = 0;
    buzzerPatternChangedAt = now;
    setBuzzer(true);
    return;
  }

  if (now - buzzerPatternChangedAt >= BUZZER_STEP_MS[buzzerPatternStep]) {
    buzzerPatternStep =
        (buzzerPatternStep + 1) %
        (sizeof(BUZZER_STEP_MS) / sizeof(BUZZER_STEP_MS[0]));
    buzzerPatternChangedAt = now;
    setBuzzer((buzzerPatternStep % 2) == 0);
  }
}

void updateLed() {
  if (targetSlot < 0) {
    updateBuzzerPattern(false);
    showLed(-1, LedColor::red, false);
    return;
  }

  const int wrongSlot = firstOpenWrongLid();
  if (wrongSlot >= 0) {
    updateBuzzerPattern(true);
    unsigned long now = millis();
    if (now - lastBlinkAt >= BLINK_MS) {
      lastBlinkAt = now;
      blinkOn = !blinkOn;
    }
    if (!blinkOn) {
      showWrongSlice = false;
      showLed(targetSlot, LedColor::green, true);
      return;
    }
    if (now - lastDisplaySliceAt >= DISPLAY_SLICE_MS) {
      lastDisplaySliceAt = now;
      showWrongSlice = !showWrongSlice;
    }
    showLed(
        showWrongSlice ? wrongSlot : targetSlot,
        showWrongSlice ? LedColor::red : LedColor::green,
        true);
    return;
  }

  updateBuzzerPattern(false);
  showWrongSlice = false;
  showLed(targetSlot, LedColor::green, true);
}

void lidOpened(uint8_t slot) {
  if (targetSlot < 0) return;
  if (!lidArmed[slot]) return;
  if (slot == targetSlot) {
    targetSlot = -1;
    correctLidOpen = false;
    blinkOn = false;
    showWrongSlice = false;
    updateBuzzerPattern(false);
    ledsOff();
    for (uint8_t nextSlot = 0; nextSlot < SLOT_COUNT; nextSlot++) {
      if (pendingSlots[nextSlot]) {
        pendingSlots[nextSlot] = false;
        selectSlot(nextSlot);
        break;
      }
    }
  }
}

void lidClosed(uint8_t slot) {
  // A disconnected test input looks open. Arm a lid only after the firmware
  // has seen it closed, which allows one-cell breadboard testing while keeping
  // normal wrong-lid detection for every connected compartment.
  lidArmed[slot] = true;
}

void scanSwitches() {
  bool raw[SLOT_COUNT] = {};

  // Do not drive LEDs while reading the shared reed-switch row. A normally
  // open reed is closed by the magnet when the lid is closed, so D4 reads LOW
  // for closed and HIGH for open.
  ledsOff();
  pinMode(SENSOR_ROW_PIN, INPUT_PULLUP);
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    pinMode(COLUMN_PINS[slot], OUTPUT);
    digitalWrite(COLUMN_PINS[slot], LOW);
    delayMicroseconds(60);
    raw[slot] = digitalRead(SENSOR_ROW_PIN) == HIGH;
    pinMode(COLUMN_PINS[slot], INPUT);
  }
  pinMode(SENSOR_ROW_PIN, INPUT);

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
  correctLidOpen = false;
  blinkOn = true;
  lastBlinkAt = millis();
  showWrongSlice = false;
  lastDisplaySliceAt = millis();
  updateBuzzerPattern(false);
  for (uint8_t lid = 0; lid < SLOT_COUNT; lid++) {
    lidArmed[lid] = !stableOpen[lid];
  }
  showLed(targetSlot, LedColor::green, true);
}

void clearReminder() {
  targetSlot = -1;
  correctLidOpen = false;
  blinkOn = false;
  showWrongSlice = false;
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) pendingSlots[slot] = false;
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) lidArmed[slot] = false;
  updateBuzzerPattern(false);
  ledsOff();
}

void clearSchedules() {
  scheduleCount = 0;
}

bool addSchedule(uint8_t slot, uint16_t minuteOfDay) {
  if (scheduleCount >= MAX_SCHEDULES) return false;
  for (uint8_t i = 0; i < scheduleCount; i++) {
    if (schedules[i].slot == slot && schedules[i].minuteOfDay == minuteOfDay) {
      return true;
    }
  }
  schedules[scheduleCount++] = {slot, minuteOfDay};
  return true;
}

void synchronizeClock(uint32_t secondOfDay) {
  clockStartSecondOfDay = secondOfDay;
  clockStartedAt = millis();
  clockSynchronized = true;
  lastScheduleMinute = secondOfDay / 60;
}

void updateScheduledReminders() {
  if (!clockSynchronized) return;

  const uint32_t secondsPerDay = 24UL * 60UL * 60UL;
  const uint32_t elapsedSeconds = (millis() - clockStartedAt) / 1000UL;
  const uint32_t currentSecondOfDay =
      (clockStartSecondOfDay + elapsedSeconds) % secondsPerDay;
  const int currentMinute = currentSecondOfDay / 60;
  if (currentMinute == lastScheduleMinute) return;
  lastScheduleMinute = currentMinute;

  for (uint8_t i = 0; i < scheduleCount; i++) {
    if (schedules[i].minuteOfDay == currentMinute) {
      pendingSlots[schedules[i].slot] = true;
    }
  }
  if (targetSlot < 0) {
    for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
      if (pendingSlots[slot]) {
        pendingSlots[slot] = false;
        selectSlot(slot);
        break;
      }
    }
  }
}

void sendResponse(
    const String &requestId,
    bool ok,
    const String &message) {
  String body = "{\"ok\":";
  body += ok ? "true" : "false";
  body += ",\"message\":\"" + message + "\",\"activeSlot\":" + String(targetSlot);
  body += "}";
  responseCharacteristic.writeValue(requestId + "|" + body);
}

bool parseInteger(
    const String &value,
    int minimum,
    int maximum,
    int &result) {
  if (value.length() == 0) return false;
  for (unsigned int i = 0; i < value.length(); i++) {
    if (!isDigit(value[i])) return false;
  }
  result = value.toInt();
  return result >= minimum && result <= maximum;
}

void handleBluetoothCommand() {
  if (!commandCharacteristic.written()) return;

  const String incoming = commandCharacteristic.value();
  const int divider = incoming.indexOf('|');
  if (divider <= 0 || divider >= incoming.length() - 1) {
    sendResponse("0", false, "Invalid command.");
    return;
  }

  const String requestId = incoming.substring(0, divider);
  const String command = incoming.substring(divider + 1);

  if (command == "STATUS") {
    sendResponse(requestId, true, "Pill box connected.");
  } else if (command == "OFF") {
    clearReminder();
    sendResponse(requestId, true, "Reminder off.");
  } else if (command == "SCHEDULE_CLEAR") {
    clearSchedules();
    sendResponse(requestId, true, "Reminder schedule cleared.");
  } else if (command.startsWith("SCHEDULE_ADD,")) {
    const int separator = command.indexOf(',', 13);
    int slot = -1;
    int minuteOfDay = -1;
    if (separator > 13 &&
        parseInteger(
            command.substring(13, separator),
            0,
            SLOT_COUNT - 1,
            slot) &&
        parseInteger(
            command.substring(separator + 1),
            0,
            (24 * 60) - 1,
            minuteOfDay) &&
        addSchedule(slot, minuteOfDay)) {
      sendResponse(requestId, true, "Reminder time saved.");
    } else {
      sendResponse(
          requestId,
          false,
          "Invalid reminder time or schedule is full.");
    }
  } else if (command.startsWith("CLOCK,")) {
    int secondOfDay = -1;
    if (parseInteger(
            command.substring(6),
            0,
            (24 * 60 * 60) - 1,
            secondOfDay)) {
      synchronizeClock(secondOfDay);
      sendResponse(requestId, true, "Pill box clock synchronized.");
    } else {
      sendResponse(requestId, false, "Invalid clock value.");
    }
  } else if (command.startsWith("SLOT,")) {
    int slot = -1;
    if (parseInteger(command.substring(5), 0, SLOT_COUNT - 1, slot)) {
      selectSlot(slot);
      sendResponse(requestId, true, "Correct compartment lit.");
    } else {
      sendResponse(requestId, false, "Slot must be 0 to 6.");
    }
  } else {
    sendResponse(requestId, false, "Unknown command.");
  }
}

void configureHardware() {
  digitalWrite(RED_ROW_PIN, HIGH);
  pinMode(RED_ROW_PIN, OUTPUT);
  digitalWrite(GREEN_ROW_PIN, HIGH);
  pinMode(GREEN_ROW_PIN, OUTPUT);
  pinMode(SENSOR_ROW_PIN, INPUT);
  releaseColumns();
  digitalWrite(BUZZER_PIN, HIGH);
  pinMode(BUZZER_PIN, OUTPUT);
  ledsOff();
}

void startupTest() {
  for (uint8_t slot = 0; slot < SLOT_COUNT; slot++) {
    showLed(slot, LedColor::red, true);
    delay(80);
    showLed(slot, LedColor::green, true);
    delay(80);
  }
  ledsOff();
}

void startBluetooth() {
  Serial.print("Starting Bluetooth: ");
  Serial.println(DEVICE_NAME);
  if (!BLE.begin()) {
    Serial.println("Bluetooth failed. Restart board.");
    while (true) delay(1000);
  }

  BLE.setDeviceName(DEVICE_NAME);
  BLE.setLocalName(DEVICE_NAME);
  BLE.setAdvertisedService(pillBoxService);
  pillBoxService.addCharacteristic(commandCharacteristic);
  pillBoxService.addCharacteristic(responseCharacteristic);
  BLE.addService(pillBoxService);
  responseCharacteristic.writeValue(
      "0|{\"ok\":true,\"message\":\"Ready.\",\"activeSlot\":-1}");
  BLE.advertise();
  Serial.println("Bluetooth advertising started.");
}

void setup() {
  Serial.begin(115200);
  configureHardware();
  startupTest();
  startBluetooth();
  Serial.println("7-compartment pill box ready.");
}

void loop() {
  BLE.poll();
  scanSwitches();
  updateScheduledReminders();
  updateLed();
  handleBluetoothCommand();
}
