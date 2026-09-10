# RV32Forge directed pipeline test
#
# Expected signatures:
#   mem[0x100] = 55
#   mem[0x104] = 110
#   mem[0x108] = 1
#   mem[0x10c] = 165

    li   x1, 10
    li   x2, 20
    add  x3, x1, x2          # RAW forwarding: 30
    addi x4, x3, 25          # forwarding: 55

    li   x10, 256            # base = 0x100
    sw   x4, 0(x10)

    lw   x5, 0(x10)
    add  x6, x5, x5          # load-use hazard => one bubble
    sw   x6, 4(x10)          # 110

    li   x7, 110
    bne  x6, x7, fail
    li   x8, 1
    sw   x8, 8(x10)

    jal  x1, function
after_call:
    sw   x9, 12(x10)         # 165
    j    done

function:
    add  x9, x4, x6          # 55 + 110 = 165
    jalr x0, x1, 0

fail:
    li   x8, 0
    sw   x8, 8(x10)
    li   x9, -1
    sw   x9, 12(x10)

done:
    ecall
