/* =========================================================
   Node: MEGA HUB + TFT (Arduino Mega 2560)
   Purpose:
     - Listen to Soil packets
     - Decide Pump ON/OFF with hysteresis & timeouts
     - Send Pump command to Pump node
     - Display values/status on 3.5" MCUFRIEND TFT

   TFT (MCUFRIEND 8-bit parallel) wiring:
     D0–D7 -> D22–D29
     RS->D38, WR->D39, RD->D40, CS->D41, RST->D49, LED->5V via 100–220Ω
     VCC 5V, GND GND
   nRF24L01+ on Mega via 5V->3.3V adapter:
     CE D46, CSN D47, SCK 52, MOSI 51, MISO 50, VCC 5V, GND
     Decoupling on adapter 3.3V: 47–100 uF + 0.1 uF
   SPI-bus protection:
     D53=OUTPUT HIGH, D10=OUTPUT HIGH, D4=OUTPUT HIGH
   Logic:
     - Pump ON when soil ≤ 40%
     - Pump OFF when soil ≥ 55% OR pump-on time > 5 min
     - If no soil packets > 5 s => Pump OFF (failsafe)
   Serial: 115200 baud
   ========================================================= */

#include <SPI.h>
#include <RF24.h>
#include <Adafruit_GFX.h>
#include <MCUFRIEND_kbv.h>

// ---------- TFT ----------
MCUFRIEND_kbv tft;
uint16_t BLACK=0x0000, WHITE=0xFFFF, YELLOW=0xFFE0, CYAN=0x07FF, GREEN=0x07E0, RED=0xF800, GRAY=0x8410;

// ---------- RF ----------
RF24 radio(46, 47); // CE, CSN

const byte PIPE_SOIL_TO_MEGA[6] = "SOIL1";
const byte PIPE_MEGA_TO_PUMP[6] = "PUMP1";
const uint8_t RF_CHANNEL = 76;
const rf24_datarate_e RF_RATE = RF24_250KBPS;

struct SoilPacket {
  uint32_t seq;
  uint32_t t_ms;
  uint16_t raw;
  float    v;
  uint8_t  pct;
  float    tempC;
  float    hum;
};

struct PumpCmd {
  uint32_t seq;
  bool     pumpOn;
  uint8_t  lastSoilPct;
  uint8_t  reason;   // 0=LOGIC,1=FAILSAFE_NO_SOIL,2=TIMEOUT_5MIN,3=HYST_OFF
};

// ---------- thresholds & timers ----------
const uint8_t  ON_THRESH       = 40;         // <= turns ON
const uint8_t  OFF_THRESH      = 55;         // >= turns OFF
const uint32_t NO_SOIL_MS      = 5000;       // 5 s
const uint32_t PUMP_MAX_ON_MS  = 300000;     // 5 min

// NEW: cooldown to allow automatic retry after timeout
const uint32_t PUMP_COOLDOWN_MS = 60000;     // 1 min OFF, then try again if still dry

// ---------- state ----------
bool     pumpDesired     = false;
uint32_t pumpOnStartMs   = 0;
uint32_t pumpOffStartMs  = 0;    // NEW: remember when pump went OFF to time cooldown
uint32_t lastSoilRxMs    = 0;
uint32_t pumpCmdSeq      = 0;
uint8_t  lastSoilPct     = 0;
bool     timedOut5min    = false;
bool     soilSeen        = false;   // <<< ensures OFF until first packet

// ---------- UI ----------
int16_t W, H;

void spiBusProtection(){
  pinMode(53,OUTPUT); digitalWrite(53,HIGH); // keep master
  pinMode(10,OUTPUT); digitalWrite(10,HIGH); // release SD CS
  pinMode(4, OUTPUT); digitalWrite(4, HIGH); // release touch CS if present
}

