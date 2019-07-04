/*
 * keccak.h  Implementation of Keccak/SHA3 digest
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 12 June 2019
 * Revision: 1
 *
 * This file is subject to the license as found in LICENSE.PDF
 *
 */
#include <stdint.h>
#include <string.h>

#ifndef byte
typedef uint8_t byte;
#endif

#ifndef KECCAK_H
#define KECCAK_H

#define KECCAK_ROUND 24
#define KECCAK_STATE_SIZE 25
#define KECCAK_Q_SIZE 192

static const uint64_t KECCAK_CONSTS[] = { 0x0000000000000001uLL, 0x0000000000008082uLL,
0x800000000000808auLL, 0x8000000080008000uLL, 0x000000000000808buLL, 0x0000000080000001uLL, 0x8000000080008081uLL,
0x8000000000008009uLL, 0x000000000000008auLL, 0x0000000000000088uLL, 0x0000000080008009uLL, 0x000000008000000auLL,
0x000000008000808buLL, 0x800000000000008buLL, 0x8000000000008089uLL, 0x8000000000008003uLL, 0x8000000000008002uLL,
0x8000000000000080uLL, 0x000000000000800auLL, 0x800000008000000auLL, 0x8000000080008081uLL, 0x8000000000008080uLL,
0x0000000080000001uLL, 0x8000000080008008uLL };

typedef struct {
	
   byte sha3_flag;
   uint32_t digestbitlen;
   uint64_t rate_bits;
   uint64_t rate_bytes;
   uint64_t absorb_round;

   int64_t state[KECCAK_STATE_SIZE];
   uint8_t q[KECCAK_Q_SIZE];

   uint64_t bits_in_queue;

} keccak_ctx_t;
typedef keccak_ctx_t KECCAK_CTX;


void keccak_init(keccak_ctx_t *ctx, uint32_t digestbitlen);
void keccak_sha3_init(keccak_ctx_t *ctx, uint32_t digestbitlen);
void keccak_update(keccak_ctx_t *ctx, byte *in, uint64_t inlen);
void keccak_final(keccak_ctx_t *ctx, byte *out);
uint64_t keccak_ROTL64(uint64_t a, uint64_t b);
int64_t keccak_MIN(int64_t a, int64_t b);
uint64_t keccak_UMIN(uint64_t a, uint64_t b);
uint64_t keccak_leuint64(uint8_t *in);
void keccak_absorb(keccak_ctx_t *ctx, byte* in);
void keccak_extract(keccak_ctx_t *ctx);
void keccak_pad(keccak_ctx_t *ctx);
void keccak_permutations(keccak_ctx_t * ctx);

#endif

