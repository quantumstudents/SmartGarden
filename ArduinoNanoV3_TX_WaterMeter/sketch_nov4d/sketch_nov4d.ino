// Nano V3 — Water SELF-TEST TX (H2M02), no-ACK, 32B static
#include <SPI.h>
#include <RF24.h>

#define CE_PIN  9
#define CSN_PIN 10
RF24 radio(CE_PIN, CSN_PIN);

const byte PIPE_WATER_TO_HUB[6] = "H2M02";

struct __attribute__((packed)) FlowPkt {
  uint32_t ms, total_mL, seq;
  uint8_t  node_id;
};

void setup(){
  Serial.begin(115200);
  if(!radio.begin()) Serial.println(F("RF init failed"));
  radio.setChannel(76);
  radio.setDataRate(RF24_250KBPS);
  radio.setPALevel(RF24_PA_HIGH);
  radio.setAutoAck(false);          // keep TX non-blocking
  radio.setRetries(0,0);
  radio.disableDynamicPayloads();
  radio.setAddressWidth(5);
  radio.setCRCLength(RF24_CRC_16);
  radio.setPayloadSize(32);
  radio.openWritingPipe(PIPE_WATER_TO_HUB);
  radio.stopListening();
  Serial.println(F("Water SELF-TEST TX ready (H2M02)"));
}

void loop(){
  static uint32_t seq=0, total=0, last=0;
  uint32_t now=millis();
  if(now - last < 1000) return;  // 1 Hz
  last = now;

  total += 100;                  // +100 mL each second (test)
  FlowPkt pkt{ now, total, ++seq, 3 };
  bool ok = radio.write(&pkt, sizeof(pkt));
  Serial.print(F("TEST TX total=")); Serial.print(pkt.total_mL);
  Serial.print(F(" seq=")); Serial.print(pkt.seq);
  Serial.print(F(" -> ")); Serial.println(ok ? F("OK") : F("FAIL"));
}
