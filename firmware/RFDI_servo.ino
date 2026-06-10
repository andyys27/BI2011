#include <Wire.h>
#include <Adafruit_PN532.h>
#include <ESP32Servo.h>

// RFID PN532 pins
#define PN532_IRQ   2
#define PN532_RESET 4

// Servo pins 
#define SERVO1_PIN  25   // Comparment 1 servo
#define SERVO2_PIN  26   // Servo del compartimento 2

// Servo positions (in degrees)
#define SERVO_REST     0     // Closed
#define SERVO_DISPENSE 180   // Open

// Time that the servo remains open to dispense
#define TIME_DISPENSE 1200  // ms CHECK LATER

// Pause between cycles
#define PAUSE_CICLE     2000  // ms

// Chronometer to prevent multiple reads
unsigned long chronometerCooldown = 0; 

struct Card {
  uint8_t uid[7];   // UID 
  uint8_t lenght;   // Real lenght of the UID
  uint8_t servo;    // Assigned servo (1 or 2)
};

const uint8_t NUM_CARDS = 2; 

Card cardsAuthorized[NUM_CARDS] = {
  { {0x4D, 0x07, 0x0D, 0x07}, 4, 1 },                   // Card 1 - servo 1
  { {0x04, 0x57, 0x57, 0x72, 0x8D, 0x20, 0x90}, 7, 2 }  // Card 2 - servo 2
};

Adafruit_PN532 nfc(PN532_IRQ, PN532_RESET);
Servo servo1;
Servo servo2;

// Print the detected UID in hexadecimal format via Serial
void printUID(uint8_t* uid, uint8_t length) {
  Serial.print("UID detected: ");
  for (uint8_t i = 0; i < length; i++) {
    if (uid[i] < 0x10) Serial.print("0"); 
    Serial.print(uid[i], HEX);
    if (i < length - 1) Serial.print(":");
  }
  Serial.println();
}

// Search for the UID in the list of authorized cards
int searchCard(uint8_t* uid, uint8_t length) {
  for (uint8_t i = 0; i < NUM_CARDS; i++) {
    if (length != cardsAuthorized[i].lenght) continue;

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

// Control the servo and dispense the pill
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

  Serial.println(">> Servo in rest position ");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println(" Pill Dispenser with RFID");

  // Begin servo control
  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);
  servo1.write(SERVO_REST); 
  servo2.write(SERVO_REST);
  Serial.println("Servos initialized and in rest position");

  // Begin PN532 module initialization
  Wire.begin(21, 22); // SDA=21, SCL=22
  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("ERROR: The PN532 module was not found.");
    Serial.println("Check the connections SDA/SCL/IRQ/RESET.");
    while (1); 
  }

  Serial.print("PN532 OK. Firmware v");
  Serial.println((versiondata >> 16) & 0xFF);

  nfc.SAMConfig(); 
  Serial.println("Ready. Bring and RFID Card close...\n");
}

void loop() {
  if (millis() - chronometerCooldown < PAUSE_CICLE) {
    return; 
  }

  uint8_t uid[7]    = {0}; // Buffer to store the detected UID 
  uint8_t uidLength = 0;   // Real length of the detected UID

  // Wait up to 500ms for a nearby card
  bool detected = nfc.readPassiveTargetID(
    PN532_MIFARE_ISO14443A, uid, &uidLength, 500
  );

  if (detected) {
    Serial.println(" RFID Card detected ");
    printUID(uid, uidLength);

    // Search for the card in the list of authorized cards
    int idx = searchCard(uid, uidLength);

if (idx >= 0) {
      uint8_t assignedServo = cardsAuthorized[idx].servo;
      Serial.print("ACCESS GRANTED → Servo ");
      Serial.println(assignedServo);
      dispense(assignedServo);
    } else {
      Serial.println("ACCESS DENIED - Card not registered.");
    }

    Serial.println();
       
    chronometerCooldown = millis();
  }
}