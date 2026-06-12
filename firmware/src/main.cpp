#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_PN532.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>
#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid     = "andyss27-hotspot";          
const char* password = "731D98026928C149A599081639";

const char* mirthUrl = "http://10.42.0.1:8081/api/telemetry"; 

#define PN532_IRQ   2
#define PN532_RESET 4

#define SERVO1_PIN  25   
#define SERVO2_PIN  26   

#define LED_VERDE   16   
#define LED_AZUL    17   

LiquidCrystal_I2C lcd(0x27, 16, 2);

#define SERVO_REST     0     
#define SERVO_DISPENSE 180   
#define TIME_DISPENSE  1200  
#define PAUSE_CYCLE    2000  

unsigned long chronometerCooldown = 0; 

int inventoryA = 10;
int inventoryB = 10;

struct Card {
  uint8_t uid[7];   
  uint8_t length;   
  uint8_t servo;    
};

const uint8_t NUM_CARDS = 2; 
Card cardsAuthorized[NUM_CARDS] = {
  { {0x04, 0xAF, 0x6D, 0x02, 0xB8, 0x1B, 0x90}, 7, 1 }, 
  { {0x04, 0x57, 0x57, 0x72, 0x8D, 0x20, 0x90}, 7, 2 }  
};

Adafruit_PN532 nfc(PN532_IRQ, PN532_RESET);
Servo servo1;
Servo servo2;

void refreshScreen();

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

void sendMirthNotification(String statusEvent, String compartment, String cardUID) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(mirthUrl);
    http.addHeader("Content-Type", "application/json");

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
  } else {
    Serial.println("[Mirth Link] Transmission dropped: Wi-Fi link not established.");
  }
}

void printUID(uint8_t* uid, uint8_t length) {
  Serial.print("UID detected: ");
  for (uint8_t i = 0; i < length; i++) {
    if (uid[i] < 0x10) Serial.print("0"); 
    Serial.print(uid[i], HEX);
    if (i < length - 1) Serial.print(":");
  }
  Serial.println();
}

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

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(50); 

  
  pinMode(LED_VERDE, OUTPUT);
  pinMode(LED_AZUL, OUTPUT);
  digitalWrite(LED_VERDE, LOW);
  digitalWrite(LED_AZUL, LOW);

  Wire.begin(21, 22); 

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
    while (1) {
      digitalWrite(LED_VERDE, HIGH); digitalWrite(LED_AZUL, HIGH); delay(200); 
      digitalWrite(LED_VERDE, LOW);  digitalWrite(LED_AZUL, LOW);  delay(200);
    } 
  }
  nfc.SAMConfig(); 
  
  delay(1500);
  refreshScreen(); 
}

void loop() {
    if (Serial.available()) {
        String command = Serial.readStringUntil('\n');
        command.trim();

        if (command == "LOAD_MED_1") {
          inventoryA++;
          Serial.println("ACK:LOAD_A_OK"); 
          refreshScreen();            
          sendMirthNotification("STOCK_RELOAD", "A", "MATLAB_SYS");     
        }
        else if (command == "LOAD_MED_2") {
          inventoryB++;
          Serial.println("ACK:LOAD_B_OK"); 
          refreshScreen(); 
          sendMirthNotification("STOCK_RELOAD", "B", "MATLAB_SYS");                
        }
    }

    if (millis() - chronometerCooldown >= PAUSE_CYCLE) {
        uint8_t uid[7] = {0}; 
        uint8_t uidLength = 0;   

        bool detected = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 60);

        if (detected) {
          Serial.println("RFID Card detected");
          printUID(uid, uidLength);

          String cardUidStr = "";
          for (uint8_t i = 0; i < uidLength; i++) {
            if (uid[i] < 0x10) cardUidStr += "0";
            cardUidStr += String(uid[i], HEX);
          }
          cardUidStr.toUpperCase();

          int idx = searchCard(uid, uidLength);

          if (idx >= 0) {
              uint8_t assignedServo = cardsAuthorized[idx].servo;
              
              if (assignedServo == 1 && inventoryA > 0) {
                Serial.println("ACCESS GRANTED → Dispensing A");
                dispense(assignedServo);
                inventoryA--; 
                refreshScreen(); 
                
                sendMirthNotification("DISPENSE_SUCCESS", "A", cardUidStr);
              }
              else if (assignedServo == 2 && inventoryB > 0) {
                Serial.println("ACCESS GRANTED → Dispensing B");
                dispense(assignedServo);
                inventoryB--; 
                refreshScreen(); 
                
                sendMirthNotification("DISPENSE_SUCCESS", "B", cardUidStr);
              } 
              else {
                // Intento de dispensación de compartimento vacío
                Serial.println("ACCESS DENIED - Out of Stock!");
                lcd.clear();
                lcd.setCursor(0,0); lcd.print("ACCESS DENIED!");
                lcd.setCursor(0,1); lcd.print("NO STOCK LEFT!");
                delay(1500);
                refreshScreen();
                
                String comp = (assignedServo == 1) ? "A" : "B";
                sendMirthNotification("ERROR_OUT_OF_STOCK", comp, cardUidStr);
              }
          } else {
            // Tarjeta ajena al sistema
            Serial.println("ACCESS DENIED - Card not registered.");
            lcd.clear();
            lcd.setCursor(0,0); lcd.print("ACCESS DENIED!");
            lcd.setCursor(0,1); lcd.print("UNKNOWN CARD!");
            delay(1500);
            refreshScreen();
            
            sendMirthNotification("ERROR_UNKNOWN_CARD", "NONE", cardUidStr);
          }
          chronometerCooldown = millis(); 
      }
    }
}

void refreshScreen() {
    if (inventoryA == 0) {
        digitalWrite(LED_VERDE, HIGH); 
    } else {
        digitalWrite(LED_VERDE, LOW);
    }

    if (inventoryB == 0) {
        digitalWrite(LED_AZUL, HIGH);  
    } else {
        digitalWrite(LED_AZUL, LOW);
    }

    lcd.clear();
    
    lcd.setCursor(0, 0);
    lcd.print("A: "); lcd.print(inventoryA); lcd.print(" pcs");
    
    lcd.setCursor(9, 0);
    lcd.print("B: "); lcd.print(inventoryB); lcd.print(" pcs");

    lcd.setCursor(0, 1);
    if (inventoryA == 0 && inventoryB == 0) {
        lcd.print("OUT OF STOCK ALL"); 
    }
    else if (inventoryA == 0) {
        lcd.print("EMPTY COMPART. A"); 
    }
    else if (inventoryB == 0) {
        lcd.print("EMPTY COMPART. B"); 
    }
    else if (inventoryA <= 2 || inventoryB <= 2) {
        lcd.print("LOW INVENTORY  "); 
    }
    else {
        lcd.print("SYSTEM OK       ");
    }

    Serial.print("STOCK_UPDATE:MED_A=");
    Serial.print(inventoryA);
    Serial.print(",MED_B=");
    Serial.println(inventoryB);
}