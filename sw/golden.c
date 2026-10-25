#include <stdio.h>
#include <stdint.h>

int main(void) {
    int32_t x1 = 10;
    int32_t x2 = 20;
    int32_t x3 = x1 + x2;
    int32_t x4 = x3 + 25;
    int32_t mem100 = x4;
    int32_t x5 = mem100;
    int32_t x6 = x5 + x5;
    int32_t mem104 = x6;
    int32_t mem108 = (x6 == 110) ? 1 : 0;
    int32_t x9 = x4 + x6;
    int32_t mem10c = x9;

    printf("RV32Forge C golden model\n");
    printf("mem[0x100] = %d\n", mem100);
    printf("mem[0x104] = %d\n", mem104);
    printf("mem[0x108] = %d\n", mem108);
    printf("mem[0x10c] = %d\n", mem10c);

    if (mem100 != 55 || mem104 != 110 || mem108 != 1 || mem10c != 165) {
        puts("FAIL");
        return 1;
    }
    puts("PASS");
    return 0;
}
