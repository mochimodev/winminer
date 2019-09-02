
#pragma OPENCL EXTENSION cl_khr_byte_addressable_store : enable

typedef uchar uint8_t;
typedef int int32_t;
typedef uint uint32_t;
typedef long int64_t;
typedef ulong uint64_t;
typedef uchar BYTE;             // 8-bit byte
typedef uint  WORD;             // 32-bit word, change to "long" for 16-bit machines
#define memcpy(dst,src,size); { for (int mi = 0; mi < size; mi++) { ((uint8_t*)dst)[mi] = ((uint8_t*)src)[mi]; } }

#define BLAKE2B_ROUNDS 12
#define BLAKE2B_BLOCK_LENGTH 128
#define BLAKE2B_CHAIN_SIZE 8
#define BLAKE2B_CHAIN_LENGTH (BLAKE2B_CHAIN_SIZE * sizeof(int64_t))
#define BLAKE2B_STATE_SIZE 16
#define BLAKE2B_STATE_LENGTH (BLAKE2B_STATE_SIZE * sizeof(int64_t))
typedef struct {
    WORD digestlen;
    BYTE key[64];
    WORD keylen;

    BYTE buff[BLAKE2B_BLOCK_LENGTH];
    uint64_t chain[BLAKE2B_CHAIN_SIZE];
    uint64_t state[BLAKE2B_STATE_SIZE];

    WORD pos;
    uint64_t t0;
    uint64_t t1;
    uint64_t f0;
} cl_blake2b_ctx_t;

#if 0
#include <assert.h>
#include <stdint.h>
extern "C"
{
#include "blake2b.cuh"
}
#endif

#define BLAKE2B_IVS_0 0x6a09e667f3bcc908
#define BLAKE2B_IVS_1 0xbb67ae8584caa73b
#define BLAKE2B_IVS_2 0x3c6ef372fe94f82b
#define BLAKE2B_IVS_3 0xa54ff53a5f1d36f1
#define BLAKE2B_IVS_4 0x510e527fade682d1
#define BLAKE2B_IVS_5 0x9b05688c2b3e6c1f
#define BLAKE2B_IVS_6 0x1f83d9abfb41bd6b
#define BLAKE2B_IVS_7 0x5be0cd19137e2179


__constant unsigned char BLAKE2B_SIGMAS[12][16] =
{
        { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
        { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
        { 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
        { 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
        { 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
        { 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 },
        { 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 },
        { 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 },
        { 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 },
        { 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 },
        { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
        { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 }
};

#if 0
uint64_t cl_blake2b_leuint64(BYTE *in)
{
    uint64_t a;
    //memcpy(&a, in, 8);
    for (int i = 0; i < 8; i++) {
	    ((uint8_t*)&a)[i] = in[i];
    }
    return a;
}
#endif

#define cl_blake2b_leuint64(in) ((uint64_t*)(in))[0]
#define cl_blake2b_ROTR64(a, b) (((a) >> (b)) | ((a) << (64 - (b))))

void cl_blake2b_G(cl_blake2b_ctx_t *ctx, int64_t m1, int64_t m2, int32_t a, int32_t b, int32_t c, int32_t d)
{
    uint64_t *state = ctx->state;
    state[a] = state[a] + state[b] + m1;
    state[d] = cl_blake2b_ROTR64(state[d] ^ state[a], 32);
    state[c] = state[c] + state[d];
    state[b] = cl_blake2b_ROTR64(state[b] ^ state[c], 24);
    state[a] = state[a] + state[b] + m2;
    state[d] = cl_blake2b_ROTR64(state[d] ^ state[a], 16);
    state[c] = state[c] + state[d];
    state[b] = cl_blake2b_ROTR64(state[b] ^ state[c], 63);
}

inline void cl_blake2b_init_state(cl_blake2b_ctx_t *ctx)
{
    uint64_t *state = ctx->state;
    memcpy(state, ctx->chain, BLAKE2B_CHAIN_LENGTH);
    state[BLAKE2B_CHAIN_SIZE + 0] = BLAKE2B_IVS_0;
    state[BLAKE2B_CHAIN_SIZE + 1] = BLAKE2B_IVS_1;
    state[BLAKE2B_CHAIN_SIZE + 2] = BLAKE2B_IVS_2;
    state[BLAKE2B_CHAIN_SIZE + 3] = BLAKE2B_IVS_3;

    state[12] = ctx->t0 ^ BLAKE2B_IVS_4;
    state[13] = ctx->t1 ^ BLAKE2B_IVS_5;
    state[14] = ctx->f0 ^ BLAKE2B_IVS_6;
    state[15] = BLAKE2B_IVS_7;
}

inline void cl_blake2b_compress(cl_blake2b_ctx_t *ctx, BYTE* in, WORD inoffset)
{
    cl_blake2b_init_state(ctx);

    uint64_t  m[16] = {0};
    for (int j = 0; j < 16; j++) {
        m[j] = cl_blake2b_leuint64(in + inoffset + (j << 3));
    }

    for (int round = 0; round < BLAKE2B_ROUNDS; round++)
    {
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][0]], m[BLAKE2B_SIGMAS[round][1]], 0, 4, 8, 12);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][2]], m[BLAKE2B_SIGMAS[round][3]], 1, 5, 9, 13);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][4]], m[BLAKE2B_SIGMAS[round][5]], 2, 6, 10, 14);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][6]], m[BLAKE2B_SIGMAS[round][7]], 3, 7, 11, 15);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][8]], m[BLAKE2B_SIGMAS[round][9]], 0, 5, 10, 15);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][10]], m[BLAKE2B_SIGMAS[round][11]], 1, 6, 11, 12);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][12]], m[BLAKE2B_SIGMAS[round][13]], 2, 7, 8, 13);
        cl_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][14]], m[BLAKE2B_SIGMAS[round][15]], 3, 4, 9, 14);
    }

    for (int offset = 0; offset < BLAKE2B_CHAIN_SIZE; offset++) {
        ctx->chain[offset] = ctx->chain[offset] ^ ctx->state[offset] ^ ctx->state[offset + 8];
    }
}

