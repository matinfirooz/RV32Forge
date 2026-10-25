# Contributing

Run `make test` for changes to the core, decoder, arithmetic, assembler, or model. Run `make lint` for RTL changes and `make synth` when changing resource structure. Preserve failing seed/program artifacts when reporting a bug.

Add a small directed program for a discovered architectural failure and retain at least one fixed expected signature or known encoding when practical. Avoid relying only on final memory: intermediate register and wrong-path failures can otherwise escape detection.

Use `results/regression.json` and `results/synthesis.json` as machine-readable evidence. Regenerate plots with `make plots` after the reports change. Distinguish cycle counts, generic logic counts, mapped area, and physical timing/power in every claim.

Keep simulation-only code in the SoC/testbench layer. The core's current memory ports assume combinational responses; a bus or cache change must explicitly design and verify response latency, stalls, and store acceptance.
