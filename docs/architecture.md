# RV32Forge Microarchitecture

RV32Forge is an in-order **RV32IM** processor organized as a classic five-stage pipeline:

```text
IF -> ID -> EX -> MEM -> WB
```

## Front end

The fetch stage includes a 256-entry dynamic predictor. Each entry contains:

- a 2-bit saturating branch-history counter,
- a valid bit,
- a full PC tag,
- a branch target buffer (BTB) target.

A BTB hit whose counter is in a taken state redirects fetch speculatively. The prediction metadata travels through IF/ID and ID/EX. EX resolves the true branch/jump result and flushes younger instructions only when direction or target was wrong.

## Decode / register access

The decoder supports the RV32I integer subset used by the project plus the complete RV32M arithmetic group. The register file has 32 registers, with `x0` permanently zero.

A WB->ID bypass handles a value written back on the same cycle that decode reads it.

## Execute

The execute stage contains:

- integer ALU,
- RV32M multiply/divide datapath,
- branch comparator,
- jump-target generator,
- EX/MEM forwarding,
- MEM/WB forwarding.

The current RV32M unit is combinational for clarity. This is functionally useful for FPGA/ASIC exploration, but DIV/REM will create a long combinational path in synthesis. An iterative or pipelined divider is a natural next extension.

## Hazards

ALU dependencies are normally removed by forwarding. A true load-use dependency inserts a single bubble because memory data is not ready for the immediately following EX stage.

Control hazards are handled by speculative fetch plus EX-stage recovery.

## Memory stage

The core supports:

- LB / LBU
- LH / LHU
- LW
- SB
- SH
- SW

The SoC wrapper decodes RAM and a small memory-mapped I/O region.

## Memory map

| Address | Function |
|---|---|
| `0x0000_0000 ...` | data RAM |
| `0x1000_0000` | UART TX (write low byte) |
| `0x1000_0010` | cycle counter |
| `0x1000_0014` | retired-instruction counter |
| `0x1000_0018` | load-use stall counter |
| `0x1000_001C` | branch/jump resolution counter |
| `0x1000_0020` | misprediction counter |

## Performance counters

The core maintains:

```text
cycles
retired instructions
load-use stalls
resolved control transfers
branch mispredictions
```

These enable CPI and predictor-accuracy experiments without requiring waveform inspection.

## RV32M

Implemented operations:

```text
MUL MULH MULHSU MULHU
DIV DIVU REM REMU
```

RISC-V corner cases for division by zero and signed division overflow are handled explicitly.
