/* =========================================================
   Node: PUMP RX (Arduino Nano V3)
   Purpose: Receive pump command from Mega and drive relay (D3)
   nRF24L01+ via adapter:
     CE D9, CSN D10, SCK D13, MOSI D11, MISO D12, VCC 5V, GND
     Decoupling on adapter 3.3V: 47–100uF + 0.1uF
   Relay/SSR:
     IN D3 (HIGH = ON), VCC 5V, GND common
   Failsafe: If no command > 5 s -> Pump OFF
   Serial: 115200 baud
   ========================================================= */

#include <SPI.h>
#include <RF24.h>

RF24 radio(9, 10); // CE, CSN

const byte PIPE_MEGA_TO_PUMP[6] = "PUMP1";
const uint8_t RF_CHANNEL = 76;
const rf24_datarate_e RF_RATE = RF24_250KBPS;

struct PumpCmd {
  uint32_t seq;
  bool     pumpOn;
  uint8_t  lastSoilPct;
  uint8_t  reason;   // 0=LOGIC,1=FAILSAFE_NO_SOIL,2=TIMEOUT_5MIN,3=HYST_OFF
};

const uint8_t PIN_RELAY = 3;

uint32_t lastCmdMs = 0;
const uint32_t CMD_TIMEOUT_MS = 5000; // 5 s
bool currentPump = false;

void applyPump(bool on, const char* src) {
  currentPump = on;
  digitalWrite(PIN_RELAY, on ? HIGH : LOW);
  Serial.print(F("[PUMP] ")); Serial.print(src);
  Serial.print(F(" -> pump=")); Serial.println(on ? F("ON") : F("OFF"));
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("[PUMP] boot"));

  pinMode(PIN_RELAY, OUTPUT);
  applyPump(false, "INIT");

  if (!radio.begin()) {
    Serial.println(F("[PUMP] RF init FAILED"));
  } else {
    radio.setChannel(RF_CHANNEL);
    radio.setDataRate(RF_RATE);
    radio.setPALevel(RF24_PA_LOW);
    radio.setAutoAck(true);
    radio.setRetries(5, 15);
    radio.disableDynamicPayloads();
    radio.openReadingPipe(1, PIPE_MEGA_TO_PUMP);
    radio.startListening();

    Serial.println(radio.isChipConnected()
      ? F("[PUMP] RF init OK; chip detected, listening")
      : F("[PUMP] RF init OK; chip NOT detected (wiring/power?)"));
  }
}

void loop() {
  // Incoming commands
  while (radio.available()) {
    PumpCmd cmd;
    radio.read(&cmd, sizeof(cmd));
    lastCmdMs = millis();
    applyPump(cmd.pumpOn, "CMD");
    Serial.print(F("[PUMP] seq=")); Serial.print(cmd.seq);
    Serial.print(F(" soilPct=")); Serial.print(cmd.lastSoilPct);
    Serial.print(F(" reason=")); Serial.println(cmd.reason);
  }

  // Failsafe: OFF if no command for >5 s
  uint32_t now = millis();
  if (now - lastCmdMs > CMD_TIMEOUT_MS) {
    if (currentPump) {
      applyPump(false, "FAILSAFE_NO_CMD");
    }
  }
}
