# Complete RV32M directed test. Signatures start at 0x180.
    li   x10, 384
    li   x1, 21
    li   x2, 6
    li   x6, -7

    mul    x3, x1, x2     # 126
    sw     x3, 0(x10)

    mulh   x3, x6, x2     # high(-42) = -1
    sw     x3, 4(x10)

    mulhsu x3, x6, x2     # signed(-7) * unsigned(6), high = -1
    sw     x3, 8(x10)

    mulhu  x3, x6, x2     # unsigned(0xfffffff9) * 6, high = 5
    sw     x3, 12(x10)

    div    x4, x1, x2     # 3
    sw     x4, 16(x10)

    divu   x4, x6, x2     # 0xfffffff9 / 6 = 715827881
    sw     x4, 20(x10)

    rem    x5, x6, x2     # -1
    sw     x5, 24(x10)

    remu   x5, x6, x2     # 0xfffffff9 % 6 = 3
    sw     x5, 28(x10)

    ecall
