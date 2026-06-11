#include <Arduino.h>

#include <Wire.h>
#include <Adafruit_PN532.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>

// Hardware configuration
#define PN532_IRQ   2
#define PN532_RESET 4

#define SERVO1_PIN  25   
#define SERVO2_PIN  26   

const int yellowLed = 2;
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Configuration parameters
#define SERVO_REST     0     
#define SERVO_DISPENSE 180   
#define TIME_DISPENSE  1200  // ms open time
#define PAUSE_CYCLE    2000  // ms cooldown 

unsigned long chronometerCooldown = 0; 

// Local inventory control
int inventoryA = 0;
int inventoryB = 0;

// RFID patient structure
struct Card {
  uint8_t uid[7];   
  uint8_t length;   
  uint8_t servo;    
};

const uint8_t NUM_CARDS = 2; 
Card cardsAuthorized[NUM_CARDS] = {
  { {0x04, 0xAF, 0x6D, 0x02, 0xB8, 0x1B, 0x90}, 7, 1 }, // Card 1 - Compartment A
  { {0x04, 0x57, 0x57, 0x72, 0x8D, 0x20, 0x90}, 7, 2 }  // Card 2 - Compartment B
};

Adafruit_PN532 nfc(PN532_IRQ, PN532_RESET);
Servo servo1;
Servo servo2;

void refreshScreen();

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

  pinMode(yellowLed, OUTPUT);
  digitalWrite(yellowLed, LOW);

  Wire.begin(21, 22); 

  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System");
  lcd.setCursor(0, 1);
  lcd.print("Initialized");

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);
  servo1.write(SERVO_REST); 
  servo2.write(SERVO_REST);

  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("ERROR: PN532 not found.");
    while (1); 
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
        Serial.println("ACK:LOAD_A_OK"); // Immediate feedback to MATLAB
        refreshScreen();                 // Triggers full structural telemetry update
        }

        else if (command == "LOAD_MED_2") {
            inventoryB++;
            Serial.println("ACK:LOAD_B_OK"); // Immediate feedback to MATLAB
            refreshScreen();                 // Triggers full structural telemetry update
        }
    }

    if (millis() - chronometerCooldown >= PAUSE_CYCLE) {
        uint8_t uid[7] = {0}; 
        uint8_t uidLength = 0;   

        bool detected = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 60);

        if (detected) {
        Serial.println("--- RFID Card detected ---");
        printUID(uid, uidLength);

        int idx = searchCard(uid, uidLength);

        if (idx >= 0) {
            uint8_t assignedServo = cardsAuthorized[idx].servo;
            
            if (assignedServo == 1 && inventoryA > 0) {
            Serial.println("ACCESS GRANTED → Dispensing A");
            dispense(assignedServo);
            inventoryA--; 
            refreshScreen(); // Refreshes LCD and syncs telemetry live to MATLAB Dashboard
            }
            else if (assignedServo == 2 && inventoryB > 0) {
                Serial.println("ACCESS GRANTED → Dispensing B");
                dispense(assignedServo);
                inventoryB--; 
                refreshScreen(); // Refreshes LCD and syncs telemetry live to MATLAB Dashboard
            } 
            else {
                Serial.println("ACCESS DENIED - Out of Stock!");
                lcd.clear();
                lcd.setCursor(0,0); lcd.print("OUT OF STOCK!");
                delay(1500);
                refreshScreen();
            }
      } else {
        Serial.println("ACCESS DENIED - Card not registered.");
        }
        chronometerCooldown = millis(); 
    }
  }
}

// Alert Management and LCD Screen
void refreshScreen() {
    bool missingInventory = false;
    bool noInventory = false;

    if (inventoryA == 0 || inventoryB == 0) { noInventory = true; }
    else if (inventoryA <= 2 || inventoryB <= 2) { missingInventory = true; }

    if (inventoryA >= 10 && inventoryB >= 10) {
        digitalWrite(yellowLed, LOW);
    }
    else if (missingInventory || noInventory) {
        digitalWrite(yellowLed, HIGH);
    }
    else {
        digitalWrite(yellowLed, LOW); 
    }

    lcd.clear();

    if (noInventory) {
        lcd.setCursor(0, 0); lcd.print("OUT OF STOCK"); 
        lcd.setCursor(0, 1); lcd.print("REFILL SYSTEM");
    }
    else if (missingInventory) {
        lcd.setCursor(0, 0); lcd.print("LOW INVENTORY"); 
        lcd.setCursor(0, 1); lcd.print("CHECK STOCKS");
    }
    else {
        lcd.setCursor(0, 0); lcd.print("A:"); lcd.print(inventoryA);
        lcd.setCursor(8, 0); lcd.print("B:"); lcd.print(inventoryB);
        lcd.setCursor(0, 1); lcd.print("SYSTEM OK");
    }

    // CRITICAL INTEGRATION: Send structured telemetry directly into MATLAB's regex stream
    Serial.print("STOCK_UPDATE:MED_A=");
    Serial.print(inventoryA);
    Serial.print(",MED_B=");
    Serial.println(inventoryB);
}