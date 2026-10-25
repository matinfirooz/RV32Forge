# Changelog

## 2.0 — 2026-10-25

### Correctness

- Made wrapper read responses word-aligned so the core selects subword lanes exactly once.
- Preserved reads of RAM's final byte and halfword; aligned counter reads use the same contract.
- Replaced EX-stage ECALL freezing with a terminal marker that drains through WB.
- Suppressed post-halt memory writes, register writes, predictor updates, and trace events.
- Rejected unsupported/reserved encodings and reported EBREAK and alignment faults as diagnostic halts.
- Excluded terminal markers from normal instruction-retirement counts.
- Reinitialized two-bit history when a BTB tag is replaced.

### Microarchitecture

- Added a request-latched, 32-step restoring divider and correct EX back-pressure.
- Shared one sign-extended multiplier among MUL/MULH/MULHSU/MULHU.
- Preserved selectable combinational division and static not-taken prediction for matched comparisons.
- Added configurable predictor capacity, a divider-stall counter/MMIO word, and ordered commit signals.

### Tools and evidence

- Rebuilt the mini assembler with source diagnostics, checked operands, full-width `li`, and standard U-immediate fields.
- Removed floating-point arithmetic from signed reference division/remainder.
- Added 19 Python tests, component/pipeline/reset/MMIO benches, and three-policy instruction-by-instruction differential regression.
- Added an INT8 dot-product workload, a dependent-divide workload, measured JSON/CSV results, matched Yosys synthesis, and CI artifacts.
- Replaced the old illustrative raster architecture images with precise editable SVGs and plots from actual runs.
- Added Windows/WSL setup, interface documentation, a captured trace/VCD, and reproducible figure scripts.

### Source compatibility

Named original core/SoC ports remain available. New output ports can be left unconnected in named instantiations. Positional instantiations and `.*` users need to account for new ports. The default divider is now multicycle, so tests must allow the added latency.

The mini assembler now interprets `lui` and `auipc` operands as 20-bit fields: use `lui a0,0x12345` for `0x12345000`. Existing included programs that did not use these instructions continue to assemble unchanged.
