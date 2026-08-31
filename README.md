# JAGDIS-MC1

Digital Hall-sensored 3-phase BLDC motor controller ASIC.

JAGDIS-MC1 is a V1 RTL implementation of a digital six-step BLDC motor controller intended to interface with an external 3-phase MOSFET gate driver such as the DRV8353RH class.

The ASIC generates six logic-level gate commands:

- `GH_A`, `GL_A`
- `GH_B`, `GL_B`
- `GH_C`, `GL_C`

The external gate driver is responsible for driving the actual power MOSFETs.

---

# V0.0.1 — Initial Functional RTL Baseline

This release represents the initial functional RTL implementation of JAGDIS-MC1.

It contains:

- RTL implementation
- Functional testbenches
- Simulation configuration
- Initial synthesis script/configuration

This is a **functional RTL milestone only**.

No synthesis results, timing closure, floorplanning, placement, routing, physical verification, layout, or GDS implementation are included in this version.

---

# 1. V1 System Requirements

| Parameter | V1 Value |
|---|---|
| System clock | 50 MHz |
| Clock period | 20 ns |
| PWM frequency | 40 kHz |
| PWM frequency range | 20–50 kHz future-capable |
| PWM style | Edge-aligned |
| Duty input | 10-bit `DUTY[9:0]` |
| Duty range | `0–1023 = 0–100%` |
| PWM counter | 11-bit |
| PWM counter range @ 40 kHz | `0–1249` |
| Duty update | Shadow → active at PWM rising edge |
| Nominal dead time | 500 ns |
| Dead-time range | 200 ns–1 µs |
| Dead-time resolution | 20 ns |
| Hall commutation | 6-step |
| Hall inputs | `HALL_A`, `HALL_B`, `HALL_C` |
| Direction | Forward / Reverse |
| Hall grace period | 1 PWM cycle |
| Normal commutation update | Next PWM rising edge |
| Fault response | Immediate gate OFF |
| Fault state | Latched |
| Fault clearing | RESET |
| Startup | Gates OFF until valid Hall + PWM boundary |

---

# 2. Hall Commutation

The valid Hall states are:

```text
001
101
100
110
010
011
```

The frozen forward sequence is:

```text
001 → 101 → 100 → 110 → 010 → 011 → 001
```

Reverse direction traverses the same sequence backwards:

```text
001 → 011 → 010 → 110 → 100 → 101 → 001
```

The invalid Hall states are:

```text
000
111
```

Illegal Hall transitions are also detected.

A one-PWM-cycle grace period is provided for invalid Hall behavior before a Hall fault is latched.

---

# 3. Hall-to-Phase Gate Mapping

The six gate command bits are ordered as:

```text
phase_cmd = {AH, AL, BH, BL, CH, CL}
```

The V1 commutation table is:

| Hall | Phase Command | Active Devices |
|---|---|---|
| `001` | `100100` | A+ B− |
| `101` | `100001` | A+ C− |
| `100` | `001001` | B+ C− |
| `110` | `011000` | B+ A− |
| `010` | `010010` | C+ A− |
| `011` | `000110` | C+ B− |

For every valid commutation state:

- One high-side device is selected.
- One low-side device is selected.
- The third phase is undriven.

The Hall lookup table itself is independent of `DIR`; direction determines which Hall transitions are considered valid.

---

# 4. PWM Architecture

JAGDIS-MC1 V1 uses a fixed external PWM frequency of:

```text
40 kHz
```

with a 50 MHz system clock.

Therefore:

```text
50 MHz / 40 kHz = 1250 clock cycles
```

The PWM counter runs:

```text
0 → 1 → 2 → ... → 1248 → 1249 → 0
```

The PWM boundary occurs at:

```text
counter = 1249
```

The PWM is edge-aligned.

PWM output is generated using:

```text
pwm_raw = (pwm_counter < compare_value)
```

---

# 5. Duty-Cycle Handling

The external MCU provides:

```text
DUTY[9:0]
```

with:

```text
0    → 0%
1023 → 100%
```

The duty input is first captured into a shadow register.

The active duty value changes only at a PWM boundary.

Conceptually:

```text
DUTY change
     ↓
duty_shadow
     ↓
PWM boundary
     ↓
duty_active
     ↓
compare_value
     ↓
new PWM period
```

The compare value is calculated as:

```text
compare_value =
    floor((duty_active × PWM_PERIOD_CLKS) / 1023)
```

For the V1 40-kHz configuration:

```text
PWM_PERIOD_CLKS = 1250
```

Therefore:

```text
DUTY = 0
    → compare = 0

DUTY = 512
    → compare = 625

DUTY = 1023
    → compare = 1250
```

---

# 6. PWM Frequency Parameterization

The V1 external interface does **not** contain a PWM-frequency configuration input.

V1 therefore uses:

```text
40 kHz fixed PWM frequency
```

Internally, the PWM period is parameterized where practical:

```verilog
parameter PWM_PERIOD_CLKS = 11'd1250
```

This allows future variants to support different PWM frequencies without increasing the external MCU pin count.

For example, with a 50 MHz system clock:

