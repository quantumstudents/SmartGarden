# 🧠 Smart Garden Project
### **Module 3️⃣ — Arduino Nano V3 “Pump” (Relay Control Node)**

---

## 📝 **Purpose**

The **Pump Node** controls the **water pump** through a **relay or SSR (Solid-State Relay)** based on commands received via the **nRF24L01+** wireless module.  
It acts as the **actuator** of the system — executing irrigation commands sent by the central **Hub (Arduino Mega 2560)** after evaluating soil moisture levels.

---

## ⚙️ **Hardware Overview**

| Component | Function | Notes |
|------------|-----------|-------|
| **Arduino Nano V3** | Core microcontroller | Receives RF commands and toggles relay output |
| **nRF24L01+** (with 5V→3.3V adapter) | Wireless RF transceiver | Communicates with the Hub Node |
| **Relay or SSR** | Controls water pump | Triggered by digital pin D3 |

---

## 🔌 **Connections**

### 🛰️ nRF24L01+ (with adapter)

| Signal | Arduino Nano Pin | Description |
|--------|-------------------|--------------|
| CE     | D9  | Chip Enable |
| CSN    | D10 | Chip Select Not |
| SCK    | D13 | SPI Clock |
| MOSI   | D11 | Master Out Slave In |
| MISO   | D12 | Master In Slave Out |
| VCC    | 5V  | Power to adapter (3.3V regulated output) |
| GND    | GND | Common ground |
| **Decoupling** | — | Add **47–100 µF + 0.1 µF** capacitors on 3.3 V rail for stability |

---

### ⚡ Relay / Solid-State Relay (SSR)

| Signal | Arduino Nano Pin | Description |
|--------|-------------------|--------------|
| IN     | D3  | Control input signal |
| VCC    | 5V  | Power for relay module |
| GND    | —   | Common ground (shared with Arduino) |

---

## 🧩 **Shared RF Configuration**

All RF nodes in the system share the same **communication setup** to ensure reliable synchronization.

| Parameter | Value | Description |
|------------|--------|-------------|
| **RF Channel** | 100 (2.5 GHz band) | Shared among all nodes |
| **Data Rate** | 250 kbps | Maximizes stability over distance |
| **Payload Size** | 32 bytes | Compact and efficient |
| **Auto Acknowledgment** | Enabled | Ensures delivery reliability |
| **CRC Length** | 16-bit | Improves data integrity |
| **Pipe Addressing** | Unique per node | Hub ↔ Pump ↔ Soil |

---

## 💧 **Operation Summary**

1. **Hub Node** receives soil data via RF from sensor nodes.  
2. When soil moisture falls below a threshold, the **Hub** sends a **“Pump ON”** command.  
3. The **Pump Node** receives this packet via **nRF24L01+** and activates the **relay** (D3 HIGH).  
4. When soil moisture recovers, a **“Pump OFF”** signal is sent to stop irrigation.  
5. The system loops continuously for real-time plant hydration control.

---

## 🔋 **Power Supply**

- Recommended: **5 V / 1 A** regulated supply for both Nano and relay.  
- For inductive pump loads, include a **flyback diode** or **optocoupled SSR** for safety.  

---

## 🧠 **Future Expansion Ideas**

- Add **manual override** switch via serial or IoT cloud.
- Integrate **status LED** or **feedback RF packet** to confirm pump activation.
- Implement **Trust M (ATECC608A)** or rolling sequence authentication for secure RF control.
