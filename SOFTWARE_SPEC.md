# LineSlat Software Specification

2026-10-14 · Rudy Albachten

## Overview

LineSlat firmware runs on an ATSAMD21G18A (48 MHz Cortex-M0+, 256 KB flash, 32 KB RAM). Each board fires up to eight pyro cues. Boards are daisy-chained left and right over RS-485 through two RJ45 connectors, which also carry battery power. The power source is a DeWalt 20V MAX pack (5S Li-ion, 15 to 21 V).

A board with the RFM95W LoRa module fitted is the **master**. It receives fire commands over 915 MHz LoRa and passes them down the chain. A board without the module is a **slave**. A single board can also be used on its own as an 8-cue controller.

Firmware builds with the custom LineSlat board variant (`PlatformIO/Pyro/LineSlat/variants/lineslat/variant.cpp`). Its pin numbering matches the Adafruit Feather M0 / Arduino Zero. Every pin is referred to below by its Arduino number.

This spec covers what the firmware must do on this hardware: pin use, peripheral setup, I2C addresses, and the firing and safety rules. It is based on schematic rev v2.0 (2025-11-23). The radio command protocol and the left/right serial protocol are defined in separate documents.

The KiCad design files and this spec are in the [albachten/LineSlat](https://github.com/albachten/LineSlat) repo on GitHub.

## Functional requirements

### Power and arm states

The battery connects to J8 or reaches the board as +BAT on pins 2, 6 and 8 of either RJ45. The master's battery powers the whole chain. Two switches set the board's state:

- **SW1 (POWER)** is a DPDT switch. One pole feeds +BAT through D2 to +18V, which powers the logic. The other pole feeds +BAT through D1 to SW2.
- **SW2 (ARM)** connects V_ARM to the second pole of SW1.

In the off or safe position, each switch connects its output to a bleeder resistor: R42 (10K) for +18V and R41 (5K1) for V_ARM. These discharge C1 and C2/C3 in about 1 s.

| SW1 | SW2 | Logic (3V3) | +18V | V_ARM | ARM LED |
| --- | --- | --- | --- | --- | --- |
| Off | Any | Off, unless USB is connected | 0 V | 0 V | Off |
| On | Safe | On | Battery − 0.8 V | 0 V | Off |
| On | Armed | On | Battery − 0.8 V | Battery − 0.8 V | On |

- 3V3 comes from U5 (TSR1-2433), a switching regulator fed from +18V through D3. It stays regulated across the full battery range.
- When USB is connected, VBUS also powers the logic through D4. The TSR1-2433 needs 4.75 V in and gets about 4.7 V from USB, so it may run slightly out of regulation on USB alone.
- Firmware cannot read SW1 or SW2 directly. See [Arm check](#arm-check).

### Battery monitoring

- A0 (PA02) reads +18V through a 1M / 100K divider: +18V = 11 × V(A0). Battery ≈ +18V + 0.8 V, which is the S3A drop of D2.
- +18V is at most about 20.2 V, so A0 never exceeds 1.84 V. 3V3 is regulated, so the default VDDANA reference (3.3 V full scale) is accurate enough. At 12 bits, one count is about 8.9 mV of battery voltage.
- AREF (PA03) has only a 1 µF capacitor (C8), so it cannot serve as an external reference.
- The battery can be measured whenever SW1 is on, whether the board is armed or not. With SW1 off, A0 reads 0 V.
- Sample at least once per second while idle, and report the result with every status message. A 5S pack is full at 21.0 V, nominal at 18 V and empty at about 15 V. Report it as low below 16.5 V (3.3 V per cell).

### Arm check

V_ARM has no ADC input. Firmware checks the armed state with the INA219 instead:

1. Make sure all eight cue pins are low.
2. Set D9_FIRE high. The high-side switch connects V_ARM to ECOMMON, the common (red) clips. No current flows because every low-side FET is off.
3. Wait about 2 ms. This covers Q9 turn-on and one full INA219 shunt-plus-bus conversion.
4. Read the INA219 bus voltage, which is ECOMMON to GND.
   - **Armed:** about V_ARM − 1 V, so 14 to 20 V.
   - **Safe:** about 2.9 V, fed from 3V3 through D8 and R31.
5. Treat the board as armed above 10 V and as safe below 5 V. Between those values, report the state as unknown and refuse to fire.

This check is part of every fire (see [Firing](#firing)). Firmware may also run it every few seconds while idle to report arm status. If it does, it must set D9_FIRE low again as soon as the reading is taken.

### Firing

Each cue is fired by two switches in series. D9 drives the shared high-side switch: Q10 (NPN) turns on Q9 (PMOS). Current then flows from V_ARM through D6, R37 (2 Ω 5 W) and the shunt R51 to ECOMMON. Each cue select pin drives one low-side FET (Q1–Q8), which switches that cue's black clip (L1–L8). All select pins and D9 are active high. Neither switch can fire a cue alone.

1. Check that the command is valid for this board and cue.
2. Set D9_FIRE high and run the [arm check](#arm-check). If the board is not armed, set D9_FIRE low and refuse the command.
3. Set the cue's select pin high for exactly 100 ms. That way the low-side NMOS FET switches the fire current, not the PMOS. E-matches light in 10–20 ms at 1 A.
4. While firing, read the INA219 shunt voltage about every 1 ms. The current at a full battery is about (V_ARM − 1 V) ÷ (2.1 Ω + match resistance), which is around 5 A. Firmware does not need to measure it exactly. It only records whether any sample exceeded 1 A, which is 100 mV on the shunt.
5. Set the select pin low, then D9_FIRE low.
6. Report the fire as good if the current exceeded 1 A, and as failed otherwise.

The shunt reading saturates at 3.2 A with the setup below. This is expected, because only the 1 A threshold matters.

### Continuity test

With D9_FIRE low, setting one cue's select pin high routes a small test current through that cue's match: 3V3 → D8 → R31 (150 Ω) → shunt R51 → ECOMMON → match → low-side FET.

- The test current is about 19 mA through a good match and near 0 mA through an open one. The matches' no-fire current is at least 200 mA, so the test cannot fire them.
- The INA219 shunt current shows whether the cue is open or closed. Its bus voltage (IN− to GND) is the voltage across the match and FET, so match resistance ≈ bus voltage ÷ current. The bus voltage LSB is 4 mV, so this resistance estimate is coarse.
- Test one cue at a time. Keep the select pin on only as long as the measurement needs, for example 10 ms.
- The continuity test works in both the safe and armed states, because D9 stays low.

### Master and slave role

- At startup, pulse the radio's RESET (D4) low and then read SX1276 register RegVersion (0x42). If it returns 0x12, the radio is fitted and the board is the master. Otherwise the board is a slave.
- MISO (D22) floats when no radio is fitted. Enable its internal pull-up during the probe so that a missing module reads 0xFF.
- On a slave, set D3 as an input with a pull-down and do not attach an interrupt. Leave D4 and D5 driven high.

### Radio (master only)

- U3 is an RFM95W (SX1276) LoRa module at 915 MHz on the default SPI bus.
- Only DIO0 is wired (to D3), so the driver must use a single interrupt line. RadioHead RH_RF95 and arduino-LoRa both work this way.
- Pull the radio's RESET (D4) low for at least 1 ms at startup, then wait 5 ms before using SPI.
- The command protocol is defined in a separate spec.

### Daisy chain (RS-485)

Each board has two independent half-duplex RS-485 ports. Each one is a point-to-point link to the neighboring board.

| Port | Side | Connector | UART | RX / TX / TX enable | Transceiver | Termination |
| --- | --- | --- | --- | --- | --- | --- |
| COM1 | Left | J5 | Serial1 (SERCOM0) | D0 / D1 / D2 | U1 THVD1400 | R33 100 Ω |
| COM2 | Right | J6 | Serial2 (SERCOM1) | D11 / D10 / D12 | U2 THVD1400 | R39 100 Ω |

"Left" and "right" are as seen looking at the component side of the PCB.

- **TX enable.** The enable pin drives both DE and ~RE. High enables the driver and turns off the receiver. Low returns to receive. Before setting it low, call `flush()`. In the SAMD core this waits until the last stop bit has been shifted out.
- **RX while sending.** RO is high-impedance while transmitting, so the RX pin floats. Enable the RX pin's internal pull-up, or discard anything received while the enable pin is high.
- **Idle bus.** The THVD1400 has receiver fail-safe, so an idle, open or shorted bus reads as idle (logic 1). The board has no bias resistors.
- **Speed.** The THVD1400 supports up to 500 kbps. The baud rate and message format are defined in the serial protocol document.
- **Setup.** The LineSlat variant does not create either UART, so the firmware must create both:

```cpp
Uart Serial1(&sercom0, 0, 1, SERCOM_RX_PAD_3, UART_TX_PAD_2);   // RX PA11, TX PA10
Uart Serial2(&sercom1, 11, 10, SERCOM_RX_PAD_0, UART_TX_PAD_2); // RX PA16, TX PA18
void SERCOM0_Handler() { Serial1.IrqHandler(); }
void SERCOM1_Handler() { Serial2.IrqHandler(); }
// After Serial2.begin(): pinPeripheral(10, PIO_SERCOM); pinPeripheral(11, PIO_SERCOM);
```

RJ45 pinout (J5 and J6): 1, 3, 7 GND; 2, 6, 8 +BAT; 4 COM− (B); 5 COM+ (A).

### Indicators

- **PWR (green LED13) on 3V3 and ARM (red LED12) on V_ARM:** driven by hardware only.
- **Cue LEDs (red LED1–LED8):** one on each cue select line. Each lights whenever its select pin is high, during both fire and continuity tests. A 10 ms continuity test gives only a faint flash.
- **FIRE LED (red LED9):** lights whenever D9_FIRE is high, including during the arm check.
- **TX and RX LEDs (yellow LED10 and LED11) on D26 and D25:** active low. The variant leaves `PIN_LED_TXL` and `PIN_LED_RXL` undefined, so the Arduino core does not drive them, and firmware must. Suggested use: blink them on RS-485 or radio traffic.
- **There is no user LED.** D13 is not connected.
- **OLED (DISP1):** the main status display (see [I2C bus](#i2c-bus)).

### USB, serial and debug

- Native USB (PA24/PA25) gives CDC serial for debug messages and bootloader uploads.
- Install the bootloader through the Cortex SWD header J4. Double-tap reset (SW3) to enter it.

## Pin assignments

The pin numbers come from the LineSlat variant, which matches the Feather M0 / Arduino Zero numbering. All signals are 3.3 V logic.

| Arduino pin | SAMD21 port | Net | Direction | Function and notes |
| --- | --- | --- | --- | --- |
| D0 | PA11 | D0_RX1 | In | Serial1 RX (SERCOM0 pad 3) from U1 RO. COM1, left |
| D1 | PA10 | D1_TX1 | Out | Serial1 TX (SERCOM0 pad 2) to U1 DI |
| D2 | PA14 | D2_TXEN1 | Out | U1 DE and ~RE. High = transmit |
| D3 | PA09 | D3_RADIO_IRQ | In | RFM95 DIO0. Interrupt on rising edge (master only) |
| D4 | PA08 | D4_RADIO_RST | Out | RFM95 reset, active low |
| D5 | PA15 | D5_RADIO_CS | Out | RFM95 SPI chip select, active low |
| D6 | PA20 | D6_CUE1 | Out | Cue 1 low-side FET Q1 (L1). Active high, 1M pull-down |
| D7 | PA21 | D7_CUE2 | Out | Cue 2 low-side FET Q2 (L2). Active high, 1M pull-down |
| D8 | PA06 | D8_CUE3 | Out | Cue 3 low-side FET Q3 (L3). Active high, 1M pull-down |
| D9 | PA07 | D9_FIRE | Out | Shared high-side switch (Q10 → Q9). Active high |
| D10 | PA18 | D10_TX2 | Out | Serial2 TX (SERCOM1 pad 2) to U2 DI. COM2, right |
| D11 | PA16 | D11_RX2 | In | Serial2 RX (SERCOM1 pad 0) from U2 RO |
| D12 | PA19 | D12_TXEN2 | Out | U2 DE and ~RE. High = transmit |
| A0 (D14) | PA02 | A0_VBAT | Analog in | +18V ÷ 11 |
| A1 (D15) | PB08 | A1_CUE7 | Out | Cue 7 low-side FET Q7 (L7). Active high, 1M pull-down |
| A2 (D16) | PB09 | A2_CUE8 | Out | Cue 8 low-side FET Q8 (L8). Active high, 1M pull-down |
| A3 / D17 | PA04 | D17_CUE4 | Out | Cue 4 low-side FET Q4 (L4). Active high, 1M pull-down |
| A4 / D18 | PA05 | D18_CUE5 | Out | Cue 5 low-side FET Q5 (L5). Active high, 1M pull-down |
| A5 / D19 | PB02 | D19_CUE6 | Out | Cue 6 low-side FET Q6 (L6). Active high, 1M pull-down |
| D20 / SDA | PA22 | SDA | I/O | I2C data (SERCOM3), 10K pull-up |
| D21 / SCL | PA23 | SCL | Out | I2C clock (SERCOM3), 10K pull-up |
| D22 / MISO | PA12 | MISO | In | SPI (SERCOM4) to RFM95 |
| D23 / MOSI | PB10 | MOSI | Out | SPI (SERCOM4) to RFM95 |
| D24 / SCK | PB11 | SCK | Out | SPI (SERCOM4) to RFM95 |
| D25 | PB03 | RXLED | Out | Yellow RX LED, active low |
| D26 | PA27 | TXLED | Out | Yellow TX LED, active low |
| D28 / D29 | PA24 / PA25 | USB_D− / USB_D+ | I/O | Native USB |
| — | PA00 / PA01 | XTAL1 / XTAL2 | — | 32.768 kHz crystal (XOSC32K) |
| — | PA03 | AREF | — | 1 µF to GND only |
| — | PA30 / PA31 | SWCLK / SWDIO | — | SWD on J4 |
| — | RESET | ~RESET | In | SW3 and J4, 10K pull-up |

The cue numbers do not follow the Arduino pin order. Use a lookup table, for example `{6, 7, 8, 17, 18, 19, A1, A2}` for cues 1–8. The variant's `SS` is defined as A2, which is cue 8 on this board, so firmware must never use `SS`.

These pins have net labels but connect to nothing: D13 (PA17), D27 USBHOSTEN (PA28), D30/D31 (PB22/PB23) and D38 (PA13, labeled D39 on the schematic). Configure them as inputs with pull-downs to keep current draw low. The RFM95's DIO1–DIO5 are not connected either.

## I2C bus

One I2C bus (Wire, SERCOM3, SDA on D20 and SCL on D21) connects the INA219 and the OLED. The bus has 10K pull-ups to 3V3. Run it at 400 kHz, which both devices support. Even at that speed, a full OLED refresh takes about 13 ms, so do not refresh the OLED during a fire.

| Address (7-bit) | Device | Notes |
| --- | --- | --- |
| 0x3C | OLED display (DISP1), SSD1306 0.91 in 128×32 module | |
| 0x40 | INA219B current monitor (U6) | A0 and A1 both tied to GND |

DISP1 pinout: 1 GND, 2 VCC (3V3), 3 SCL, 4 SDA.

### INA219 setup

- **Config register (0x00):** write 0x399F, which is also the power-on default. This sets a 32 V bus range, PGA ÷8 (±320 mV, ±3.2 A on the 0.1 Ω shunt R51), 12-bit samples and continuous shunt and bus conversion. The 32 V range is required because ECOMMON reaches about 20 V when firing.
- **Current:** read the shunt voltage register (0x01) directly. Its LSB is 10 µV, which is 100 µA on R51. The 1 A fire threshold is a reading of 10000 or more. The ~19 mA continuity current reads about 190. No calibration register or range switching is needed.
- **Bus voltage (0x02):** shift right by 3, then multiply by 4 mV. This is the voltage at ECOMMON, the common (red) clips, relative to GND.
- One conversion takes about 0.53 ms (12-bit), so a shunt-plus-bus pair takes about 1.06 ms. During a fire, sample about every 1 ms.

## SPI radio interface

The RFM95W is the only SPI device. It sits on the default Arduino SPI bus (SERCOM4) and is fitted on the master only.

| Setting | Value |
| --- | --- |
| SPI pins | MISO D22 (PA12), MOSI D23 (PB10), SCK D24 (PB11) |
| Chip select | D5 (PA15), active low |
| Reset | D4 (PA08), active low |
| Interrupt | D3 (PA09), DIO0 only. DIO1–DIO5 are not connected |
| SPI mode and clock | Mode 0, MSB first, 8 MHz or less (the SX1276 allows up to 10 MHz) |
| Frequency | 915 MHz (US 902–928 MHz band) |
| TX output | PA_BOOST pin, up to +20 dBm |
| Suggested modem | LoRa, 125 kHz BW, SF7–SF9, CR 4/5, private sync word 0x12 |
| Antenna | On-board 915 MHz antenna (ANT1) |

The RadioHead RH_RF95 driver works with this pinout: `RH_RF95 rf95(5, 3);`, after pulsing reset on D4. The over-the-air command protocol is outside this spec.

## Safety requirements

Firing needs two independent switches, the high-side switch and a cue's low-side switch, plus the physical ARM switch. Firmware must never be the only thing preventing a fire.

1. **Safe outputs at boot.** The first lines of `setup()` set D9 and all eight cue pins (D6, D7, D8, D17, D18, D19, A1, A2) as outputs driven low, before any other setup. All switches stay off until then: Q1–Q8 have 1M gate pull-downs, and Q10 (a bipolar transistor) needs base current, which the MCU's reset-state input pins don't supply.
2. **Fire only when armed.** Refuse every fire command unless the [arm check](#arm-check) reads ECOMMON above 10 V immediately before the cue pin is set high.
3. **Valid commands only.** Act only on a fire command addressed to this board and cue. Discard duplicates and stale commands, using a sequence number or a timestamp.
4. **100 ms fire pulse.** Each cue's select pin is high for 100 ms, and never longer. At a full battery R37 dissipates about 50 W while a match is firing, and about 170 W into a shorted cue, against its 5 W rating. Use a hardware timer or a loop based on `millis()`, never a delay that an interrupt or a radio handler could stretch.
5. **At most one fire per second.** A 100 ms fire at about 50 W puts an average of about 5 W into R37 at one fire per second, which is its rating. Normal shows leave tens of seconds between cues, so this limit is never reached in practice. Firmware still enforces it: reject a fire that comes less than 1 s after the previous fire on the same board.
6. **One cue at a time.** All eight cues share R37 and the shunt. Firing two at once splits the current and may not light either match.
7. **D9 high only with cue pins low.** Set D9 high only when all cue pins are low, at the start of a fire or for an arm check. Never set D9 high during a continuity test.
8. **Watchdog.** Enable the WDT with a timeout of about 1 s. A reset leaves all pins high-impedance, which turns Q1–Q8 and Q10 off.
9. **Brown-out.** Enable BOD33 at about 2.9 V. 3V3 is regulated, so it only sags if the battery or USB supply fails.
10. **Clean up after firing.** After every fire, or any fault such as a command timeout or radio or serial error, drive all cue pins low first, then D9, so the low-side FET breaks the current.
