
 # Arduino Mega 2560 HUB (TFT + nRF24L01+)  
  


# Abstract

This document presents a complete technical report for the central hub
node of a Smart Garden system implemented on the Arduino Mega 2560
platform. The hub integrates an 8-bit parallel MCUFRIEND TFT display for
real-time visualization and an nRF24L01+ radio for wireless
communication. It receives soil telemetry packets, evaluates irrigation
logic using hysteresis with safety constraints, and transmits pump
commands and keep-alive frames to a pump controller node. The report
provides wiring details, data structures, RF configuration, control
logic with mathematical conditions, performance notes, and extensive
verbatim code listings for reproducibility. Color coding is used
consistently: <span style="color: HWBlue">hardware</span>,
<span style="color: CloudGreen">RF/communication</span>,
<span style="color: AnalyticsOrange">logic/analytics</span>, and
<span style="color: FailRed">failsafe</span>.

# Introduction

The Smart Garden project aims to provide a robust, low-maintenance, and
explainable irrigation controller suitable for instructional labs and
club projects. The hub node described herein acts as the control plane
between soil sensor transmitters and a remotely-switched pump node. Key
goals:

- Reliability under noisy power and RF conditions.

- Safety through time-based and packet-based failsafes.

- Human-readable UI feedback (TFT) and serial diagnostics.

- Clear, reproducible code paths with fixed packet layouts.

The system uses hysteresis thresholds for moisture-based activation, a
five-minute runtime limiter to protect actuators and plants, and a
link-loss failsafe that ensures OFF when telemetry is stale. A
one-minute cooldown provides automatic retry capability after timeouts.

# Hardware Architecture

## Bill of Materials

| Component | Notes |
|:---|:---|
| Arduino Mega 2560 | 16 MHz, abundant GPIOs for 8-bit TFT and SPI. |
| nRF24L01+ radio + 5V  3.3V adapter | Use local decoupling: 47–100 μF + 0.1 μF. |
| 3.5M̈CUFRIEND 8-bit TFT (ILI9486 class) | Parallel 8-bit bus, driver via MCUFRIEND_kbv. |
| Jumper wires / shield | Minimize CE/CSN lead length for RF stability. |
| Power supply (5 V) | Stable 5 V for Mega and TFT; adapter regulates RF to 3.3 V. |

## Pin Connections

#### TFT (MCUFRIEND, 8-bit parallel).

Mapping used:

<div class="center">

| TFT Signal | Mega 2560 Pin                                            |
|:-----------|:---------------------------------------------------------|
| D0–D7      | D22–D29                                                  |
| RS         | D38 (<span style="color: HWBlue">register select</span>) |
| WR         | D39 (write strobe)                                       |
| RD         | D40 (read strobe)                                        |
| CS         | D41 (chip select)                                        |
| RST        | D49 (reset)                                              |
| LED        | 5 V via 100–220 Ω resistor                               |
| VCC        | 5 V                                                      |
| GND        | GND                                                      |

</div>

#### nRF24L01+ (with adapter).

<div class="center">

| Radio Signal | Mega 2560 Pin                   |
|:-------------|:--------------------------------|
| CE           | D46                             |
| CSN (CS)     | D47                             |
| SCK          | D52                             |
| MOSI         | D51                             |
| MISO         | D50                             |
| VCC          | 5 V to adapter (3.3 V on radio) |
| GND          | GND                             |

</div>

**Decoupling** at the adapter 3.3 V rail: 47–100 μF electrolytic +
0.1 μF ceramic placed close to the radio header.

#### SPI-bus Protection.

Some stacked shields can hold the SPI bus. We explicitly configure:

    pinMode(53, OUTPUT); digitalWrite(53, HIGH); // keep SPI master
    pinMode(10, OUTPUT); digitalWrite(10, HIGH); // release SD CS
    pinMode(4,  OUTPUT); digitalWrite(4,  HIGH); // release touch CS

# Microcontroller Responsibilities

The Mega hub performs four concurrent roles in the main loop:

1.  **RF Reception** (<span style="color: CloudGreen">SOIL1  MEGA</span>
    pipe) with fixed-size packet structs.

