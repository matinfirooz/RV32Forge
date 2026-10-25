# Signed INT8 dot product: 16 pairs, result stored at 0x300.
li t0,0xf80c07fd
sw t0,512(zero)
li t0,0x09f00401
sw t0,516(zero)
li t0,0x0306fe05
sw t0,520(zero)
li t0,0xff08fb0a
sw t0,524(zero)
li t0,0x0603fe04
sw t0,544(zero)
li t0,0xfd0102f9
sw t0,548(zero)
li t0,0x07fc0508
sw t0,552(zero)
li t0,0x0bfa0902
sw t0,556(zero)
li a0,512
li a1,544
li a2,16
li a3,0
dot_loop:
lb t0,0(a0)
lb t1,0(a1)
mul t2,t0,t1
add a3,a3,t2
addi a0,a0,1
addi a1,a1,1
addi a2,a2,-1
bne a2,zero,dot_loop
sw a3,768(zero)
ecall
