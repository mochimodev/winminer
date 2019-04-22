/* trigg_cuda.cu OpenCL Implementation of Trigg's Algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 22 April 2019
 *
*/

#define __align__(x) __attribute__((aligned(x)))
#define __forceinline inline

/* Lines 21 through 178 of this file were provided by a third party and are not subject to copyright
 * or ownership claims by Adequate Systems.  These lines represent a CUDA implementation of SHA-256
 * that an anonymous community member wrote for us.  Please note sha256 is based on public domain code
 * by Brad Conte (brad AT bradconte.com).
 * https://raw.githubusercontent.com/B-Con/crypto-algorithms/master/sha256.c
*/

/*__global static unsigned int __align__(8) c_midstate256[8];
__global static unsigned int __align__(8) c_input32[8];
__global static unsigned int __align__(8) c_blockNumber8[2];
__global static unsigned char __align__(8) c_difficulty;*/
__constant static unsigned int __align__(8) c_K[64] =
{
	0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
	0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
	0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
	0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
	0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
	0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
	0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
	0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
};


#define cuda_swab32(x) \
    ((((x) << 24) & 0xff000000u) | (((x) << 8) & 0x00ff0000u) | \
        (((x) >> 8) & 0x0000ff00u) | (((x) >> 24) & 0x000000ffu))

#define xor3b(a,b,c) (a ^ b ^ c)
#define ROTR32(x, n) (((x) << (32 - (n))) | ((x) >> (n)))

__forceinline unsigned long xandx(unsigned long a, unsigned long b, unsigned long c)
{
	return ((b ^ c) & a) ^ c;
}

#define AS_UINT2(addr) *((uint2*)(addr))

__forceinline unsigned int bsg2_0(const unsigned int x)
{
	return xor3b(ROTR32(x, 2), ROTR32(x, 13), ROTR32(x, 22));
}

__forceinline unsigned int bsg2_1(const unsigned int x)
{
	return xor3b(ROTR32(x, 6), ROTR32(x, 11), ROTR32(x, 25));
}

__forceinline unsigned int ssg2_0(const unsigned int x)
{
	return xor3b(ROTR32(x, 7), ROTR32(x, 18), (x >> 3));
}

__forceinline unsigned int ssg2_1(const unsigned int x)
{
	return xor3b(ROTR32(x, 17), ROTR32(x, 19), (x >> 10));
}

__forceinline unsigned int andor32(const unsigned int a, const unsigned int b, const unsigned int c)
{
	return (a & b) | ((a | b) & c);
}

static void sha2_step1(unsigned int a, unsigned int b, unsigned int c, unsigned int *d, unsigned int e, unsigned int f, unsigned int g, unsigned int *h,
	unsigned int in, const unsigned int Kshared)
{
	unsigned int t1, t2;
	unsigned int vxandx = xandx(e, f, g);
	unsigned int bsg21 = bsg2_1(e);
	unsigned int bsg20 = bsg2_0(a);
	unsigned int andorv = andor32(a, b, c);

	t1 = *h + bsg21 + vxandx + Kshared + in;
	t2 = bsg20 + andorv;
	*d = *d + t1;
	*h = t1 + t2;
}

static void sha2_step2(unsigned int a, unsigned int b, unsigned int c, unsigned int *d, unsigned int e, unsigned int f, unsigned int g, unsigned int *h,
	unsigned int* in, unsigned int pc, const unsigned int Kshared)
{
	unsigned int t1, t2;

	int pcidx1 = (pc - 2) & 0xF;
	int pcidx2 = (pc - 7) & 0xF;
	int pcidx3 = (pc - 15) & 0xF;

	unsigned int inx0 = in[pc];
	unsigned int inx1 = in[pcidx1];
	unsigned int inx2 = in[pcidx2];
	unsigned int inx3 = in[pcidx3];

	unsigned int ssg21 = ssg2_1(inx1);
	unsigned int ssg20 = ssg2_0(inx3);
	unsigned int vxandx = xandx(e, f, g);
	unsigned int bsg21 = bsg2_1(e);
	unsigned int bsg20 = bsg2_0(a);
	unsigned int andorv = andor32(a, b, c);

	in[pc] = ssg21 + inx2 + ssg20 + inx0;

	t1 = *h + bsg21 + vxandx + Kshared + in[pc];
	t2 = bsg20 + andorv;
	*d = *d + t1;
	*h = t1 + t2;
}