void cl_blake2b_init(cl_blake2b_ctx_t *ctx, BYTE* key, WORD keylen, WORD digestbitlen, uint8_t debug)
{
	for (int i = 0; i < BLAKE2B_STATE_SIZE; i++) {
		ctx->state[i] = 0;
	}
	for (int i = 0; i < BLAKE2B_BLOCK_LENGTH; i++) {
		ctx->buff[i] = 0;
	}

    ctx->keylen = keylen;
    ctx->digestlen = digestbitlen >> 3;
    ctx->pos = 0;
    ctx->t0 = 0;
    ctx->t1 = 0;
    ctx->f0 = 0;
    ctx->chain[0] = BLAKE2B_IVS_0 ^ (ctx->digestlen | (ctx->keylen << 8) | 0x1010000);
    ctx->chain[1] = BLAKE2B_IVS_1;
    ctx->chain[2] = BLAKE2B_IVS_2;
    ctx->chain[3] = BLAKE2B_IVS_3;
    ctx->chain[4] = BLAKE2B_IVS_4;
    ctx->chain[5] = BLAKE2B_IVS_5;
    ctx->chain[6] = BLAKE2B_IVS_6;
    ctx->chain[7] = BLAKE2B_IVS_7;

    memcpy(ctx->buff, key, keylen);
    memcpy(ctx->key, key, keylen);
    ctx->pos = BLAKE2B_BLOCK_LENGTH;
}

void cl_blake2b_update(cl_blake2b_ctx_t *ctx, BYTE* in, uint64_t inlen)
{
    if (inlen == 0)
        return;

    WORD start = 0;
    int64_t in_index = 0, block_index = 0;

    if (ctx->pos)
    {
        start = BLAKE2B_BLOCK_LENGTH - ctx->pos;
        if (start < inlen){
            memcpy(ctx->buff + ctx->pos, in, start);
            ctx->t0 += BLAKE2B_BLOCK_LENGTH;

            if (ctx->t0 == 0) ctx->t1++;

            cl_blake2b_compress(ctx, ctx->buff, 0);
	    ctx->pos = 0;
	    for (int i = 0; i < BLAKE2B_BLOCK_LENGTH; i++) {
		    ctx->buff[i] = 0;
	    }
        } else {
            memcpy(ctx->buff + ctx->pos, in, inlen);//read the whole *in
            ctx->pos += inlen;
            return;
        }
    }

    block_index =  inlen - BLAKE2B_BLOCK_LENGTH;
    for (in_index = start; in_index < block_index; in_index += BLAKE2B_BLOCK_LENGTH)
    {
        ctx->t0 += BLAKE2B_BLOCK_LENGTH;
        if (ctx->t0 == 0) {
            ctx->t1++;
	}

        cl_blake2b_compress(ctx, in, in_index);
    }

    memcpy(ctx->buff, in + in_index, inlen - in_index);
    ctx->pos += inlen - in_index;
}

void cl_blake2b_final(cl_blake2b_ctx_t *ctx, BYTE* out)
{
    ctx->f0 = 0xFFFFFFFFFFFFFFFFL;
    ctx->t0 += ctx->pos;
    if (ctx->pos > 0 && ctx->t0 == 0) {
        ctx->t1++;
    }

    cl_blake2b_compress(ctx, ctx->buff, 0);
    for (int i = 0; i < BLAKE2B_BLOCK_LENGTH; i++) {
	    ctx->buff[i] = 0;
    }
    for (int i = 0; i < BLAKE2B_STATE_SIZE; i++) {
	    ctx->state[i] = 0;
    }

    int i8 = 0;
    // Added (&& i8 <= 24) because HASHLEN is only 32.
    // And clLinkProgram will segfault on AMD systems otherwise (unless compiling with -O0).
    for (int i = 0; i < BLAKE2B_CHAIN_SIZE && ((i8 = i * 8) < ctx->digestlen) && i8 <= 24; i++)
    //for (int i = 0; i < BLAKE2B_CHAIN_SIZE && ((i8 = i * 8) < ctx->digestlen); i++)
    {
        BYTE * BYTEs = (BYTE*)(&ctx->chain[i]);
        if (i8 < ctx->digestlen - 8) {
            memcpy(out + i8, BYTEs, 8);
	} else {
            memcpy(out + i8, BYTEs, ctx->digestlen - i8);
	}
    }
}


__kernel void test_blake2b(__global uint8_t *in, __global uint8_t *out) {
	uint32_t thread = get_global_id(0);
	uint32_t index = thread + 0x20;
	uint8_t key32[32];
	uint8_t l_out[32];
	uint8_t l_in[32];
	for (int i = 0; i < 32; i++) {
		((uint8_t*)key32)[i] = 0;
	}
	for (int i = 0; i < 32; i++) {
		l_in[i] = in[i];
	}
	cl_blake2b_ctx_t ctx;
	cl_blake2b_init(&ctx, key32, 32, 256, 0);
	cl_blake2b_update(&ctx, l_in, 32);
	cl_blake2b_update(&ctx, (uint8_t *)&index, 4);
	cl_blake2b_final(&ctx, l_out);
	for (int i = 0; i < 32; i++) {
		out[32*thread + i] = l_out[i];
	}
}
