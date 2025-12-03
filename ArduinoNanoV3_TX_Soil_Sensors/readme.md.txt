# 🌱 Smart Garden Project
### **Module 2️⃣ — Arduino Nano V3 “Sensors” Node**

---

## 📝 **Purpose**

The **Sensor Node** continuously measures **soil moisture**, **temperature**, and **humidity**, transmitting the readings wirelessly to the **Hub (Arduino Mega 2560)** using the **nRF24L01+** transceiver.  
It serves as the **data acquisition unit** in the Smart Garden network, enabling automated irrigation control and environmental monitoring.

---

## ⚙️ **Hardware Overview**

| Component | Function | Notes |
|------------|-----------|-------|
| **Arduino Nano V3** | Core microcontroller | Reads sensor data and handles RF transmission |
| **nRF24L01+** (with 5V→3.3V adapter) | Wireless RF transceiver | Sends sensor data to Hub Node |
| **Capacitive Soil Moisture Sensor v1.2** | Measures soil moisture | Analog output connected to A0 |
| **DHT11 Sensor** | Measures temperature & humidity | Digital output on D2 |

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

### 🌡️ Sensors

| Sensor | Arduino Pin | Description |
|---------|--------------|-------------|
| **Capacitive Soil Moisture v1.2** | A0 | Analog output proportional to soil humidity |
| **DHT11 Temp/Humidity** | D2 | Data pin (with internal pull-up) |
| VCC | 5V | Power line for both sensors |
| GND | GND | Shared ground |

---

## ⚙️ **Power Requirements**

| Component | Typical Current | Notes |
|------------|----------------|-------|
| Arduino Nano | ~20 mA | Base MCU consumption |
| DHT11 | ~2 mA | During measurement cycles |
| Soil Sensor | ~10 mA | Analog output circuit |
| nRF24L01+ | ~100 mA (burst) | During transmission |
| **Total** | ≈ 150 mA | Safe with 5V USB or regulated supply |

**Recommended Supply Options:**
- USB 5V power (from PC or charger)
- 5V regulated power adapter
- Optional: external capacitor (470 µF) near Nano 5V line for RF stability

---

## 🧩 **Shared RF Configuration**

| Parameter | Value | Description |
|------------|--------|-------------|
| **RF Channel** | 100 (2.5 GHz band) | Shared among all nodes |
| **Data Rate** | 250 kbps | Maximizes stability over distance |
| **Payload Size** | 32 bytes | Compact and efficient |
| **Auto Acknowledgment** | Enabled | Ensures delivery reliability |
| **CRC Length** | 16-bit | Improves data integrity |
| **Pipe Addressing** | Unique per node | Hub ↔ Sensor ↔ Pump |

---

## 📡 **Operation Summary**

1. **Sensor Node** measures temperature, humidity, and soil moisture periodically.  
2. Data is packaged into a **compact RF packet** and sent to the **Hub Node (Mega 2560)**.  
3. The Hub processes the data, displays it on the TFT screen, and makes irrigation decisions.  
4. The system provides real-time feedback to ensure plants maintain optimal soil conditions.

---

## 🔋 **Power Supply**

- Use stable **5V USB** or **external regulated 5V** input.  
- Ensure common ground with the Hub and Pump Nodes.  
- For battery power: include an **LM2596 step-down regulator** for efficiency.

---

## 🧠 **Future Expansion Ideas**

- Replace **DHT11** with **DHT22** or **BME280** for higher accuracy.  
- Add **light sensor (LDR or BH1750)** to measure sunlight intensity.  
- Implement **sleep mode** for energy-saving in battery-powered nodes.  
- Secure transmission using **Trust M (ATECC608A)** authentication chip.  
