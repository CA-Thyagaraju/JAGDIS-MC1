# JAGDIS-MC1 RTL

Plain Verilog-2001 implementation of the frozen Step 2A–2J architecture.

## File hierarchy

```text
jagdis_top.v
├── reset_sync.v          asynchronous assertion / synchronous release
├── pwm_generator.v       40 kHz counter PWM and duty shadow register
├── fault_manager.v       external/Hall fault OR, latch, and status
├── control_fsm.v         IDLE / STARTUP / RUN / BRAKE / FAULT
├── hall_commutation.v    Hall synchronizers, validation, and phase command
└── gate_controller.v     three same-phase dead-time interlocks
    └── gate_phase.v
```

`jagdis_top` is the synthesis top.  The only ownership of the six normal gate
commands is `gate_controller`; `jagdis_top` adds the required asynchronous
reset and fault output override.

The source is deliberately Verilog-2001: no `logic`, `always_ff`, `enum`, or
other SystemVerilog constructs are used.
