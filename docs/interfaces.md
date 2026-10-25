# Interfaces and integration

## Core ports

`rv32_core` is synthesizable SystemVerilog. `rv32_soc` contains simulation arrays, program loading, and UART printing; synthesize the core directly unless replacing that wrapper.

| Port group | Contract |
|---|---|
| `clk`, `rst_n` | Rising-edge logic; asynchronous active-low reset |
| `imem_addr`, `imem_rdata` | Byte PC and combinational 32-bit instruction response |
| `dmem_re`, `dmem_we` | Valid memory actions from MEM; gated during reset and after halt |
| `dmem_addr` | Original byte effective address |
| `dmem_size` | 0 byte, 1 halfword, 2 word |
| `dmem_wdata` | Unshifted store data; low 8/16/32 bits are used |
| `dmem_rdata` | Aligned 32-bit word at `dmem_addr & ~3` |
| `halted` | High once the terminal marker reaches WB; sticky until reset |
| `faulted`, `fault_cause`, `fault_pc` | Diagnostic terminal status, cause, and source PC |
| `*_count` | 32-bit counters described in architecture.md |

There is no response-valid, back-pressure, access-error, or bus handshake on the memory ports. Do not attach variable-latency memory directly.

## Ordered debug trace

When `commit_valid=1` at a rising edge, one architectural event is reported:

| Signal | Meaning |
|---|---|
| `commit_pc`, `commit_instr` | Instruction PC and encoding |
| `commit_rd` | Destination register, or zero when there is no architectural register write |
| `commit_wdata` | Register value; canonical zero if `commit_rd=0` |
| `commit_mem_we` | This instruction is a store |
| `commit_mem_addr` | Effective byte address; meaningful for stores |
| `commit_mem_wdata` | Unshifted full register value; compare only the stored byte(s) |
| `commit_mem_size` | Store size encoding, as above |
| `commit_stop` | Final terminal event |
| `commit_fault`, `commit_cause` | Diagnostic fault status/cause for that event |

Non-store memory fields are unspecified and normalized to zero by the comparator. Stores take effect in MEM one cycle before their event reaches the trace; the in-order fault policy prevents a younger store from escaping a terminal instruction. The trace is an observation interface, not a bus or back-pressure mechanism.

The final ECALL event has `commit_stop=1`, `commit_fault=0`, no register write, and no store. It is excluded from `instret_count`. A fault event likewise has no register or memory side effect. No trace event occurs after halt.

`tb_regression.sv` writes one whitespace-delimited hexadecimal row per event:

```text
pc instr rd wdata mem_we mem_addr mem_wdata mem_size stop fault cause
```

`reference.jsonl` contains the corresponding model events as JSON objects. `rtl.state` contains 32 register words followed by 1,024 words of little-endian test RAM.

This trace is not RVFI and has not been checked with riscv-formal. It omits RVFI fields such as register source data, masks, and order metadata required by that specification.

## Divider handshake

`rv32_divider` accepts `start=1` when `busy=0`. It latches operands and signed/remainder modes. Requests while busy are ignored. `done` pulses for one cycle with the completed `result`; the result remains stable until a later completion or reset. A reset cancels the operation.

The core does not issue another request while `done` is high. An external client should use the same one-request/one-completion discipline and assert start for one acceptance edge.

## Program selection

The SoC loads `IMEM_HEX` by default. Simulation can override it with `+HEX=/path/program.hex`. Programs must fit `IMEM_WORDS`; the regression explicitly rejects oversized images. The SoC's `$readmemh` warning about a shorter image is harmless because remaining instruction locations were initialized to NOP.
