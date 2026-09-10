# Verification

RV32Forge includes three directed SystemVerilog tests.

## Base pipeline test

Exercises:

- EX/MEM and MEM/WB forwarding,
- load-use stall,
- stores and loads,
- BNE,
- JAL/JALR,
- pipeline recovery.

Expected memory signature:

```text
0x100 = 55
0x104 = 110
0x108 = 1
0x10C = 165
```

## RV32M test

Exercises positive and signed multiplication, division and remainder. Expected signature starts at `0x180`.

## Predictor benchmark

Computes the sum `1 + ... + 40 = 820` in a loop. The branch is taken repeatedly and not-taken once, which makes it a useful directed test of the 2-bit predictor.

The test asserts:

- the loop result is correct,
- the branch counter increments,
- mispredictions are fewer than resolved branches.

## Commands

```bash
make sim
make sim-m
make sim-branch
make sim-all
```