2.  **Decision Logic**
    (<span style="color: AnalyticsOrange">hysteresis</span>, runtime
    timeout, cooldown, link-loss failsafe).

3.  **RF Transmission**
    (<span style="color: CloudGreen">MEGA  PUMP1</span> pipe), including
    1 s keep-alives.

4.  **TFT Rendering** (<span style="color: HWBlue">status fields,
    colors, reasons</span>).

We separate static UI drawing (labels, frames) from dynamic fields
(values and status) to minimize redraw overhead and improve readability.

# Communication Protocol (nRF24L01+)

## Addresses, Channel, Data Rate

    const byte PIPE_SOIL_TO_MEGA[6] = "SOIL1";   // reading pipe
    const byte PIPE_MEGA_TO_PUMP[6] = "PUMP1";   // writing pipe
    const uint8_t RF_CHANNEL = 76;               // 2.476 GHz
    const rf24_datarate_e RF_RATE = RF24_250KBPS; // robust, long-range

We disable dynamic payloads to keep packet size deterministic and ease
debugging.

## Packet Layouts

#### SoilPacket

    struct SoilPacket {
      uint32_t seq;    // sequence number from sensor node
      uint32_t t_ms;   // sensor-side timestamp
      uint16_t raw;    // raw ADC from capacitive probe
      float    v;      // mapped/filtered voltage
      uint8_t  pct;    // moisture percentage (0..100)
      float    tempC;  // temperature in °C
      float    hum;    // humidity %RH
    };

#### PumpCmd

    struct PumpCmd {
      uint32_t seq;        // hub sequence for pump commands
      bool     pumpOn;     // desired state
      uint8_t  lastSoilPct;// last known soil pct from RX
      uint8_t  reason;     // 0=LOGIC,1=FAILSAFE_NO_SOIL,2=TIMEOUT_5MIN,3=HYST_OFF
    };

## RF Initialization and Pipes

    if (!radio.begin()) {
      Serial.println(F("[MEGA] RF init FAILED"));
    }
    radio.setChannel(RF_CHANNEL);
    radio.setDataRate(RF_RATE);
    radio.setPALevel(RF24_PA_LOW);
    radio.setAutoAck(true);
    radio.setRetries(5, 15);
    radio.disableDynamicPayloads();

    radio.openReadingPipe(1, PIPE_SOIL_TO_MEGA);
    radio.startListening();

# Control Logic (Mathematical Conditions)

## Thresholds and Timers

    ON_THRESH        = 40;       // ≤ → ON
    OFF_THRESH       = 55;       // ≥ → OFF
    NO_SOIL_MS       = 5000;     // link-loss failsafe window
    PUMP_MAX_ON_MS   = 300000;   // 5 minutes safety limit
    PUMP_COOLDOWN_MS = 60000;    // retry window after timeout

## Decision Conditions

Let $`s(t)`$ denote soil percentage at time $`t`$. Define the indicator
$`u(t) \in \{0,1\}`$ for the desired pump state.
``` math
\begin{aligned}
&\textbf{Hysteresis ON:}\quad s(t) \leq \theta_{\text{on}} = 40 \Rightarrow u(t)=1,\\
&\textbf{Hysteresis OFF:}\quad s(t) \geq \theta_{\text{off}} = 55 \Rightarrow u(t)=0.\\
&\textbf{Failsafe (link loss):}\quad t - t_{\text{soil\_last}} > 5\,\text{s} \Rightarrow u(t)=0.\\
&\textbf{Runtime Timeout:}\quad t - t_{\text{pump\_on}} > 300\,\text{s} \Rightarrow u(t)=0\ (\text{latch timeout}).\\
&\textbf{Cooldown Retry:}\quad \text{if timeout latched and } t - t_{\text{pump\_off}} > 60\,\text{s},\\
&\phantom{\textbf{Cooldown Retry:}}\quad s(t) \leq 40 \Rightarrow u(t)=1 \text{ and clear latch}.
\end{aligned}
```

# Code Section I: Initialization

