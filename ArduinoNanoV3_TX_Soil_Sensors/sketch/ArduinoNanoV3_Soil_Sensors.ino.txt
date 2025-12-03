/* =========================================================
   Node: SOIL TX (Arduino Nano V3)
   Purpose: Read soil moisture (A0), DHT11 (D2), send to Mega via nRF24L01+
   nRF24L01+ (through 5V->3.3V adapter):
     CE  D9, CSN D10, SCK D13, MOSI D11, MISO D12, VCC 5V (adapter), GND
     Decoupling on adapter 3.3V: 47–100 uF + 0.1 uF
   Sensors:
     Capacitive Soil Moisture v1.2 -> A0 (analog)
     DHT11 -> D2
   Serial: 115200 baud
   ========================================================= */

#include <SPI.h>
#include <RF24.h>
#include <DHT.h>

#define DHTPIN 2
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

// RF
RF24 radio(9, 10);               // CE, CSN
const byte PIPE_SOIL_TO_MEGA[6] = "SOIL1";
const uint8_t RF_CHANNEL = 76;
const rf24_datarate_e RF_RATE = RF24_250KBPS;



// SoilTx_Nano.ino — set these near the top
//const int SOIL_WET_ADC = 360;   // ~100% (probe in water / very wet soil)
//const int SOIL_DRY_ADC = 780;   // ~0%   (probe in air)




// Soil calibration (tune!)
const int SOIL_WET_ADC = 215;    // ADC ≈ 100% (very wet) - adjust ~100% (probe in water / very wet soil)
const int SOIL_DRY_ADC = 484;    // ADC ≈   0% (very dry) - adjust








struct SoilPacket {
  uint32_t seq;
  uint32_t t_ms;
  uint16_t raw;     // analogRead(A0)
  float    v;       // optional (unused here)
  uint8_t  pct;     // 0..100
  float    tempC;   // DHT11
  float    hum;     // DHT11
};

uint32_t seq = 0;
uint32_t lastSendMs = 0;
const uint32_t SEND_PERIOD_MS = 1000; // 1 Hz

uint8_t clampPctFromADC(int adc) {
  int pct = map(adc, SOIL_DRY_ADC, SOIL_WET_ADC, 0, 100);
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return (uint8_t)pct;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("[SOIL] boot"));

  dht.begin();

  if (!radio.begin()) {
    Serial.println(F("[SOIL] RF init FAILED"));
  } else {
    radio.setChannel(RF_CHANNEL);
    radio.setDataRate(RF_RATE);
    radio.setPALevel(RF24_PA_LOW);
    radio.setAutoAck(true);
    radio.setRetries(5, 15); // delay,count
    radio.disableDynamicPayloads();     // fixed payload
    radio.openWritingPipe(PIPE_SOIL_TO_MEGA);
    radio.stopListening();

    Serial.println(radio.isChipConnected()
      ? F("[SOIL] RF init OK; chip detected")
      : F("[SOIL] RF init OK; chip NOT detected (wiring/power?)"));
  }

  pinMode(A0, INPUT);
}

void loop() {
  const uint32_t now = millis();
  if (now - lastSendMs < SEND_PERIOD_MS) return;
  lastSendMs = now;

  int raw = analogRead(A0);
  uint8_t pct = clampPctFromADC(raw);

  float h = dht.readHumidity();
  float t = dht.readTemperature(); // °C
  if (isnan(h) || isnan(t)) {
    h = -1.0f; t = -100.0f; // mark invalid
  }

  SoilPacket pkt;
  pkt.seq   = ++seq;
  pkt.t_ms  = now;
  pkt.raw   = (uint16_t)raw;
  pkt.v     = 0.0f;
  pkt.pct   = pct;
  pkt.tempC = t;
  pkt.hum   = h;

  bool ok = radio.write(&pkt, sizeof(pkt));

  Serial.print(F("[SOIL] send seq=")); Serial.print(pkt.seq);
  Serial.print(F(" raw=")); Serial.print(pkt.raw);
  Serial.print(F(" pct=")); Serial.print(pkt.pct);
  Serial.print(F(" T=")); Serial.print(pkt.tempC);
  Serial.print(F("C H=")); Serial.print(pkt.hum);
  Serial.print(F("% -> ")); Serial.println(ok ? F("OK") : F("FAIL"));
}