static void sha256_round(unsigned int* in, unsigned int* state, __constant unsigned int* const Kshared)
{
	unsigned int a = state[0];
	unsigned int b = state[1];
	unsigned int c = state[2];
	unsigned int d = state[3];
	unsigned int e = state[4];
	unsigned int f = state[5];
	unsigned int g = state[6];
	unsigned int h = state[7];

	sha2_step1(a, b, c, &d, e, f, g, &h, in[0], Kshared[0]);
	sha2_step1(h, a, b, &c, d, e, f, &g, in[1], Kshared[1]);
	sha2_step1(g, h, a, &b, c, d, e, &f, in[2], Kshared[2]);
	sha2_step1(f, g, h, &a, b, c, d, &e, in[3], Kshared[3]);
	sha2_step1(e, f, g, &h, a, b, c, &d, in[4], Kshared[4]);
	sha2_step1(d, e, f, &g, h, a, b, &c, in[5], Kshared[5]);
	sha2_step1(c, d, e, &f, g, h, a, &b, in[6], Kshared[6]);
	sha2_step1(b, c, d, &e, f, g, h, &a, in[7], Kshared[7]);
	sha2_step1(a, b, c, &d, e, f, g, &h, in[8], Kshared[8]);
	sha2_step1(h, a, b, &c, d, e, f, &g, in[9], Kshared[9]);
	sha2_step1(g, h, a, &b, c, d, e, &f, in[10], Kshared[10]);
	sha2_step1(f, g, h, &a, b, c, d, &e, in[11], Kshared[11]);
	sha2_step1(e, f, g, &h, a, b, c, &d, in[12], Kshared[12]);
	sha2_step1(d, e, f, &g, h, a, b, &c, in[13], Kshared[13]);
	sha2_step1(c, d, e, &f, g, h, a, &b, in[14], Kshared[14]);
	sha2_step1(b, c, d, &e, f, g, h, &a, in[15], Kshared[15]);

#pragma unroll
	for (int i = 0; i < 3; i++)
	{
		sha2_step2(a, b, c, &d, e, f, g, &h, in, 0, Kshared[16 + 16 * i]);
		sha2_step2(h, a, b, &c, d, e, f, &g, in, 1, Kshared[17 + 16 * i]);
		sha2_step2(g, h, a, &b, c, d, e, &f, in, 2, Kshared[18 + 16 * i]);
		sha2_step2(f, g, h, &a, b, c, d, &e, in, 3, Kshared[19 + 16 * i]);
		sha2_step2(e, f, g, &h, a, b, c, &d, in, 4, Kshared[20 + 16 * i]);
		sha2_step2(d, e, f, &g, h, a, b, &c, in, 5, Kshared[21 + 16 * i]);
		sha2_step2(c, d, e, &f, g, h, a, &b, in, 6, Kshared[22 + 16 * i]);
		sha2_step2(b, c, d, &e, f, g, h, &a, in, 7, Kshared[23 + 16 * i]);
		sha2_step2(a, b, c, &d, e, f, g, &h, in, 8, Kshared[24 + 16 * i]);
		sha2_step2(h, a, b, &c, d, e, f, &g, in, 9, Kshared[25 + 16 * i]);
		sha2_step2(g, h, a, &b, c, d, e, &f, in, 10, Kshared[26 + 16 * i]);
		sha2_step2(f, g, h, &a, b, c, d, &e, in, 11, Kshared[27 + 16 * i]);
		sha2_step2(e, f, g, &h, a, b, c, &d, in, 12, Kshared[28 + 16 * i]);
		sha2_step2(d, e, f, &g, h, a, b, &c, in, 13, Kshared[29 + 16 * i]);
		sha2_step2(c, d, e, &f, g, h, a, &b, in, 14, Kshared[30 + 16 * i]);
		sha2_step2(b, c, d, &e, f, g, h, &a, in, 15, Kshared[31 + 16 * i]);
	}

	state[0] += a;
	state[1] += b;
	state[2] += c;
	state[3] += d;
	state[4] += e;
	state[5] += f;
	state[6] += g;
	state[7] += h;
}
/* Code below this line is property of Adequate Systems, LLC. Copyright 2019. All Rights Reserved.  Please see LICENSE.PDF
 * for specific license details */
