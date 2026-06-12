#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_PN532.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>
#include <WiFi.h>
#include <HTTPClient.h>


// GLOBAL CONFIGURATION & NETWORK CREDENTIALS
const char* ssid     = "andyss27-hotspot";          
const char* password = "731D98026928C149A599081639";

const char* mirthUrl = "http://10.42.0.1:8081/api/telemetry/";

// HARDWARE PIN DEFINITIONS
#define PN532_IRQ   2
#define PN532_RESET 4

#define SERVO1_PIN  25   
#define SERVO2_PIN  26   

#define LED_VERDE   16    // Alert indicator for Compartment A out-of-stock
#define LED_AZUL    4     // Alert indicator for Compartment b out-of-stock
#define BUZZER_PIN  13    // Audio feedback indicator for errors and lockouts

// PERIPHERIAL INITIALIZATIONS
LiquidCrystal_I2C lcd(0x27, 16, 2);
Adafruit_PN532 nfc(PN532_IRQ, PN532_RESET);
Servo servo1;
Servo servo2;

// TIMING, OPERATIONAL CONSTANTS AND SYSTEM STATE
#define SERVO_REST        0     // Rest angle for continous/standard servo
#define SERVO_DISPENSE    180   // Actuation angle for dispensing medicine
#define TIME_DISPENSE     1200  // Duration for ful physical dispensation
#define PAUSE_CYCLE       2000  // Guard interval between RFID read attempts
#define COOLDOWN_DISPENSE 30000 // Mandatory user cooldown lockout period (30)

// Non-blocking asynchronous task scheduler (Time tracking variables)
unsigned long chronometerCooldown = 0; 
unsigned long lastDispenseTimeA   = 0;    
unsigned long lastDispenseTimeB   = 0;    
unsigned long lastScreenRefresh   = 0; 
unsigned long buzzerTurnOffTime   = 0; 

// Medication inventory state variables
int inventoryA = 0;
int inventoryB = 0;

// Deplucation state variables to prevent redundant serial/MATLAB stream flooding
int lastSentA = -1; 
int lastSentB = -1;

// DATA STRUCTURES AND AUTHENTICATION ACCESS CONTROL
struct Card {
  uint8_t uid[7]; // Target unique hardware identifier array
  uint8_t length; // Expected byte length of the UID token
  uint8_t servo;  // Linked hardware payload compartment target (1=A, 2=B)
};

const uint8_t NUM_CARDS = 2; 
Card cardsAuthorized[NUM_CARDS] = {
  { {0x04, 0xAF, 0x6D, 0x02, 0xB8, 0x1B, 0x90}, 7, 1 }, // Linked to Medication Compartment A
  { {0x04, 0x57, 0x57, 0x72, 0x8D, 0x20, 0x90}, 7, 2 }  // Linked to Medication Compartment B
};

// Forward declaration of display update routine
void refreshScreen();

// NETWORK AND COMMUNICATIONS STACK
// Initializes the Wi-Fi connection with a deterministic connection timeout
void setupWiFi() {
  delay(10);
  Serial.println();
  Serial.print("Connecting to network: ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 15) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[Wi-Fi] Connected successfully!");
    Serial.print("[Wi-Fi] ESP32 Local IP address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n[Wi-Fi] Warning: Connection timeout. System running offline mode.");
  }
}

