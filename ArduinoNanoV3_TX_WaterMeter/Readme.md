# 💧 Smart Garden Project
### **Module 4️⃣ — Arduino Nano V3 “Water Meter” Node**

---

## 📝 **Purpose**

The **Water Meter Node** monitors and reports **total water flow** used by the irrigation system.  
It receives pulses from a **flow sensor (YF‑S201 or similar)** connected to the water line, converts them into a volume reading (mL or L), and transmits this data to the **Hub (Arduino Mega 2560)** via the **nRF24L01+** radio module.  
This ensures precise water usage tracking and enables future integration of analytics for water efficiency optimization.

---

## ⚙️ **Hardware Overview**

| Component | Function | Notes |
|------------|-----------|-------|
| **Arduino Nano V3** | Core microcontroller | Counts flow pulses and transmits water volume data |
| **nRF24L01+** (with 5V→3.3V adapter) | Wireless RF transceiver | Sends volume data to Hub Node |
| **Water Flow Sensor (YF‑S201 or compatible)** | Measures flow rate | Generates pulse output proportional to flow |

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

### 🚿 Water Flow Sensor

| Signal | Arduino Nano Pin | Description |
|--------|-------------------|--------------|
| OUT (Signal) | D2 | Pulse output per revolution |
| VCC | 5V | Sensor power |
| GND | GND | Common ground |

**Pulse Calibration:**  
Each pulse corresponds to approximately **2.25 mL** for typical YF‑S201 sensors, but this value should be calibrated experimentally.

---

## ⚙️ **Power Requirements**

| Component | Typical Current | Notes |
|------------|----------------|-------|
| Arduino Nano | ~20 mA | Base MCU consumption |
| nRF24L01+ | ~100 mA (burst) | During RF transmission |
| Flow Sensor | ~15 mA | During operation |
| **Total** | ≈ 135 mA | Stable with 5V USB or regulated supply |

**Recommended Supply Options:**
- USB 5V (from PC or charger)
- Regulated 5V DC power input (LM2596 module optional)
- Add 470 µF capacitor near 5V input for RF surge protection

---

## 🧩 **Shared RF Configuration**

| Parameter | Value | Description |
|------------|--------|-------------|
| **RF Channel** | 100 (2.5 GHz band) | Shared among all nodes |
| **Data Rate** | 250 kbps | Optimized for stability |
| **Payload Size** | 32 bytes | Compact and efficient |
| **Auto Acknowledgment** | Enabled | Ensures delivery reliability |
| **CRC Length** | 16-bit | Improves data integrity |
| **Pipe Addressing** | Unique per node | Hub ↔ Sensor ↔ Pump ↔ Water Meter |

---

## 📡 **Operation Summary**

1. The **Water Flow Sensor** generates electrical pulses proportional to water flow.  
2. The **Nano** counts pulses using hardware interrupts (D2) to calculate total volume.  
3. The calculated water volume (mL/L) is periodically transmitted via **nRF24L01+** to the **Hub Node**.  
4. The **Hub** displays cumulative flow and verifies irrigation efficiency.  
5. If communication fails, the node retries transmission until acknowledgment is received.

---

## 🔋 **Power Supply**

- 5V regulated power (USB or DC adapter).  
- Ensure stable supply — RF module is sensitive to voltage dips.  
- Optional: 3.7V Li‑ion battery + step‑up converter for standalone use.

---

## 🧠 **Future Expansion Ideas**

- Add **non‑volatile memory (EEPROM)** to store total volume in case of power loss.  
- Implement **checksum validation** for transmitted flow packets.  
- Integrate **temperature compensation** for sensor accuracy.  
- Add **secure RF authentication** with **Trust M (ATECC608A)** for encrypted telemetry.  
