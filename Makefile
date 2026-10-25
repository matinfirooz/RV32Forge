PYTHON ?= python3
CC ?= gcc
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys
SEEDS ?= 12
LENGTH ?= 180

RTL := $(sort $(wildcard rtl/*.sv))
CORE_RTL := $(filter-out rtl/rv32_soc.sv,$(RTL))
PROGRAMS := $(patsubst %.s,%.hex,$(wildcard programs/*.s))
BUILD := build

.PHONY: all help asm test test-tools test-c test-ref smoke sim sim-m sim-branch sim-mmio sim-all regression quick lint synth plots check clean
all: test

help:
	@$(PYTHON) -c "print('RV32Forge: make test | quick | regression | lint | synth | plots | check\nSee README.md for tool requirements and Windows/WSL setup.')"

asm: $(PROGRAMS)
programs/%.hex: programs/%.s tools/mini_rv32_asm.py
	$(PYTHON) tools/mini_rv32_asm.py $< $@

$(BUILD)/logs $(BUILD)/waves:
	mkdir -p $@

test-tools:
	$(PYTHON) -m unittest discover -s tests -v

test-c: | $(BUILD)/logs
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror sw/golden.c -o $(BUILD)/golden
	$(BUILD)/golden
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror sw/golden_rv32m.c -o $(BUILD)/golden_rv32m
	$(BUILD)/golden_rv32m

test-ref: asm
	$(PYTHON) tools/rv32im_ref.py programs/demo.hex
	$(PYTHON) tools/rv32im_ref.py programs/rv32m_demo.hex
	$(PYTHON) tools/rv32im_ref.py programs/branch_bench.hex
	$(PYTHON) tools/rv32im_ref.py programs/dot_product.hex

$(BUILD)/tb_%: tb/tb_%.sv $(RTL) | $(BUILD)/logs $(BUILD)/waves
	$(IVERILOG) -g2012 -s tb_$* -o $@ $(RTL) $< 2>$(BUILD)/logs/tb_$*.compile.log || { cat $(BUILD)/logs/tb_$*.compile.log; exit 1; }

sim: asm $(BUILD)/tb_rv32_soc
	$(VVP) $(BUILD)/tb_rv32_soc
sim-m: asm $(BUILD)/tb_rv32m
	$(VVP) $(BUILD)/tb_rv32m
sim-branch: asm $(BUILD)/tb_branch_predictor
	$(VVP) $(BUILD)/tb_branch_predictor
sim-mmio: asm $(BUILD)/tb_mmio
	$(VVP) $(BUILD)/tb_mmio
sim-all smoke: sim sim-m sim-branch sim-mmio

regression: asm
	IVERILOG="$(IVERILOG)" VVP="$(VVP)" $(PYTHON) tools/regress.py --seeds $(SEEDS) --length $(LENGTH) --wave

quick: test-tools asm smoke

test: test-tools test-c test-ref smoke regression

lint:
	$(VERILATOR) --lint-only -Wall --unroll-count 512 -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module rv32_core $(CORE_RTL)
	$(VERILATOR) --lint-only -Wall --unroll-count 512 -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module rv32_core -GITERATIVE_DIV=0 $(CORE_RTL)

synth:
	YOSYS="$(YOSYS)" $(PYTHON) tools/synthesize.py

plots:
	$(PYTHON) tools/plot_results.py

check: test lint synth

clean:
	rm -rf $(BUILD)