```text
1250 clocks → 40 kHz
1000 clocks → 50 kHz
2500 clocks → 20 kHz
```

---

# 7. Gate Drive Strategy

JAGDIS-MC1 does not directly drive the power MOSFETs.

The ASIC produces six logic-level gate commands for an external 3-phase gate driver.

The gate controller uses the following V1 strategy:

```text
High-side selected device → PWM controlled
Low-side selected device  → continuously requested ON
```

For example, for:

```text
Hall = 001
```

the command is:

```text
A+ B-
```

so:

```text
AH → PWM
BL → continuously ON
```

while:

```text
AL = 0
BH = 0
CH = 0
CL = 0
```

---

# 8. Dead Time

Dead time is implemented independently for each phase.

Each phase contains a `gate_phase` interlock.

Dead time is inserted only when the same phase changes between complementary devices:

```text
High → Low
```

or:

```text
Low → High
```

The V1 nominal value is:

```text
500 ns
```

At 50 MHz:

```text
500 ns / 20 ns = 25 clock cycles
```

Therefore:

```text
DEAD_TIME_CLKS = 25
```

The supported V1 architectural range is:

```text
200 ns → 10 clocks
500 ns → 25 clocks
1 µs   → 50 clocks
```

During dead time:

```text
gate_high = 0
gate_low  = 0
```

The latest request present at the end of dead time is used.

An illegal simultaneous high/low request is handled fail-safe by forcing both outputs OFF.

---

# 9. Commutation Timing

Hall transitions are synchronized before being processed.

The normal commutation sequence is:

```text
Hall transition
      ↓
2-FF synchronization
      ↓
Hall validation
      ↓
pending Hall state
      ↓
next PWM boundary
      ↓
hall_active changes
      ↓
phase command changes
```

Therefore a valid Hall transition does not directly change the active commutation command in the middle of a PWM period.

If another valid Hall state is observed before the PWM boundary, the latest valid candidate is intended to replace the previous pending candidate.

---

# 10. Startup

After reset, the controller begins in:

```text
IDLE
```

When `ENABLE` is asserted:

```text
IDLE
 ↓
STARTUP
```

The controller remains in STARTUP until a valid Hall state is available and a PWM boundary occurs.

Only then does the controller enter:

```text
RUN
```

The intended startup behavior is therefore:

```text
RESET
 ↓
Gates OFF
 ↓
ENABLE
 ↓
STARTUP
 ↓
Valid Hall
 ↓
PWM boundary
 ↓
RUN
 ↓
Gate drive enabled
```

---

# 11. Brake

V1 brake behavior is defined as:

```text
BRAKE → all six gates OFF
```

The controller enters:

```text
BRAKE
```

when `BRAKE` is asserted.

When brake is released, the controller does not immediately resume drive.

Instead:

```text
BRAKE
 ↓
STARTUP
 ↓
valid Hall + PWM boundary
 ↓
RUN
```

This ensures the motor controller re-establishes a valid startup/commutation condition before driving the MOSFETs again.

---

# 12. Fault Architecture

The fault inputs are:

```text
OC_FAULT
UV_FAULT
OT_FAULT
```

The Hall commutation block can also generate:

```text
hall_fault
```

These are combined into:

```text
fault_condition =
    OC_FAULT |
    UV_FAULT |
    OT_FAULT |
    hall_fault
```

The fault state is latched.

Conceptually:

```text
Fault condition
      ↓
Immediate gate shutdown
      +
Fault latch
      ↓
FAULT state
      ↓
RESET required
```

The external fault inputs therefore have two paths:

```text
Fault input
    │
    ├──────────────► Immediate gate OFF
    │
    └──────────────► Fault latch / FSM
```

The immediate gate shutdown does not wait for a clock.

The latched FAULT state remains active until RESET.

---

# 13. Reset Architecture

`RESET_N` is active-low.

Reset assertion is asynchronous.

Reset deassertion is conditioned through a two-flip-flop release synchronizer.

Conceptually:

```text
RESET_N
   ↓
2-FF reset release synchronizer
   ↓
reset_n_sync
   ↓
functional RTL
```

The physical gate outputs additionally use the raw external reset:

```text
Gate output = normal gate
            & RESET_N
            & ~fault_condition
            & ~fault_latched
```

Therefore external reset immediately forces all six physical gate outputs LOW.

---

# 14. RTL Architecture

The current RTL consists of the following modules:

```text
src/
├── jagdis_top.v
├── reset_sync.v
├── pwm_generator.v
├── hall_commutation.v
├── gate_controller.v
├── gate_phase.v
├── fault_manager.v
└── control_fsm.v
```

### `jagdis_top.v`

Top-level integration of the complete JAGDIS-MC1 controller.

### `reset_sync.v`

Provides asynchronous reset assertion and synchronized reset release.

### `pwm_generator.v`

Generates the edge-aligned PWM carrier, manages duty shadow/active registers, and calculates the PWM compare value.

### `hall_commutation.v`

Synchronizes Hall inputs, validates Hall states and transitions, manages pending commutation states, and generates the six-step phase command.

