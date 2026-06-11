#include <Wire.h>
#include <LiquidCrystal_I2C.h>

LiquidCrystal_I2C lcd(0x27, 16, 2);

const int yellowLed = 2;

// Inventory counts
int inventoryA = 0;
int inventoryB = 0;

void setup() {
  Serial.begin(115200);

  pinMode(yellowLed, OUTPUT);
  digitalWrite(yellowLed, LOW);

  lcd.init();
  lcd.backlight();

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System");
  lcd.setCursor(0, 1);
  lcd.print("Initialized");

  delay(2000);

  refreshScreen();
}

void loop() {

  if (Serial.available()) {

    String command = Serial.readStringUntil('\n');
    command.trim();

    if (command == "A") {

      inventoryA++;

      Serial.print("Inventory A: ");
      Serial.println(inventoryA);
    }

    else if (command == "B") {

      inventoryB++;

      Serial.print("Inventory B: ");
      Serial.println(inventoryB);
    }

    refreshScreen();
  }
}

void refreshScreen() {

  bool missingInventory = false;
  bool noInventory = false;

  // Verificar A
  if (inventoryA == 0) {
    noInventory = true;
  }
  else if (inventoryA <= 2) {
    missingInventory = true;
  }

  // Verificar B
  if (inventoryB == 0) {
    noInventory = true;
  }
  else if (inventoryB <= 2) {
    missingInventory = true;
  }

  // Control LED
  if (inventoryA >= 10 && inventoryB >= 10) {
    digitalWrite(yellowLed, LOW);
  }
  else if (missingInventory || noInventory) {
    digitalWrite(yellowLed, HIGH);
  }

  // LCD
  lcd.clear();

  if (noInventory) {
    lcd.setCursor(0, 0);
    lcd.print("NO INVENTORY");

    lcd.setCursor(0, 1);
    lcd.print("INVENTORY");
  }

  else if (missingInventory) {

    lcd.setCursor(0, 0);
    lcd.print("LOW INVENTORY");

    lcd.setCursor(0, 1);
    lcd.print("INVENTORY");
  }

  else {

    lcd.setCursor(0, 0);
    lcd.print("A:");
    lcd.print(inventoryA);

    lcd.setCursor(8, 0);
    lcd.print("B:");
    lcd.print(inventoryB);

    lcd.setCursor(0, 1);
    lcd.print("SYSTEM OK");
  }
}
