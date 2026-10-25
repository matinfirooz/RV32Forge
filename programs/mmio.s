# Executed by tb_mmio, since cycle counters are timing dependent.
li s0,0x10000000
lw a0,16(s0)
nop # isolate counter reads from load-use bubbles
sw a0,256(zero)
lw a1,20(s0)
nop # isolate counter reads from load-use bubbles
sw a1,260(zero)
lw a2,24(s0)
nop # isolate counter reads from load-use bubbles
sw a2,264(zero)
li t0,100
li t1,7
div t2,t0,t1
lw a3,36(s0)
nop # isolate counter reads from load-use bubbles
sw a3,268(zero)
sw t2,272(zero)
lw t3,272(zero)
add t4,t3,t3
lw a4,24(s0)
nop # isolate counter reads from load-use bubbles
sw a4,276(zero)
# Writes to read-only counters must have no effect.
li t0,-1
sw t0,16(s0)
lw a5,16(s0)
nop # isolate counter reads from load-use bubbles
sw a5,280(zero)
# Exercise a nonzero upper byte of the cycle counter through an unaligned
# byte address within the aligned MMIO word. This must select bits 15:8.
li t0,130
counter_loop:
addi t0,t0,-1
bne t0,zero,counter_loop
lbu a6,17(s0)
sw a6,284(zero)
lhu a7,16(s0)
sw a7,288(zero)
lw t1,28(s0)
sw t1,292(zero)
lw t2,32(s0)
sw t2,296(zero)
ecall