int gpu_trigg_eval(unsigned int *h, unsigned char d)
{
	unsigned int *bp, n;
	for (bp = h, n = d >> 5; n; n--) {
		if (*bp++ != 0) return 0;
	}
	return clz(*bp) >= (d & 31);
}

__constant static int Z_PREP[8] = { 12,13,14,15,16,17,12,13 }; /* Confirmed */
__constant static int Z_ING[32] = { 18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,23,24,31,32,33,34 }; /* Confirmed */
__constant static int Z_INF[16] = { 44,45,46,47,48,50,51,52,53,54,55,56,57,58,59,60 }; /* Confirmed */
__constant static int Z_ADJ[64] = { 61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,94,95,96,97,98,99,100,101,102,103,104,105,107,108,109,110,112,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128 }; /* Confirmed */
__constant static int Z_AMB[16] = { 77,94,95,96,126,214,217,218,220,222,223,224,225,226,227,228 }; /* Confirmed */
__constant static int Z_TIMED[8] = { 84,243,249,250,251,252,253,255 }; /* Confirmed */
__constant static int Z_NS[64] = { 129,130,131,132,133,134,135,136,137,138,145,149,154,155,156,157,177,178,179,180,182,183,184,185,186,187,188,189,190,191,192,193,194,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,241,244,245,246,247,248,249,250,251,252,253,254,255 }; /* Confirmed */
__constant static int Z_NPL[32] = { 139,140,141,142,143,144,146,147,148,150,151,153,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,181 }; /* Confirmed */
__constant static int Z_MASS[32] = { 214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,242,214,215,216,219 }; /* Confirmed */
__constant static int Z_INGINF[32] = { 18,19,20,21,22,25,26,27,28,29,30,36,37,38,39,40,41,42,44,46,47,48,49,51,52,53,54,55,56,57,58,59 }; /* Confirmed */
__constant static int Z_TIME[16] = { 82,83,84,85,86,87,88,243,249,250,251,252,253,254,255,253 }; /* Confirmed */
__constant static int Z_INGADJ[64] = { 18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,23,24,31,32,33,34,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92 };/* Confirmed */

