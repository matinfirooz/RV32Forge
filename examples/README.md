# Captured execution example

`divider_dependencies.s`, `divider.trace`, `divider_reference.jsonl`, and `divider.vcd` come from the passing `iterative_dynamic` regression. They exercise load-to-DIV forwarding, signed overflow, zero divisors, dependent arithmetic, stores, and a normal 32-step divide.

Open `divider.vcd` in GTKWave, or inspect `../docs/assets/execution.svg`. Trace columns are documented in `../docs/interfaces.md`. Regenerate the example with `make regression`; per-program outputs remain under `build/regression/`.