void drawStaticUI(){
  tft.fillScreen(BLACK);
  tft.setRotation(1);
  W = tft.width(); H = tft.height();

  tft.setTextColor(WHITE, BLACK);
  tft.setTextSize(3);
  tft.setCursor(10, 10);
  tft.print("Smart Garden - MEGA");

  tft.drawRect(8, 50, W-16, H-60, GRAY);

  tft.setTextSize(2);
  tft.setCursor(20,  70); tft.print("Soil %:");
  tft.setCursor(20, 100); tft.print("Raw  :");
  tft.setCursor(20, 130); tft.print("Temp :");
  tft.setCursor(20, 160); tft.print("Hum  :");
  tft.setCursor(20, 190); tft.print("Age  :");
  tft.setCursor(20, 220); tft.print("Pump :");
  tft.setCursor(20, 250); tft.print("Reason:");

  tft.drawLine(10, 280, W-10, 280, GRAY);
  tft.setCursor(10, 290); tft.print("LOG: see Serial @115200");
}

void printField(int x,int y,const String& s,uint16_t color=YELLOW){
  tft.fillRect(x, y, W - x - 20, 20, BLACK);
  tft.setTextColor(color, BLACK);
  tft.setTextSize(2);
  tft.setCursor(x, y);
  tft.print(s);
}

void showStatus(uint8_t soilPct,uint16_t raw,float T,float Hh,uint32_t age_ms,bool pump,uint8_t reason){
  printField(130,  70, String(soilPct) + " %", CYAN);
  printField(130, 100, String(raw));
  printField(130, 130, isnan(T)  ? String("NA") : (String(T,1)  + " C"));
  printField(130, 160, isnan(Hh) ? String("NA") : (String(Hh,0) + " %"));
  printField(130, 190, String(age_ms/1000.0, 1) + " s");
  printField(130, 220, pump ? "ON" : "OFF", pump ? GREEN : RED);

  const char* r = "LOGIC";
  if (reason==1) r="FAILSAFE_NO_SOIL";
  else if (reason==2) r="TIMEOUT_5MIN";
  else if (reason==3) r="HYST_OFF";
  printField(130, 250, r, WHITE);
}

void setupTFT(){
  spiBusProtection();
  uint16_t ID = tft.readID();
  if (ID == 0xD3D3) ID = 0x9486; // common fallback
  tft.begin(ID);
  tft.setRotation(1);
  drawStaticUI();
  Serial.print(F("[MEGA] TFT ID=0x")); Serial.println(ID, HEX);
}

void setupRF(){
  if (!radio.begin()) {
    Serial.println(F("[MEGA] RF init FAILED"));
    return;
  }
  radio.setChannel(RF_CHANNEL);
  radio.setDataRate(RF_RATE);
  radio.setPALevel(RF24_PA_LOW);
  radio.setAutoAck(true);
  radio.setRetries(5, 15);
  radio.disableDynamicPayloads();

  radio.openReadingPipe(1, PIPE_SOIL_TO_MEGA);
  radio.startListening();

  Serial.println(radio.isChipConnected()
    ? F("[MEGA] RF listening SOIL; chip detected")
    : F("[MEGA] RF listening SOIL; chip NOT detected (wiring/power?)"));
}

void sendPump(bool on,uint8_t reason,uint8_t soilPctForCmd){
  PumpCmd cmd;
  cmd.seq = ++pumpCmdSeq;
  cmd.pumpOn = on;
  cmd.lastSoilPct = soilPctForCmd;
  cmd.reason = reason;

  radio.stopListening();
  radio.openWritingPipe(PIPE_MEGA_TO_PUMP);

  bool ok = radio.write(&cmd, sizeof(cmd));
  Serial.print(F("[MEGA] TX->PUMP seq=")); Serial.print(cmd.seq);
  Serial.print(F(" pump=")); Serial.print(on ? F("ON") : F("OFF"));
  Serial.print(F(" soil=")); Serial.print(soilPctForCmd);
  Serial.print(F(" reason=")); Serial.print(reason);
  Serial.print(F(" -> ")); Serial.println(ok ? F("OK") : F("FAIL"));

  radio.openReadingPipe(1, PIPE_SOIL_TO_MEGA);
  radio.startListening();
}

void setup(){
  Serial.begin(115200);
  delay(300);
  Serial.println(F("[MEGA] boot"));

  setupTFT();
  setupRF();

  pumpDesired = false;
  pumpOnStartMs = 0;
  pumpOffStartMs = 0; // NEW
  lastSoilRxMs = 0;
  timedOut5min = false;
  soilSeen = false;

  // Show "no soil yet" right away
  showStatus(0, 0, NAN, NAN, NO_SOIL_MS + 1, false, 1);
}