__kernel void trigg(unsigned int threads, __global int *g_found, __global unsigned char *g_seed,
	__global unsigned int *c_midstate256,
	__global unsigned int *c_input32,
	__global unsigned int *c_blockNumber8,
	unsigned char c_difficulty)
{
	const unsigned int thread = get_global_id(0);
	unsigned char seed[16] = { 0 };
	unsigned int input[16], state[8];

#ifdef CL_DEBUG
	if (thread == 10) {
		printf("thread: %d\n", thread);
		printf("midstate265: "); for (int i = 0; i < 8; i++) { printf("%08x ", c_midstate256[i]); } printf("\n");
		printf("blockNumber8: "); for (int i = 0; i < 2; i++) { printf("%08x ", c_blockNumber8[i]); } printf("\n");
		printf("diff: %d\n", c_difficulty);
		printf("threads: %d\n", threads);
	}
#endif

	if (thread <= threads) {

		if (thread <= 131071) { /* Total Permutations, this frame: 131,072 */
			seed[0] = Z_PREP[(thread & 7)];
			seed[1] = Z_TIMED[(thread >> 3) & 7];
			seed[2] = 1;
			seed[3] = 5;
			seed[4] = Z_NS[(thread >> 6) & 63];
			seed[5] = 1;
			seed[6] = Z_ING[(thread >> 12) & 31];
		}
		if ((131071 < thread) && (thread <= 262143)) { /* Total Permutations, this frame: 131,072 */
			seed[0] = Z_TIME[(thread & 15)];
			seed[1] = Z_MASS[(thread >> 4) & 31];
			seed[2] = 1;
			seed[3] = Z_INF[(thread >> 9) & 15];
			seed[4] = 9;
			seed[5] = 2;
			seed[6] = 1;
			seed[7] = Z_AMB[(thread >> 13) & 15];
		}
		if ((262143 < thread) && (thread <= 4456447)) { /* Total Permutations, this frame: 4,194,304 */
			seed[0] = Z_PREP[(thread & 7)];
			seed[1] = Z_TIMED[(thread >> 3) & 7];
			seed[2] = 1;
			seed[3] = Z_ADJ[(thread >> 6) & 63];
			seed[4] = Z_NPL[(thread >> 12) & 31];
			seed[5] = 1;
			seed[6] = Z_INGINF[(thread >> 17) & 31];
		}
		if ((4456447 < thread) && (thread <= 12845055)) { /* Total Permutations, this frame: 8,388,608 */
			seed[0] = 5;
			seed[1] = Z_NS[(thread & 63)];
			seed[2] = 1;
			seed[3] = Z_PREP[(thread >> 6) & 7];
			seed[4] = Z_TIMED[(thread >> 9) & 7];
			seed[5] = Z_MASS[(thread >> 12) & 31];
			seed[6] = 3;
			seed[7] = 1;
			seed[8] = Z_ADJ[(thread >> 17) & 63];
		}
		if ((12845055 < thread) && (thread <= 29622271)) { /* Total Permutations, this frame: 16,777,216 */
			seed[0] = Z_PREP[thread & 7];
			seed[1] = Z_ADJ[(thread >> 3) & 63];
			seed[2] = Z_MASS[(thread >> 9) & 31];
			seed[3] = 1;
			seed[4] = Z_NPL[(thread >> 14) & 31];
			seed[5] = 1;
			seed[6] = Z_INGINF[(thread >> 19) & 31];
		}
		if ((29622271 < thread) && (thread <= 46399487)) { /* Total Permutations, this frame: 16,777,216 */
			seed[0] = Z_PREP[(thread & 7)];
			seed[1] = Z_MASS[(thread >> 3) & 31];
			seed[2] = 1;
			seed[3] = Z_ADJ[(thread >> 8) & 63];
			seed[4] = Z_NPL[(thread >> 14) & 31];
			seed[5] = 1;
			seed[6] = Z_INGINF[(thread >> 19) & 31];
		}
		if ((46399487 < thread) && (thread <= 63176703)) { /* Total Permutations, this frame: 16,777,216 */
			seed[0] = Z_TIME[(thread & 15)];
			seed[1] = Z_AMB[(thread >> 4) & 15];
			seed[2] = 1;
			seed[3] = Z_ADJ[(thread >> 8) & 63];
			seed[4] = Z_MASS[(thread >> 14) & 31];
			seed[5] = 1;
			seed[6] = Z_ING[(thread >> 19) & 31];
		}
		if ((63176703 < thread) && (thread <= 600047615)) { /* Total Permutations, this frame: 536,870,912 */
			seed[0] = Z_TIME[(thread & 15)];
			seed[1] = Z_AMB[(thread >> 4) & 15];
			seed[2] = 1;
			seed[3] = Z_PREP[(thread >> 8) & 7];
			seed[4] = 5;
			seed[5] = Z_ADJ[(thread >> 11) & 63];
			seed[6] = Z_NS[(thread >> 17) & 63];
			seed[7] = 3;
			seed[8] = 1;
			seed[9] = Z_INGADJ[(thread >> 23) & 63];
		}
#if 0
		/* Below Two Frames are Valid, But Require 64-Bit Math: if extra entropy req'd.*/
		if (< thread <= ) { /* Total Permutations, this frame: 549,755,813,888 */
			seed[0] = Z_ING[(thread & 31)];
			seed[1] = Z_PREP[(thread << 5) & 7];
			seed[2] = Z_TIME[(thread << 8) & 15];
			seed[3] = Z_MASS[(thread << 12) & 31];
			seed[4] = 1;
			seed[5] = Z_MASS[(thread << 17) & 31];
			seed[6] = Z_ING[(thread << 22) & 31];
			seed[7] = 3;
			seed[8] = 1;
			seed[9] = 5;
			seed[10] = Z_ADJ[(thread << 27) & 63];
			seed[11] = Z_NS[(thread << 33) & 63];
		}
		if (< thread <= ) { /* Total Permutations, this frame: 4,398,046,511,104 */
			seed[0] = Z_ING[(thread & 31)];
			seed[1] = Z_PREP[(thread << 5) & 7];
			seed[2] = 5;
			seed[3] = Z_ADJ[(thread << 8) & 63];
			seed[4] = Z_NS[(thread << 14) & 63];
			seed[5] = 1;
			seed[6] = Z_MASS[(thread << 19) & 31];
			seed[7] = Z_ING[(thread << 24) & 31];
			seed[8] = 3;
			seed[9] = 1;
			seed[10] = 5;
			seed[11] = Z_ADJ[(thread << 30) & 63];
			seed[12] = Z_NS[(thread << 36) & 63];
		}
		/* End 64-bit Frames */
#endif

#pragma unroll
		for (int i = 0; i < 8; i++)
		{
			input[i] = c_input32[i];
		}
#pragma unroll
		for (int i = 0; i < 4; i++)
		{
			input[8 + i] = cuda_swab32(((unsigned int *)seed)[i]);
		}

		input[12] = cuda_swab32(c_blockNumber8[0]);
		input[13] = cuda_swab32(c_blockNumber8[1]);
		input[14] = 0x80000000;
		input[15] = 0;

#ifdef CL_DEBUG
		if (thread == 10) {
			printf("input: "); for (int i = 0; i < 16; i++) { printf("%08x ", input[i]); } printf("\n");
		}
#endif

#pragma unroll
		//for (int i = 0; i < 8; i += 2)
		for (int i = 0; i < 4; i++)
		{
			//AS_UINT2(&state[i]) = AS_UINT2(&c_midstate256[i]);
			((unsigned long*)state)[i] = ((__global unsigned long*)c_midstate256)[i];
		}

		sha256_round(input, state, c_K);

#ifdef CL_DEBUG
		if (thread == 10) {
			printf("state2: "); for (int i = 0; i < 8; i++) { printf("%08x ", state[i]); } printf("\n");
		}
#endif

#pragma unroll
		for (int i = 0; i < 15; i++)
		{
			input[i] = 0;
		}
		input[15] = 0x9c0;

		sha256_round(input, state, c_K);
#ifdef CL_DEBUG
		if (thread == 10) {
			printf("state3: "); for (int i = 0; i < 8; i++) { printf("%08x ", state[i]); } printf("\n");

			printf("seed: "); for (int i = 0; i < 16; i++) { printf("%02x ", seed[i]); } printf("\n");
		}
#endif

		if (gpu_trigg_eval(state, c_difficulty))
		{
			*g_found = 1;
#pragma unroll
			for (int i = 0; i < 16; i++)
			{
				g_seed[i] = seed[i];
			}
		}
	}
}