// Forwards structured telemetry payloads to Mirth Connect using HTTP POST
void sendMirthNotification(String statusEvent, String compartment, String cardUID) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Mirth Link] Transmission dropped: Wi-Fi link not established.");
    return;
  }
  
  HTTPClient http;
  http.begin(mirthUrl);

  // Critical safeguard threshold. Prevents I/O blocking during server cold starts
  http.setTimeout(500); 

  http.addHeader("Content-Type", "application/json");

  // Assembling normalized JSON telemetry frame
  String jsonPayload = "{\"status\":\"" + statusEvent + 
                       "\",\"compartment\":\"" + compartment + 
                       "\",\"uid\":\"" + cardUID + 
                       "\",\"stockA\":" + String(inventoryA) + 
                       ",\"stockB\":" + String(inventoryB) + "}";

  Serial.print("[Mirth Link] Sending payload: ");
  Serial.println(jsonPayload);

  int httpResponseCode = http.POST(jsonPayload);

  if (httpResponseCode > 0) {
    Serial.print("[Mirth Link] Dispatch complete. Code received: ");
    Serial.println(httpResponseCode);
  } else {
    Serial.print("[Mirth Link] Transport crash error code: ");
    Serial.println(http.errorToString(httpResponseCode).c_str());
  }
  http.end();
}

// RFID CARD UTILITIES & ACCESS SEARCH MATCHERS
// Prints the formatted hex identifier string of an RFID tag to the serial link
void printUID(uint8_t* uid, uint8_t length) {
  Serial.print("UID detected: ");
  for (uint8_t i = 0; i < length; i++) {
    if (uid[i] < 0x10) Serial.print("0"); 
    Serial.print(uid[i], HEX);
    if (i < length - 1) Serial.print(":");
  }
  Serial.println();
}

// Searches the registry array for an explicit cryptographic hardware match
int searchCard(uint8_t* uid, uint8_t length) {
  for (uint8_t i = 0; i < NUM_CARDS; i++) {
    if (length != cardsAuthorized[i].length) continue;
    bool coincide = true;
    for (uint8_t j = 0; j < length; j++) {
      if (uid[j] != cardsAuthorized[i].uid[j]) {
        coincide = false;
        break;
      }
    }
    if (coincide) return i; 
  }
  return -1; 
}

// HARDWARE ACTUATION MECHANICAL CONTROLS
// Executes a synchronized physical sweep actuation cycle on the target servo
void dispense(uint8_t numberServo) {
  Serial.print(">> Dispensing with servo ");
  Serial.println(numberServo);

  if (numberServo == 1) {
    servo1.write(SERVO_DISPENSE);       
    delay(TIME_DISPENSE);             
    servo1.write(SERVO_REST);         
  } else if (numberServo == 2) {
    servo2.write(SERVO_DISPENSE);
    delay(TIME_DISPENSE);
    servo2.write(SERVO_REST);
  }
  Serial.println(">> Servo in rest position");
}

// MAIN SYSTEM HARDWARE BOOTSTRAP INITIALIZATION
void setup() {
  Serial.begin(115200);
  Serial.setTimeout(50);    // Optimized for parsing direct serial commands from MATLAB
  
  pinMode(LED_VERDE, OUTPUT);
  pinMode(LED_AZUL, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);     
  
  digitalWrite(LED_VERDE, LOW);
  digitalWrite(LED_AZUL, LOW);
  digitalWrite(BUZZER_PIN, LOW);   

  Wire.begin(21, 22);       // Custom I2C Interface Configuration (SDA, SCL Pins)

  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Setup...");
  
  setupWiFi(); 

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);
  servo1.write(SERVO_REST); 
  servo2.write(SERVO_REST);

  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("ERROR: PN532 not found.");
    while (1) {   // Infinite hardware panic loop indicator
      digitalWrite(LED_VERDE, HIGH); digitalWrite(LED_AZUL, HIGH); delay(200); 
      digitalWrite(LED_VERDE, LOW);  digitalWrite(LED_AZUL, LOW);  delay(200);
    } 
  }
  nfc.SAMConfig(); 
  
  delay(1500);
  refreshScreen(); 
}

