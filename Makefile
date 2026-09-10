PYTHON ?= python3
CC ?= gcc
IVERILOG ?= iverilog
VVP ?= vvp

RTL = rtl/alu.sv rtl/regfile.sv rtl/imm_gen.sv rtl/muldiv_unit.sv rtl/branch_predictor.sv rtl/rv32_core.sv rtl/rv32_soc.sv

.PHONY: all asm test-c test-ref sim sim-m sim-branch sim-all clean

all: asm test-c test-ref

asm:
	$(PYTHON) tools/mini_rv32_asm.py programs/demo.s programs/demo.hex
	$(PYTHON) tools/mini_rv32_asm.py programs/rv32m_demo.s programs/rv32m_demo.hex
	$(PYTHON) tools/mini_rv32_asm.py programs/branch_bench.s programs/branch_bench.hex

test-c:
	$(CC) -O2 -Wall -Wextra sw/golden.c -o /tmp/rv32forge_golden
	/tmp/rv32forge_golden
	$(CC) -O2 -Wall -Wextra sw/golden_rv32m.c -o /tmp/rv32m_golden
	/tmp/rv32m_golden

test-ref: asm
	$(PYTHON) tools/rv32im_ref.py programs/demo.hex
	$(PYTHON) tools/rv32im_ref.py programs/rv32m_demo.hex
	$(PYTHON) tools/rv32im_ref.py programs/branch_bench.hex

sim: asm
	$(IVERILOG) -g2012 -Wall -s tb_rv32_soc -o rv32forge_sim $(RTL) tb/tb_rv32_soc.sv
	$(VVP) rv32forge_sim

sim-m: asm
	$(IVERILOG) -g2012 -Wall -s tb_rv32m -o rv32m_sim $(RTL) tb/tb_rv32m.sv
	$(VVP) rv32m_sim

sim-branch: asm
	$(IVERILOG) -g2012 -Wall -s tb_branch_predictor -o branch_sim $(RTL) tb/tb_branch_predictor.sv
	$(VVP) branch_sim

sim-all: sim sim-m sim-branch

clean:
	rm -f rv32forge_sim rv32m_sim branch_sim *.vcd
