# Verification

## Reproduce the recorded run

```bash
make test
make lint
make synth
```

Requirements are Python 3.9+ (3.10+ recommended), GCC, Make, Icarus Verilog, Verilator for lint, and Yosys for synthesis. Python simulation tools use the standard library. The checked-in results were produced with Icarus 12.0, Verilator 5.020, and Yosys 0.33.

The full functional run includes:

| Test | Scope |
|---|---|
| Python `unittest` | 19 methods: known instruction encodings, full-width constants, labels after pseudo expansion, source diagnostics, rejection paths, arithmetic identities, memory and fault model behavior |
| `tb_rv32_soc` | Original hazard, forwarding, jump, and memory-signature demo |
| `tb_rv32m` | All eight M-extension instruction signatures |
| `tb_branch_predictor` | The 40-iteration sum and predictor learning |
| `tb_divider` | 2,048 vectors; signed/unsigned quotient/remainder, edge operands, deterministic random operands, altered inputs while busy, ignored busy requests, pulse timing, reset abort |
| `tb_muldiv_unit` | 4,096 vectors over all eight operations, including high-product signedness |
| `tb_predictor_unit` | Reset, saturation, full-tag alias rejection, fresh history on replacement, target changes |
| `tb_mmio` | Cycle/retirement/load-stall/divider-stall counter loads and read-only behavior |
| `tb_reset` | Reset during an in-flight divide, fresh restart, no stale completion/store |
| `tb_regression` + Python comparator | 111 runs, 13,863 instruction events across three policies, final register and full test-RAM equality |

The 512 arithmetic operand pairs consist of an 8×8 edge grid and 448 seeded random pairs. Four divider modes give 2,048 divider vectors; all eight RV32M operations give 4,096 combinational unit vectors.

## Differential regression

```bash
python3 tools/regress.py --seeds 12 --length 180 --seed 42 --wave
```

Thirty-seven programs run in each configuration: `iterative_dynamic`, `iterative_static`, and `combinational_dynamic`. The harness uses a 64-entry predictor, 4 KiB data RAM, 4,096 instruction words, a three-edge reset, and a 100,000-cycle watchdog. The 12 generated programs use seeds 42–53 and 180 generated operation groups each; a group can emit several instructions.

Each program is assembled, executed by the Python model, and simulated in RTL. The comparator checks every event's PC, instruction, register result, stored address/data/size, terminal flag, fault flag, and cause. It also compares all 32 registers and all 4 KiB of RAM. Known signatures for the original demos and signed INT8 dot product independently anchor selected reference results.

The SystemVerilog harness checks x0, exact retirement-counter agreement, one store action per committed store, timeout, and no trace/store/counter activity after halt. Directed cases include every byte lane, both naturally aligned halfword lanes, RAM's final byte/halfword, signed extension, forwarding priority, load-to-store dependencies, zero-register dependencies, dependent divides, zero divisors, signed overflow, changing JALR targets, wrong-path terminal instructions/stores, illegal opcode/function/shift/CSR encodings, EBREAK, and taken versus untaken misaligned branches.

Counter-MMIO data is timing dependent and is tested separately by `tb_mmio`, rather than assigned fabricated values by the architectural model. The model does support UART store effects; it does not predict cycle counters.

## Failure investigation

Failed commands return nonzero. The failing program's assembly, image, trace, reference, state dump, and simulation log remain in:

```text
build/regression/<configuration>_cases/<program>/
```

A mismatch reports the first differing instruction and fields. Increase the seed range, reduce `--length`, or rerun a particular configuration:

```bash
python3 tools/regress.py --configs iterative_dynamic --seed 100 --seeds 1 --length 120 --wave
```

`--skip-units` skips only the component benches for a targeted follow-up; default and CI runs include them. `IVERILOG` and `VVP` environment variables can override executable paths.

CI runs the functional suite, both lint configurations, and both generic synthesis configurations. It uploads results and build evidence even when a check fails.

## What the evidence does not establish

This is directed and seeded random simulation against a project-specific model. It is not exhaustive ISA coverage, an official architectural-test result, RVFI validation, or formal equivalence. Some assembler/model errors could be shared; known encoding and signature tests reduce that risk without eliminating it. More seeds and official ISA tests would be useful extensions.

The testbench clock is a simulation stimulus, not an achieved operating frequency. Generic synthesis checks logic elaboration/mapping and structural consistency; it does not establish physical area, timing closure, power, or FPGA utilization. The simulation SoC uses combinational memories, and variable memory latency remains unimplemented.