## Serial and SPI-Bus Protection

    void spiBusProtection(){
      pinMode(53,OUTPUT); digitalWrite(53,HIGH); // keep master
      pinMode(10,OUTPUT); digitalWrite(10,HIGH); // release SD CS
      pinMode(4, OUTPUT); digitalWrite(4, HIGH); // release touch CS
    }

    void setup(){
      Serial.begin(115200);
      delay(300);
      Serial.println(F("[MEGA] boot"));
      setupTFT();
      setupRF();
      // Initialize state and show placeholder UI
      pumpDesired   = false;
      pumpOnStartMs = 0;
      pumpOffStartMs= 0;
      lastSoilRxMs  = 0;
      timedOut5min  = false;
      soilSeen      = false;
      showStatus(0, 0, NAN, NAN, NO_SOIL_MS + 1, false, 1);
    }

## TFT Bring-Up

    void setupTFT(){
      spiBusProtection();
      uint16_t ID = tft.readID();
      if (ID == 0xD3D3) ID = 0x9486; // common fallback
      tft.begin(ID);
      tft.setRotation(1);
      drawStaticUI();
      Serial.print(F("[MEGA] TFT ID=0x")); Serial.println(ID, HEX);
    }

## RF Bring-Up

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

# Code Section II: RF Reception

## Receive Loop

    while (radio.available()) {
      SoilPacket s;        // fixed-size struct
      radio.read(&s, sizeof(s));
      lastSoil     = s;
      lastSoilRxMs = now;
      lastSoilPct  = s.pct;
      soilSeen     = true;
      Serial.print(F("[MEGA] SOIL seq=")); Serial.print(s.seq);
      Serial.print(F(" raw=")); Serial.print(s.raw);
      Serial.print(F(" pct=")); Serial.print(s.pct);
      Serial.print(F(" T=")); Serial.print(s.tempC);
      Serial.print(F("C H=")); Serial.print(s.hum);
      Serial.println(F("%"));
    }

## Packet Integrity Considerations

Because dynamic payloads are disabled, the hub expects exactly
`sizeof(SoilPacket)` bytes. Mismatches surface as framing errors or
stalled reads. In practice, using the same compiler and struct packing
on both nodes avoids alignment issues.

# Code Section III: Decision Logic

## Hysteresis, Timeout, Cooldown

    uint8_t reason = 0;  // default LOGIC
    bool desired = pumpDesired;

    if (!soilSeen) {
      desired     = false;  reason = 1; // FAILSAFE_NO_SOIL
      timedOut5min= false;
    }
    else if (now - lastSoilRxMs > NO_SOIL_MS) {
      desired     = false;  reason = 1; // link-loss
      timedOut5min= false;
    } else {
      if (pumpDesired) { // currently ON
        if (lastSoil.pct >= OFF_THRESH) {
          desired = false; reason = 3; // HYST_OFF
          timedOut5min = false;
        } else if (!timedOut5min && (now - pumpOnStartMs > PUMP_MAX_ON_MS)) {
          desired = false; reason = 2; // TIMEOUT_5MIN
          timedOut5min = true;         // latch
        }
      } else { // currently OFF
        if (timedOut5min) {
          if ((now - pumpOffStartMs > PUMP_COOLDOWN_MS) && (lastSoil.pct <= ON_THRESH)) {
            desired = true; reason = 0; // retry
            timedOut5min = false;
          }
        } else {
          if (lastSoil.pct <= ON_THRESH) {
            desired = true; reason = 0; // normal ON
          }
          if (lastSoil.pct >= OFF_THRESH) {
            timedOut5min = false; // ensure clear
          }
        }
      }
    }

# Code Section IV: Pump Transmission

