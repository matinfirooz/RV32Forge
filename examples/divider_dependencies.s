li a0,-2147483648
li a1,-1
sw a0,256(zero)
lw a2,256(zero)
div a3,a2,a1
add a4,a3,a3
rem a5,a0,a1
div a6,a0,zero
rem a7,a0,zero
divu t0,a0,zero
remu t1,a0,zero
li t2,7
div t3,a0,t2
rem t4,a0,t2
sw t3,260(zero)
div t3,t3,t2
sw t3,264(zero)
ecall
