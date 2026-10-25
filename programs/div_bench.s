# Dependent divides illustrate the area/throughput tradeoff.
li a0,0x7fffffff
li a1,3
li a2,20
li a3,0
loop:
div a0,a0,a1
rem t0,a0,a1
add a3,a3,t0
addi a2,a2,-1
bne a2,zero,loop
sw a0,768(zero)
sw a3,772(zero)
ecall