### `gate_controller.v`

Converts the phase command and PWM signal into high-side and low-side requests for the three motor phases.

### `gate_phase.v`

Provides per-phase complementary-device interlocking and programmable dead time.

### `fault_manager.v`

Combines external and Hall fault conditions and provides a latched fault state.

### `control_fsm.v`

Implements the controller operating states:

```text
IDLE
STARTUP
RUN
BRAKE
FAULT
```

---

# 15. External Interface

The V1 external interface is:

## Inputs

```text
CLK
RESET_N

HALL_A
HALL_B
HALL_C

DUTY[9:0]

ENABLE
DIR
BRAKE

OC_FAULT
UV_FAULT
OT_FAULT
```

## Outputs

```text
GH_A
GL_A

GH_B
GL_B

GH_C
GL_C

RUN
FAULT
```

No external PWM-frequency configuration pins are used in V1.

---

# 16. External Motor-Control Hardware

JAGDIS-MC1 is intended to form the digital control portion of a larger BLDC motor-control unit.

The PCB/system requires, at minimum:

```text
                 ┌────────────────────┐
MCU ────────────►│                    │
                 │    JAGDIS-MC1      │
Hall sensors ──►│                    │
Fault signals ─►│                    │
                 │                    │
                 └─────────┬──────────┘
                           │
                    6 logic gate commands
                           │
                           ▼
                 ┌────────────────────┐
                 │ 3-Phase Gate       │
                 │ Driver             │
                 └─────────┬──────────┘
                           │
                    MOSFET gate drive
                           │
                           ▼
                 ┌────────────────────┐
                 │ 3-Phase MOSFET     │
                 │ Power Stage        │
                 └─────────┬──────────┘
                           │
                           ▼
                       BLDC Motor
```

The external gate driver handles the power-stage gate-drive requirements.

JAGDIS-MC1 remains a digital control ASIC and does not directly drive the power MOSFET gates.

---

# 17. Verification

The project includes self-checking simulation testbenches under:

```text
testbench/
```

## Full Verification

```text
testbench/jagdis_top_full_tb.v
```

The full testbench verifies:

- Reset behavior
- Forward six-step commutation
- Reverse direction
- Hall state validation
- PWM-boundary commutation
- Duty shadow/active transfer
- 0% duty
- 50% duty
- 100% duty
- PWM high-time scaling
- Brake behavior
- External over-current fault
- External under-voltage fault
- External over-temperature fault
- Fault latching
- Invalid Hall grace period
- Reverse Hall transitions
- Same-phase dead-time interlock

The V0.0.1 baseline full functional testbench passes:

```text
PASS: JAGDIS full RTL verification
```

---

# 18. Verification Status

V0.0.1 is a **functional RTL baseline**.

The current verification establishes the intended baseline behavior of the implemented RTL.

Further regression tests will be added as RTL development continues, particularly around:

- Multiple Hall transitions within one PWM period
- Latest-pending-Hall behavior
- Brake → STARTUP → RUN
- ENABLE disable/re-enable
- Fault persistence after fault-input removal
- Exact dead-time boundary behavior
- Duty changes close to PWM boundaries

---

# 19. Implementation Status

| Development Stage | Status |
|---|---|
| System requirements | Complete |
| System architecture | Complete |
| RTL architecture | Complete |
| RTL implementation | Initial baseline |
| Functional verification | Passing |
| Synthesis | Not yet completed |
| Static timing analysis | Not yet completed |
| Timing closure | Not yet completed |
| Floorplanning | Not yet completed |
| Placement | Not yet completed |
| Clock-tree synthesis | Not yet completed |
| Routing | Not yet completed |
| Physical verification | Not yet completed |
| Layout | Not yet completed |
| GDS generation | Not yet completed |

---

# 20. Development Philosophy

JAGDIS-MC1 is being developed incrementally from:

```text
System Architecture
        ↓
RTL Architecture
        ↓
Functional RTL
        ↓
Functional Verification
        ↓
Synthesis
        ↓
Timing Analysis
        ↓
Physical Design
        ↓
Layout
        ↓
GDS
```

System-level decisions are treated as frozen requirements once established.

RTL implementation details may be changed when necessary to satisfy those requirements or when implementation analysis demonstrates that an existing approach is unsuitable.

System-level decisions should not be changed merely for convenience during RTL implementation.

---

# 21. Version History

## v0.0.1 — Initial Functional RTL Baseline

Initial functional RTL implementation and verification baseline.

Contains:

- JAGDIS-MC1 V1 RTL
- Six-step Hall commutation
- 40-kHz PWM generation
- 10-bit duty control
- Forward/reverse direction handling
- PWM-boundary duty and commutation updates
- 500-ns nominal dead time
- Brake/coast gate-off behavior
- Latched fault handling
- Immediate external-fault gate shutdown
- Functional testbenches

This version is preserved as the baseline snapshot for subsequent RTL refinement.

---

# Project Status

**Current milestone: V0.0.1 — Functional RTL baseline**

**Next milestone: RTL correction and expanded functional regression**

No physical implementation has been performed yet.