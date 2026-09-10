#include <stdint.h>
#include <stdio.h>

static uint32_t high_ss(int32_t a, int32_t b) {
    int64_t p = (int64_t)a * (int64_t)b;
    return (uint32_t)(((uint64_t)p) >> 32);
}
static uint32_t high_su(int32_t a, uint32_t b) {
    int64_t p = (int64_t)a * (int64_t)(uint64_t)b;
    return (uint32_t)(((uint64_t)p) >> 32);
}
static uint32_t high_uu(uint32_t a, uint32_t b) {
    uint64_t p = (uint64_t)a * (uint64_t)b;
    return (uint32_t)(p >> 32);
}

int main(void) {
    int32_t a = 21, b = 6, n = -7;
    uint32_t u = (uint32_t)n;
    uint32_t sig[8] = {
        (uint32_t)(a * b),
        high_ss(n, b),
        high_su(n, (uint32_t)b),
        high_uu(u, (uint32_t)b),
        (uint32_t)(a / b),
        u / (uint32_t)b,
        (uint32_t)(n % b),
        u % (uint32_t)b
    };
    const uint32_t expected[8] = {
        126u, 0xffffffffu, 0xffffffffu, 5u,
        3u, 715827881u, 0xffffffffu, 3u
    };
    for (int i = 0; i < 8; ++i) {
        printf("sig[%d] = 0x%08x (%u)\n", i, sig[i], sig[i]);
        if (sig[i] != expected[i]) return 1;
    }
    puts("RV32M golden PASS");
    return 0;
}
