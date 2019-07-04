/*********************************************************************
Licensing stuff
*********************************************************************/
#include <stdio.h>
#include "cpu/keccak.h"

int main()
{
        KECCAK_CTX ctx;
        keccak_sha3_init(&ctx, 256);
        uint32_t inlen = 32;
        uint8_t in[32] = {0xcd, 0x78, 0x17, 0xb7, 0x24, 0xda, 0xd0, 0x58, 0x52, 0xf1, 0x53, 0xf3, 0x57, 0x03, 0xf6, 0x5c, 0x35, 0x29, 0xe5, 0x63, 0x94, 0x90, 0x11, 0x0a, 0xf5, 0x0a, 0xf5, 0x8a, 0xf4, 0x72, 0x25, 0x0b};
        keccak_update(&ctx, in, inlen);
        uint8_t in2[4] = {0,0,0,0};
        keccak_update(&ctx, in2, 4);

        uint8_t out[32];
        keccak_final(&ctx, out);

        printf("Out: ");
        for (int i = 0; i < 32; i++) {
                printf("%02x ", out[i]);
        }
		printf("\n");

		uint64_t a = 0x1111222344512345;
		uint64_t b = keccak_ROTL64(a, 5);
		printf("ROTL64(0x%llx, 5) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 10);
		printf("ROTL64(0x%llx, 10) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 15);
		printf("ROTL64(0x%llx, 15) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 20);
		printf("ROTL64(0x%llx, 20) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 25);
		printf("ROTL64(0x%llx, 25) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 30);
		printf("ROTL64(0x%llx, 30) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 32);
		printf("ROTL64(0x%llx, 32) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 48);
		printf("ROTL64(0x%llx, 48) = 0x%llx\n", a, b);
		b = keccak_ROTL64(a, 56);
		printf("ROTL64(0x%llx, 56) = 0x%llx\n", a, b);

    return 0;
}