// MAIN EXECUTIVE CORE PROCESSING LOOP
void loop() {
    // Shuts down buzzer cleanly without using delay()
    if (buzzerTurnOffTime != 0 && millis() >= buzzerTurnOffTime) {
        digitalWrite(BUZZER_PIN, LOW);
        buzzerTurnOffTime = 0;
    }

    // Dynamic Live LCD Update Loop running at fixed 1-second intervals
    if (millis() - lastScreenRefresh >= 1000) {
        refreshScreen();
        lastScreenRefresh = millis();
    }

    // Checking incoming hardware commands routed via the serial stream from MATLAB
    if (Serial.available()) {
        String command = Serial.readStringUntil('\n');
        command.trim();

        if (command == "LOAD_MED_1") {
          inventoryA++;
          refreshScreen();            
          sendMirthNotification("STOCK_RELOAD", "A", "MATLAB_SYS");     
        }
        else if (command == "LOAD_MED_2") {
          inventoryB++;
          refreshScreen(); 
          sendMirthNotification("STOCK_RELOAD", "B", "MATLAB_SYS");                
        }
    }

    // Scheduled non-blocking poll task check loop for RFID scanning
    if (millis() - chronometerCooldown >= PAUSE_CYCLE) {
        uint8_t uid[7] = {0}; 
        uint8_t uidLength = 0;   

        // Fast-polling scanner execution pass 
        bool detected = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 60);

        if (detected) {
          Serial.println("RFID Card detected");
          printUID(uid, uidLength);

          // Convert raw byte block to String 
          String cardUidStr = "";
          for (uint8_t i = 0; i < uidLength; i++) {
            if (uid[i] < 0x10) cardUidStr += "0";
            cardUidStr += String(uid[i], HEX);
          }
          cardUidStr.toUpperCase();

          int idx = searchCard(uid, uidLength);

          // Scenario A: Found a valid registered card token entry
          if (idx >= 0) {
              uint8_t assignedServo = cardsAuthorized[idx].servo;
              
              // Validate dynamic software cooldown lockout timers independently
              bool isBlocked = false;
              if (assignedServo == 1 && lastDispenseTimeA != 0 && (millis() - lastDispenseTimeA < COOLDOWN_DISPENSE)) {
                  isBlocked = true;
              } else if (assignedServo == 2 && lastDispenseTimeB != 0 && (millis() - lastDispenseTimeB < COOLDOWN_DISPENSE)) {
                  isBlocked = true;
              }

              // Exception State 1: Action rejected due to Cooldown active
              if (isBlocked) {
                Serial.print("ACCESS DENIED - Compartment ");
                Serial.print(assignedServo == 1 ? "A" : "B");
                Serial.println(" is in cooldown! Please wait.");
                
                String comp = (assignedServo == 1) ? "A" : "B";
                sendMirthNotification("ERROR_COOLDOWN_LOCKOUT", comp, cardUidStr);
                
                digitalWrite(BUZZER_PIN, HIGH);
                buzzerTurnOffTime = millis() + 3000;  // Queue buzzer shutdown in 3 seconds
                
                refreshScreen();
              }

              // Normal Execution Flow 1: Action approved for Compartment A
              else if (assignedServo == 1 && inventoryA > 0) {
                Serial.println("ACCESS GRANTED → Dispensing A");
                dispense(assignedServo);
                inventoryA--; 
                lastDispenseTimeA = millis(); 
                refreshScreen(); 
                
                sendMirthNotification("DISPENSE_SUCCESS", "A", cardUidStr);
              }

              // Normal Execution Flow 2: Action approved for Compartment B
              else if (assignedServo == 2 && inventoryB > 0) {
                Serial.println("ACCESS GRANTED → Dispensing B");
                dispense(assignedServo);
                inventoryB--; 
                lastDispenseTimeB = millis(); 
                refreshScreen(); 
                
                sendMirthNotification("DISPENSE_SUCCESS", "B", cardUidStr);
              } 

              // Exception State 2: Valid token, but inventory empty
              else {
                Serial.println("ACCESS DENIED - Out of Stock!");
                lcd.clear();
                lcd.setCursor(0,0); lcd.print("ACCESS DENIED!");
                lcd.setCursor(0,1); lcd.print("NO STOCK LEFT!");
                delay(1500);
                refreshScreen();
                
                String comp = (assignedServo == 1) ? "A" : "B";
                sendMirthNotification("ERROR_OUT_OF_STOCK", comp, cardUidStr);
              }
          } 
          
          // Exception State 3: Card is unregistered in local firmware list
          else {
            Serial.println("ACCESS DENIED - Card not registered.");
            lcd.clear();
            lcd.setCursor(0,0); lcd.print("ACCESS DENIED!");
            lcd.setCursor(0,1); lcd.print("UNKNOWN CARD!");
            delay(1500);
            refreshScreen();
            
            sendMirthNotification("ERROR_UNKNOWN_CARD", "NONE", cardUidStr);
          }
          chronometerCooldown = millis();   // Reset cycle baseline timestamp
      }
    }
}

