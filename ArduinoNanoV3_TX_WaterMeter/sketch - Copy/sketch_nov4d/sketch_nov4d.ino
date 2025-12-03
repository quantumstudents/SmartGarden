#include <SPI.h>
#include <RF24.h>

#define FLOW_PIN 2
#define CE_PIN   9
#define CSN_PIN 10

RF24 radio(CE_PIN, CSN_PIN);

const byte PIPE_WATER_TO_MEGA[6] = "H2M01";
const uint8_t RF_CHANNEL = 76;

struct __attribute__((packed)) FlowPkt {
  uint32_t ms;
  uint32_t total_mL;
  uint32_t seq;
  uint8_t  node_id;
};

volatile uint32_t pulses = 0;
volatile uint32_t lastPulseUs = 0;

void onPulse() {
  uint32_t now = micros();
  if (now - lastPulseUs > 800) { pulses++; lastPulseUs = now; }
}

void setup() {
  Serial.begin(115200);
  pinMode(FLOW_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), onPulse, FALLING);

  if (!radio.begin()) Serial.println(F("RF24 init failed"));
  radio.setChannel(RF_CHANNEL);
  radio.setDataRate(RF24_250KBPS);
  radio.setPALevel(RF24_PA_HIGH);

  // *** CHANGES: no-ACK transmit ***
  radio.setAutoAck(false);          // <— turn off ACK requirement (TX side only)
  radio.setRetries(0,0);            // <— no retries since no ACK
  radio.disableDynamicPayloads();   // match hub
  radio.setAddressWidth(5);
  radio.setCRCLength(RF24_CRC_16);

  radio.openWritingPipe(PIPE_WATER_TO_MEGA);
  radio.stopListening();

  Serial.println(F("Water Meter TX ready (no-ACK mode)"));
}

void loop() {
  static uint32_t seq = 0;
  static uint32_t lastSend = 0;
  uint32_t now = millis();
  if (now - lastSend < 1000) return;   // 1 Hz
  lastSend = now;

  const float ML_PER_PULSE = 2.0f;     // calibrate as needed
  uint32_t total_mL = (uint32_t)(pulses * ML_PER_PULSE + 0.5f);

  FlowPkt pkt{ now, total_mL, ++seq, 3 };

  bool ok = radio.write(&pkt, sizeof(pkt)); // will return 'true' without waiting for ACK
  Serial.print(F("TX total=")); Serial.print(pkt.total_mL);
  Serial.print(F(" mL, seq=")); Serial.print(pkt.seq);
  Serial.print(F(" -> ")); Serial.println(ok ? F("OK") : F("FAIL"));
}