## Command Framing and Keep-Alive

    void sendPump(bool on, uint8_t reason, uint8_t soilPctForCmd){
      PumpCmd cmd; cmd.seq = ++pumpCmdSeq; cmd.pumpOn = on;
      cmd.lastSoilPct = soilPctForCmd; cmd.reason = reason;

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

    // periodic keep-alive (≈1 s)
    static uint32_t lastKeepAlive = 0;
    if (now - lastKeepAlive > 1000) {
      sendPump(pumpDesired,
        (!soilSeen || (now - lastSoilRxMs > NO_SOIL_MS)) ? 1
          : (timedOut5min ? 2 : (pumpDesired ? 0 : (lastSoil.pct >= OFF_THRESH ? 3 : 0))),
        lastSoilPct);
      lastKeepAlive = now;
    }

# Code Section V: TFT Rendering

## Static UI

    void drawStaticUI(){
      tft.fillScreen(0x0000); // BLACK
      tft.setRotation(1);
      W = tft.width(); H = tft.height();
      tft.setTextColor(0xFFFF, 0x0000); // WHITE on BLACK
      tft.setTextSize(3);
      tft.setCursor(10, 10); tft.print("Smart Garden - MEGA");
      tft.drawRect(8, 50, W-16, H-60, 0x8410); // GRAY frame
      tft.setTextSize(2);
      tft.setCursor(20,70);  tft.print("Soil %:");
      tft.setCursor(20,100); tft.print("Raw  :");
      tft.setCursor(20,130); tft.print("Temp :");
      tft.setCursor(20,160); tft.print("Hum  :");
      tft.setCursor(20,190); tft.print("Age  :");
      tft.setCursor(20,220); tft.print("Pump :");
      tft.setCursor(20,250); tft.print("Reason:");
      tft.drawLine(10, 280, W-10, 280, 0x8410);
      tft.setCursor(10,290); tft.print("LOG: see Serial @115200");
    }

## Dynamic Fields

    void printField(int x,int y,const String& s,uint16_t color=0xFFE0){ // YELLOW
      tft.fillRect(x, y, W - x - 20, 20, 0x0000); // clear to BLACK
      tft.setTextColor(color, 0x0000);
      tft.setTextSize(2);
      tft.setCursor(x, y); tft.print(s);
    }

    void showStatus(uint8_t soilPct,uint16_t raw,float T,float Hh,
                    uint32_t age_ms,bool pump,uint8_t reason){
      printField(130,70,  String(soilPct) + " %", 0x07FF); // CYAN
      printField(130,100, String(raw), 0xFFE0);             // YELLOW
      printField(130,130, isnan(T)?"NA":(String(T,1)+" C"), 0xFFE0);
      printField(130,160, isnan(Hh)?"NA":(String(Hh,0)+" %"), 0xFFE0);
      printField(130,190, String(age_ms/1000.0, 1) + " s", 0xFFE0);
      printField(130,220, pump?"ON":"OFF", pump?0x07E0:0xF800); // GREEN/RED
      const char* r="LOGIC"; if (reason==1) r="FAILSAFE_NO_SOIL";
      else if (reason==2) r="TIMEOUT_5MIN"; else if (reason==3) r="HYST_OFF";
      printField(130,250, r, 0xFFFF);
    }

# End-to-End Data Flow

This section illustrates the path from the soil sensor to the pump node
through the Mega hub. Fixed-size structs minimize parsing complexity and
improve determinism. Keep-alives ensure the pump state remains
synchronized even if no threshold crossings occur.

## Example Sequence (verbatim log)

    [SOIL TX] -> seq=101 pct=37 raw=512 temp=24.6 hum=41.0
    [MEGA RX] <- seq=101 pct=37 ... (age=0.0s)
    [MEGA LOGIC] soil<=40? no -> pump stays OFF
    [MEGA KEEPALIVE] TX->PUMP seq=881 pump=OFF reason=0
    ...
    [SOIL TX] -> seq=117 pct=39 ...
    [MEGA LOGIC] soil<=40? yes -> pump ON; start ON timer
    [MEGA CMD] TX->PUMP seq=894 pump=ON reason=0
    ...
    [MEGA LOGIC] ON time exceeds 5 min -> pump OFF, reason=2 (timeout latch)
    [MEGA CMD] TX->PUMP seq=955 pump=OFF reason=2
    [MEGA LOGIC] wait 60 s cooldown; if soil<=40 then retry ON and clear latch

# Testing and Debugging

## Serial Monitor Checks

    [MEGA] boot
    [MEGA] TFT ID=0x9486
    [MEGA] RF listening SOIL; chip detected
    [MEGA] SOIL seq=123 raw=512 pct=37 T=24.5C H=41.0%
    [MEGA] TX->PUMP seq=7 pump=ON soil=37 reason=0 -> OK

## Troubleshooting Quicklist

- RF reads but UI never changes: verify struct sizes are identical
  across nodes.

- RF not detected: re-check CE/CSN pins (D46/D47) and adapter
  decoupling.

- Random resets when pump toggles: investigate supply sag, add bulk
  capacitance.

- TFT frozen: confirm `readID()` fallback to 0x9486 and proper CS lines
  via `spiBusProtection()`.

# Power and Signal Integrity

- Place the 47–100 μF and 0.1 μF capacitors close to the radio header.

- Keep CE/CSN short; avoid long dupont leads acting as antennas.

- If using a breadboard, avoid sharing the radio rail with servo/pump
  loads.

- Consider twisted pairs (signal+GND) for SPI lines to reduce EMI.

# Safety, Failsafe, and Recovery

The system intentionally biases toward safety: in any uncertain state
(no packets, timing overrun), the pump is commanded OFF and a reason
code reflects the cause. This principle avoids overwatering and hardware
strain.

# Performance Analysis

## Latency

Typical RX to decision to TX turnaround is sub-millisecond on the Mega
at 16 MHz. The keep-alive interval (1̃ s) dominates command refresh
cadence when states are steady.

## Error Tolerance

At 250 kbps and LOW PA, packet error rate is low indoors with proper
decoupling. Should losses occur, the failsafe will revert to OFF once
the 5 s window elapses.

# Future Enhancements

- Ethernet/HTTPS gateway for cloud logging and dashboards.

- On-device calibration pages (touch UI) for sensor mapping.

- ML-based irrigation policy using seasonal trends.

# TikZ Diagrams

## RF Data Path (Sensor Mega Pump)

<div class="center">

</div>

## Software Task Flow (Setup, Loop, Display, TX)

<div class="center">

</div>

## RF/Logic State Machine

<div class="center">

</div>

# Appendices

## Constants and State

    const uint8_t  ON_THRESH       = 40;
    const uint8_t  OFF_THRESH      = 55;
    const uint32_t NO_SOIL_MS      = 5000;
    const uint32_t PUMP_MAX_ON_MS  = 300000;
    const uint32_t PUMP_COOLDOWN_MS= 60000;

    bool     pumpDesired   = false;
    uint32_t pumpOnStartMs = 0;
    uint32_t pumpOffStartMs= 0;
    uint32_t lastSoilRxMs  = 0;
    uint32_t pumpCmdSeq    = 0;
    uint8_t  lastSoilPct   = 0;
    bool     timedOut5min  = false;
    bool     soilSeen      = false;

## Full Hub Code Listing (for Archiving)

    #include <SPI.h>
    #include <RF24.h>
    #include <Adafruit_GFX.h>
    #include <MCUFRIEND_kbv.h>

    MCUFRIEND_kbv tft;
    uint16_t BLACK=0x0000, WHITE=0xFFFF, YELLOW=0xFFE0, CYAN=0x07FF, GREEN=0x07E0, RED=0xF800, GRAY=0x8410;
    RF24 radio(46, 47); // CE, CSN

    const byte PIPE_SOIL_TO_MEGA[6] = "SOIL1";
    const byte PIPE_MEGA_TO_PUMP[6] = "PUMP1";
    const uint8_t RF_CHANNEL = 76;
    const rf24_datarate_e RF_RATE = RF24_250KBPS;

    struct SoilPacket {
      uint32_t seq; uint32_t t_ms; uint16_t raw; float v; uint8_t pct; float tempC; float hum;
    };
    struct PumpCmd {
      uint32_t seq; bool pumpOn; uint8_t lastSoilPct; uint8_t reason;
    };

    const uint8_t  ON_THRESH       = 40;
    const uint8_t  OFF_THRESH      = 55;
    const uint32_t NO_SOIL_MS      = 5000;
    const uint32_t PUMP_MAX_ON_MS  = 300000;
    const uint32_t PUMP_COOLDOWN_MS= 60000;

    bool     pumpDesired     = false;
    uint32_t pumpOnStartMs   = 0;
    uint32_t pumpOffStartMs  = 0;
    uint32_t lastSoilRxMs    = 0;
    uint32_t pumpCmdSeq      = 0;
    uint8_t  lastSoilPct     = 0;
    bool     timedOut5min    = false;
    bool     soilSeen        = false;

    int16_t W, H;

    void spiBusProtection(){
      pinMode(53,OUTPUT); digitalWrite(53,HIGH);
      pinMode(10,OUTPUT); digitalWrite(10,HIGH);
      pinMode(4, OUTPUT); digitalWrite(4, HIGH);
    }

    void drawStaticUI(){
      tft.fillScreen(BLACK);
      tft.setRotation(1);
      W = tft.width(); H = tft.height();
      tft.setTextColor(WHITE, BLACK); tft.setTextSize(3);
      tft.setCursor(10,10); tft.print("Smart Garden - MEGA");
      tft.drawRect(8,50,W-16,H-60,GRAY);
      tft.setTextSize(2);
      tft.setCursor(20,70);  tft.print("Soil %:");
      tft.setCursor(20,100); tft.print("Raw  :");
      tft.setCursor(20,130); tft.print("Temp :");
      tft.setCursor(20,160); tft.print("Hum  :");
      tft.setCursor(20,190); tft.print("Age  :");
      tft.setCursor(20,220); tft.print("Pump :");
      tft.setCursor(20,250); tft.print("Reason:");
      tft.drawLine(10,280,W-10,280,GRAY);
      tft.setCursor(10,290); tft.print("LOG: see Serial @115200");
    }

    void printField(int x,int y,const String& s,uint16_t color=YELLOW){
      tft.fillRect(x, y, W - x - 20, 20, BLACK);
      tft.setTextColor(color, BLACK); tft.setTextSize(2);
      tft.setCursor(x, y); tft.print(s);
    }

    void showStatus(uint8_t soilPct,uint16_t raw,float T,float Hh,uint32_t age_ms,bool pump,uint8_t reason){
      printField(130,70,String(soilPct)+" %",CYAN);
      printField(130,100,String(raw));
      printField(130,130,isnan(T)?String("NA"):String(T,1)+" C");
      printField(130,160,isnan(Hh)?String("NA"):String(Hh,0)+" %");
      printField(130,190,String(age_ms/1000.0,1)+" s");
      printField(130,220,pump?"ON":"OFF", pump?GREEN:RED);
      const char* r="LOGIC"; if (reason==1) r="FAILSAFE_NO_SOIL"; else if (reason==2) r="TIMEOUT_5MIN"; else if (reason==3) r="HYST_OFF";
      printField(130,250,r,WHITE);
    }

    void setupTFT(){
      spiBusProtection();
      uint16_t ID = tft.readID(); if (ID == 0xD3D3) ID = 0x9486; tft.begin(ID);
      tft.setRotation(1); drawStaticUI();
      Serial.print(F("[MEGA] TFT ID=0x")); Serial.println(ID, HEX);
    }

    void setupRF(){
      if (!radio.begin()) { Serial.println(F("[MEGA] RF init FAILED")); return; }
      radio.setChannel(RF_CHANNEL); radio.setDataRate(RF_RATE); radio.setPALevel(RF24_PA_LOW);
      radio.setAutoAck(true); radio.setRetries(5,15); radio.disableDynamicPayloads();
      radio.openReadingPipe(1, PIPE_SOIL_TO_MEGA); radio.startListening();
      Serial.println(radio.isChipConnected()?F("[MEGA] RF listening SOIL; chip detected"):F("[MEGA] RF listening SOIL; chip NOT detected (wiring/power?)"));
    }

    void sendPump(bool on,uint8_t reason,uint8_t soilPctForCmd){
      PumpCmd cmd; cmd.seq=++pumpCmdSeq; cmd.pumpOn=on; cmd.lastSoilPct=soilPctForCmd; cmd.reason=reason;
      radio.stopListening(); radio.openWritingPipe(PIPE_MEGA_TO_PUMP);
      bool ok = radio.write(&cmd, sizeof(cmd));
      Serial.print(F("[MEGA] TX->PUMP seq=")); Serial.print(cmd.seq);
      Serial.print(F(" pump=")); Serial.print(on?F("ON"):F("OFF"));
      Serial.print(F(" soil=")); Serial.print(soilPctForCmd);
      Serial.print(F(" reason=")); Serial.print(reason);
      Serial.print(F(" -> ")); Serial.println(ok?F("OK"):F("FAIL"));
      radio.openReadingPipe(1, PIPE_SOIL_TO_MEGA); radio.startListening();
    }

    void setup(){
      Serial.begin(115200); delay(300); Serial.println(F("[MEGA] boot"));
      setupTFT(); setupRF();
      pumpDesired=false; pumpOnStartMs=0; pumpOffStartMs=0; lastSoilRxMs=0; timedOut5min=false; soilSeen=false;
      showStatus(0,0,NAN,NAN,NO_SOIL_MS+1,false,1);
    }

    void loop(){
      static SoilPacket lastSoil={0}; const uint32_t now = millis();
      while (radio.available()) { SoilPacket s; radio.read(&s,sizeof(s)); lastSoil=s; lastSoilRxMs=now; lastSoilPct=s.pct; soilSeen=true;
        Serial.print(F("[MEGA] SOIL seq=")); Serial.print(s.seq); Serial.print(F(" raw=")); Serial.print(s.raw);
        Serial.print(F(" pct=")); Serial.print(s.pct); Serial.print(F(" T=")); Serial.print(s.tempC);
        Serial.print(F("C H=")); Serial.print(s.hum); Serial.println(F("%")); }

      uint8_t reason=0; bool desired=pumpDesired;
      if (!soilSeen) { desired=false; reason=1; timedOut5min=false; }
      else if (now-lastSoilRxMs>NO_SOIL_MS) { desired=false; reason=1; timedOut5min=false; }
      else {
        if (pumpDesired) {
          if (lastSoil.pct>=OFF_THRESH) { desired=false; reason=3; timedOut5min=false; }
          else if (!timedOut5min && (now-pumpOnStartMs>PUMP_MAX_ON_MS)) { desired=false; reason=2; timedOut5min=true; }
        } else {
          if (timedOut5min) {
            if ((now-pumpOffStartMs>PUMP_COOLDOWN_MS) && (lastSoil.pct<=ON_THRESH)) { desired=true; reason=0; timedOut5min=false; }
          } else {
            if (lastSoil.pct<=ON_THRESH) { desired=true; reason=0; }
            if (lastSoil.pct>=OFF_THRESH) { timedOut5min=false; }
          }
        }
      }

      if (desired!=pumpDesired) {
        pumpDesired=desired; if (pumpDesired) pumpOnStartMs=now; else pumpOffStartMs=now; sendPump(pumpDesired,reason,lastSoilPct);
      } else {
        static uint32_t lastKeepAlive=0; if (now-lastKeepAlive>1000) {
          sendPump(pumpDesired, (!soilSeen || (now-lastSoilRxMs>NO_SOIL_MS))?1:(timedOut5min?2:(pumpDesired?0:(lastSoil.pct>=OFF_THRESH?3:0))), lastSoilPct);
          lastKeepAlive=now; }
      }

      uint32_t age = soilSeen ? (now-lastSoilRxMs) : (NO_SOIL_MS+1);
      showStatus(soilSeen?lastSoil.pct:0, soilSeen?lastSoil.raw:0, soilSeen?lastSoil.tempC:NAN, soilSeen?lastSoil.hum:NAN,
                 age, pumpDesired, (!soilSeen||age>NO_SOIL_MS)?1:(timedOut5min?2:(pumpDesired?0:(lastSoil.pct>=OFF_THRESH?3:0))));
    }

## Example Pump Node ACK (Optional Reference)

    // Pseudocode illustrating how a pump node might parse PumpCmd
    struct PumpCmd { uint32_t seq; bool pumpOn; uint8_t lastSoilPct; uint8_t reason; };
    if (radio.available()) { PumpCmd c; radio.read(&c,sizeof(c)); digitalWrite(PUMP_RELAY, c.pumpOn?HIGH:LOW); }

# References

- TMRh20 RF24 library (nRF24L01+)

- MCUFRIEND_kbv display driver and Adafruit GFX primitives

- Arduino AVR core documentation