// DISPLAY INTERFACE & TELEMETRY DUPLICATION FILTER ENGINE
void refreshScreen() {
    // Dynamic out-of-stock warning lights processing
    if (inventoryA == 0) digitalWrite(LED_VERDE, HIGH); else digitalWrite(LED_VERDE, LOW);
    if (inventoryB == 0) digitalWrite(LED_AZUL, HIGH);  else digitalWrite(LED_AZUL, LOW);

    unsigned long timeLeftA = 0;
    unsigned long timeLeftB = 0;
    
    // Evaluate exact localized cooldown delays remaining (rounded up cleanly)
    if (lastDispenseTimeA != 0) {
        unsigned long elapsedA = millis() - lastDispenseTimeA;
        if (elapsedA < COOLDOWN_DISPENSE) {
            timeLeftA = ((COOLDOWN_DISPENSE - elapsedA) + 999) / 1000;
        }
    }
    if (lastDispenseTimeB != 0) {
        unsigned long elapsedB = millis() - lastDispenseTimeB;
        if (elapsedB < COOLDOWN_DISPENSE) {
            timeLeftB = ((COOLDOWN_DISPENSE - elapsedB) + 999) / 1000;
        }
    }

    // Text Render Routine: String line buffer allocations 
    char line0[17];
    snprintf(line0, sizeof(line0), "A:%02d pc  B:%02d pc ", inventoryA, inventoryB);
    lcd.setCursor(0, 0);
    lcd.print(line0);

    char line1[17];
    if (timeLeftA > 0 || timeLeftB > 0) {
        if (timeLeftA > 0 && timeLeftB > 0) {
            snprintf(line1, sizeof(line1), "A:%02ds  B:%02ds   ", (int)timeLeftA, (int)timeLeftB);
        } else if (timeLeftA > 0) {
            snprintf(line1, sizeof(line1), "A:%02ds  B:READY   ", (int)timeLeftA);
        } else {
            snprintf(line1, sizeof(line1), "A:READY  B:%02ds   ", (int)timeLeftB);
        }
    } else {
        if (inventoryA == 0 && inventoryB == 0) {
            snprintf(line1, sizeof(line1), "OUT OF STOCK ALL"); 
        }
        else if (inventoryA == 0) {
            snprintf(line1, sizeof(line1), "EMPTY COMPART. A"); 
        }
        else if (inventoryB == 0) {
            snprintf(line1, sizeof(line1), "EMPTY COMPART. B"); 
        }
        else if (inventoryA <= 2 || inventoryB <= 2) {
            snprintf(line1, sizeof(line1), "LOW INVENTORY  "); 
        }
        else {
            snprintf(line1, sizeof(line1), "SYSTEM OK       ");
        }
    }
    lcd.setCursor(0, 1);
    lcd.print(line1);

    // Only streams payload line if dynamic stock state shifts
    if (inventoryA != lastSentA || inventoryB != lastSentB) {
        Serial.print("STOCK_UPDATE:MED_A=");
        Serial.print(inventoryA);
        Serial.print(",MED_B=");
        Serial.println(inventoryB);
        
        // Synchronize cache to block continuous duplicate stream transmissions to MATLAB
        lastSentA = inventoryA;
        lastSentB = inventoryB;
    }
}