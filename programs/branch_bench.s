# Loop-heavy branch predictor demo. Results at 0x1c0.
    li   x10, 448
    li   x1, 0
    li   x2, 40
    li   x3, 0
loop:
    addi x1, x1, 1
    add  x3, x3, x1
    blt  x1, x2, loop
    sw   x3, 0(x10)      # sum 1..40 = 820
    ecall