void loop(){
  static SoilPacket lastSoil = {0};
  const uint32_t now = millis();

  // --- Receive soil packets ---
  while (radio.available()) {
    SoilPacket s;
    radio.read(&s, sizeof(s));
    lastSoil = s;
    lastSoilRxMs = now;
    lastSoilPct = s.pct;
    soilSeen = true;

    Serial.print(F("[MEGA] SOIL seq=")); Serial.print(s.seq);
    Serial.print(F(" raw=")); Serial.print(s.raw);
    Serial.print(F(" pct=")); Serial.print(s.pct);
    Serial.print(F(" T=")); Serial.print(s.tempC);
    Serial.print(F("C H=")); Serial.print(s.hum);
    Serial.println(F("%"));
  }

  // --- Decide pump using hysteresis & timeouts ---
  uint8_t reason = 0;
  bool desired = pumpDesired;

  if (!soilSeen) {
    desired = false;        // keep OFF until first valid packet
    reason  = 1;            // FAILSAFE_NO_SOIL
    timedOut5min = false;
  }
  else if (now - lastSoilRxMs > NO_SOIL_MS) {
    desired = false;        // link lost -> OFF
    reason  = 1;
    timedOut5min = false;
  } else {
    // CHANGED/EXTENDED LOGIC BELOW
    if (pumpDesired) {
      // Currently ON
      if (lastSoil.pct >= OFF_THRESH) {
        desired = false; reason = 3;          // HYST_OFF
        timedOut5min = false;                 // clear latch if we actually reached the wet threshold
      } else if (!timedOut5min && (now - pumpOnStartMs > PUMP_MAX_ON_MS)) {
        desired = false; reason = 2;          // TIMEOUT_5MIN
        timedOut5min = true;                  // latch; we'll allow retry after cooldown below
      }
    } else {
      // Currently OFF
      if (timedOut5min) {
        // After timeout, wait cooldown then retry if still dry
        if ((now - pumpOffStartMs > PUMP_COOLDOWN_MS) && (lastSoil.pct <= ON_THRESH)) {
          desired = true; reason = 0;         // LOGIC ON
          timedOut5min = false;               // clear latch on retry
        }
      } else {
        // Normal ON hysteresis
        if (lastSoil.pct <= ON_THRESH) {
          desired = true; reason = 0;         // LOGIC ON
        }
        // If already wet enough, ensure latch is clear
        if (lastSoil.pct >= OFF_THRESH) {
          timedOut5min = false;
        }
      }
    }
  }

  // --- Send command if changed, otherwise keep-alive every 1 s ---
  if (desired != pumpDesired) {
    pumpDesired = desired;
    if (pumpDesired) {
      pumpOnStartMs = now;
    } else {
      pumpOffStartMs = now;           // NEW: start cooldown timing whenever we turn OFF
    }
    sendPump(pumpDesired, reason, lastSoilPct);
  } else {
    static uint32_t lastKeepAlive = 0;
    if (now - lastKeepAlive > 1000) {
      sendPump(pumpDesired, (!soilSeen || (now - lastSoilRxMs > NO_SOIL_MS)) ? 1
                    : (timedOut5min ? 2 : (pumpDesired ? 0 : (lastSoil.pct >= OFF_THRESH ? 3 : 0))),
               lastSoilPct);
      lastKeepAlive = now;
    }
  }

  // --- Update TFT ---
  uint32_t age = soilSeen ? (now - lastSoilRxMs) : (NO_SOIL_MS + 1);
  showStatus(soilSeen ? lastSoil.pct : 0,
             soilSeen ? lastSoil.raw : 0,
             soilSeen ? lastSoil.tempC : NAN,
             soilSeen ? lastSoil.hum : NAN,
             age, pumpDesired,
             (!soilSeen || age > NO_SOIL_MS) ? 1 : (timedOut5min ? 2 : (pumpDesired ? 0 : (lastSoil.pct >= OFF_THRESH ? 3 : 0))));
}
