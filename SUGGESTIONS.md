# LineSlat Hardware Suggestions

2026-10-18 · Review of schematic rev v2.0 (2025-11-23)

This review compares the schematic and PCB with [SOFTWARE_SPEC.md](SOFTWARE_SPEC.md). It used a netlist, ERC and DRC run with kicad-cli 9.0. DRC reports no violations. ERC reports one warning: the ANT1 symbol does not match its copy in MyLib. The netlist matches the topology and pin table in the spec.

The items are ordered by priority within each section. Items marked **(spec)** also changed SOFTWARE_SPEC.md, either to work around the issue on v2.0 boards or because firmware can cover part of it.

## 1. Safety and robustness

### 1.1 Add a base-emitter pull-down to Q10 (reworked on v2.0)

The cue FETs Q1–Q8 have 1M gate pull-downs, but the D9_FIRE → R25 → Q10 base net has none. The only load on D9 is LED9 and R30, which draw almost nothing below about 1.6 V. While the MCU is in reset or booting, D9 floats. If the board powers up already armed, a few hundred nA of leakage times Q10's hFE can give tens of µA of collector current. Q9 starts to turn on with only about 10 µA through R50.

- **v2.0 rework:** 10K (0603 or 0805) across Q10 pin 1 (base) and pin 2 (emitter, GND). See the [Board modifications](SOFTWARE_SPEC.md#board-modifications) section of the spec. **(spec)**
- **Next revision:** put the 10K on the schematic next to R25.
- With the 10K fitted, D9 high still gives about 2.75 V open-circuit at the base through R25 (2K). The resistor takes only about 65 µA of the roughly 1.3 mA base drive, so Q10 still saturates.

### 1.2 A shorted Q9 plus a continuity test fires a cue

A continuity test turns on a low-side FET with D9 low. If Q9 or Q10 has failed short, which is the usual way a MOSFET fails, ECOMMON sits at V_ARM whenever the board is armed. The first continuity test then fires that cue.

- **Firmware (v2.0):** with D9 low and all cue pins low, read the INA219 bus voltage before each continuity test and each arm check. Above 5 V means the high-side switch has failed. Lock out all continuity tests and fires, and report the fault. **(spec)**
- **Firmware (v2.0):** a power-on lockout (refuse fires until the arm check has read safe once) was considered and dropped (2026-10-19): a brown-out mid-show would strand boards until someone cycled their keys. After any reset a board fires only once the controller has synced and armed it again. See `docs/reset_behavior.md` in the pyro repo.
- **Option:** allow continuity tests only while the board reads safe. This removes the hazard completely but stops crews from re-testing an armed board.
- **Hardware:** add a V_ARM sense divider (for example 1M / 100K, with 100 nF) to **PA03**. PA03 is AIN1. Today it only has the AREF capacitor C8, which isn't needed because the firmware uses the VDDANA reference. With the divider, firmware can read the arm state without switching Q9, and compare V_ARM with ECOMMON to detect high-side faults with D9 low.

### 1.3 The two "independent" switches are driven by one MCU

The high-side and low-side switches use separate transistors, but one firmware fault or stuck pin can turn both on. For independence in hardware:

- Drive Q10 through an AC-coupled or charge-pump stage, so the high side conducts only while D9 is toggling. A stuck-high or stuck-low pin then turns it off.
- Or add an RC one-shot that drops Q9 after about 150–200 ms, so the 100 ms limit no longer depends only on firmware.

### 1.4 Q1–Q9 into a shorted cue

Into a dead short the current is about (20.2 − 1) V ÷ 2.2 Ω ≈ 9 A. At 3.3 V gate drive the DMG3402 (SOT-23, about 60–70 mΩ) dissipates about 5 W for 100 ms. That is near its single-pulse limit. Q9, also in SOT-23, sees the same.

- **Hardware:** use FETs with more thermal headroom, for example a logic-level part in PowerDI3333 or DFN2020 that is rated at Vgs = 2.5 V.
- **Firmware (v2.0):** the INA219 shunt reading saturates at 3.2 A, so it cannot measure a short directly. The bus voltage can show one: it is the voltage across the match and FET, about 0.6 V into a short and 5 V or more into a real match. If the shunt reading is saturated and the bus voltage stays below 2 V after 20 ms, end the pulse early. **(spec)**

### 1.5 No transient or ESD protection on the field terminals

The clips go to long, exposed lead wires.

- ECOMMON goes to the INA219 inputs through only 10 Ω. The INA219's absolute maximum is 26 V.
- L1–L8 have no protection. The DMG3402s have only about 9 V of margin above the battery for the inductive kick when a cue turns off under current.
- **Suggestion:** add a TVS (for example SMBJ24A) on V_ARM and on ECOMMON, and a TVS or ESD array on L1–L8.

## 2. Power and the daisy chain

### 2.1 Fire current flows through the Ethernet cable

A slave's fire current (5–9 A) comes from the master's battery over +BAT and GND, on three 24 AWG conductors each way.

- 24 AWG is about 84 mΩ/m, so 30 m of Cat5 with three conductors in parallel is about 0.84 Ω each way (1.7 Ω round trip, before connector contacts). At 5 A that is about 4 V lost each way per link, and the losses add up down the chain. Far boards fire with less voltage.
- Every unit fires the same cue at once, so the links near the master carry the sum of the fire currents. A model with an 18 V battery and 1.5 Ω matches gives these values at the far board while firing:

  | Spacing | Boards | Far board +BAT | Far board match current |
  | --- | --- | --- | --- |
  | 10 m | 4 | 9.6 V | 2.1 A |
  | 10 m | 6 | 5.6 V | 1.0 A |
  | 30 m | 3 | 8.0 V | 1.6 A |
  | 30 m | 4 | 5.2 V | 0.9 A |
  | 30 m | 6 | 2.8 V | 0.2 A |

- **The current use is within limits.** Up to 8 stations, master in the middle (4 + 3 slaves), at most 10 ft per link. A model of that setup, with every board firing, gives these values at the far board (4 hops):

  | Battery | Match | Far board +BAT | Far board match current | Battery current |
  | --- | --- | --- | --- | --- |
  | 16 V | 1.0 Ω | 8.5 V | 2.1 A | 23 A |
  | 18 V | 1.5 Ω | 10.1 V | 2.2 A | 24 A |
  | 20 V | 1.5 Ω | 11.1 V | 2.5 A | 27 A |
  | 16 V, pessimistic (0.15 Ω battery, 0.15 Ω contacts per link each way) | 1.0 Ω | 6.0 V | 1.3 A | 17 A |

  U5 stays fed from the cable except in the pessimistic case, where it reaches the 6 V limit and C1 covers the rest. The items below matter for the redesign (longer links, more hops, master at one end). For v2.0, a full-chain fire pulls 20–30 A from the DeWalt pack, so test one with a low battery to make sure the pack's protection doesn't trip.
- **Logic hold-up.** U5 needs about 6 V at +BAT (4.75 V plus D2 and D3). Below that, a far board's 3V3 runs only from C1. C1 is usable from its starting voltage down to about 5.1 V. At an estimated 165–330 mW into U5 (40–80 mA at 3V3), it lasts:

  | C1 | From 16 V | From 19 V |
  | --- | --- | --- |
  | 100 µF (v2.0) | 35–70 ms | 50–100 ms |
  | 470 µF | 165–330 ms | 240–480 ms |

  That covers a good match, which opens in 10–20 ms, but not a full 100 ms pulse. A single dud match anywhere in the chain keeps the cable low for 100 ms. Measure the real 3V3 current with the OLED lit to confirm these numbers.
  - **Firmware (v2.0):** keep the 3V3 load low during a fire. **(spec)**
  - **Firmware:** staggering fires by unit index (for example 20 ms per unit), so only one board's fire current is on the cable at a time, was considered and dropped (2026-10-22). The 4 + 3 setup at 10 ft per link has enough margin without it. If the redesign needs it, each unit must forward the fire command down the chain before any unit fires, because fires corrupt RS-485 traffic.
  - **Hardware:** make C1 470 µF, rated 35 V. D2 already keeps the cable from draining it.
- **Match energy on far boards.** Far boards get well under 1 A from the cable, so C2/C3 must light the match nearly alone. They discharge through D6, R37, the shunt and the FET (about 2.2 Ω plus a diode drop), so a 1.5 Ω match gets only about 40% of their energy. 200 µF at 16 V gives the match about 6 A²·ms. The bench test in `Ematch2_v1/ematch_cap_test.txt` (200 µF at 9 V across the match) gives about 5 A²·ms, so the margin is small. Test-fire matches through a board's real fire path from C2/C3 alone, with the cable supply removed.
- The ground shift between boards adds up the same way. The RS-485 links share that ground, and the THVD1400's common-mode range is −7 to +12 V. Expect communication errors during fires on long chains. **(spec: protocol must tolerate errors during fires)**
- RJ45 contacts: checked (2026-10-22). The SS-700810 limit is thermal, 1.5 A average per contact. The first link carries about 9 A across three pins during a fire, but at the fire budget's limit of one cue per second that averages about 0.06 A per pin, or about 0.3 A if a dud runs the full 100 ms.
- **Suggestion:** a local battery on each slave, or local storage on V_ARM (supercapacitor or larger bulk capacitance) charged from the cable through a current limit.

### 2.2 Batteries are paralleled with no protection

J8 ties straight to +BAT on both RJ45s. A pack connected at two boards puts two packs at different charge levels in parallel through Ethernet cable. Add OR-ing (an ideal-diode controller on each input), and a PTC or fuse on the +BAT going out to each RJ45. The fuse also covers a crushed cable shorting 20 V.

### 2.3 20 V on an RJ45

Plugging a board into real Ethernet equipment will damage it. Label the jacks clearly, or move to a different keyed connector.

### 2.4 RS-485 bus fault tolerance

A mis-crimped cable can put +BAT (21 V) on A or B, which is beyond the THVD1400's bus-pin rating. The THVD24x0 family (±70 V bus fault protection) suits a cable that also carries battery power.

### 2.5 USB-only operation

- The TSR1-2433 needs 4.75 V in and gets about 4.65 V from USB through the BAT54W (D4). Use a regulator with a lower minimum input (for example an LMR36006 or TPS62933 buck), or add an LDO path from VBUS.
- U5 has no input capacitor on VIN. On USB power nothing is there, and on battery power C1 sits behind D3. Add 10 µF at U5 pin 1.

### 2.6 Fire current goes through the switch contacts

The full fire current passes through SW1B and SW2. Check the E-Switch T2 DC current ratings. For the arm function, a removable key or shunt plug is common pyro practice and is harder to bump than a toggle.

### 2.7 Bulk capacitor voltage rating

C1–C3 should be rated at least 35 V on a 21 V rail. Confirm the rating of the 860010573007.

### 2.8 Input diode losses

D1, D2 and D6 (S3A) drop 1–1.2 V at fire current. A P-FET reverse-polarity circuit on the input would get back about 1 V of fire voltage and cut the heat in D1.

## 3. BOM and symbol errors

Fix these before the next order.

| Ref | Issue |
| --- | --- |
| SW3 | Mouser PN `652-CR0805JW-104ELF` is a 100K 0805 resistor, not a pushbutton. |
| LED13 | Value is GREEN, but PN `710-150080RS75000` is the red part. It should be `710-150080GS75000`. |
| Q9 | Value and symbol are DMG3401, but the PN is DMP3099L-13, which is SOT-23, while the footprint is SC-59. Pick one part and check that its Vgs rating suits the 10 V clamp (D7). |
| R51 and the other passives | No MPN, power or voltage rating. R51 especially needs a specific pulse-rated shunt. |
| ANT1 | ERC warning: the symbol does not match its copy in MyLib. |

## 4. Minor improvements

- **J7 shield is unconnected.** Tie it to GND, directly or through RC. Consider a USB ESD array such as a USBLC6-2 on D+ and D−.
- **I2C pull-ups.** 10K is weak for 400 kHz. 4.7K is safer, unless the OLED module has its own pull-ups.
- **A0 divider.** The 91K source impedance needs a long ADC sample time. Add 100 nF from A0 to GND. **(spec: keep a long sample time)**
- **Unused pins (PA13, PA17, PA28, PB22, PB23).** Use one for a user LED or an SW2 sense line, and bring PB22/PB23 out to pads as a debug UART.
- **Antenna.** The master often sits low in a field. A u.FL or SMA footprint as an alternative to the coil antenna would give more range.
