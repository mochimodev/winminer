// SHA2-256 hash implementations Copyright (c) 2019 Wolf9466 (AKA Wolf0/OhGodAPet)

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. All advertising materials mentioning features or use of this software
//    must display the following acknowledgement:
//    This product includes software developed by Wolf9466.
// 4. Neither the name of the <organization> nor the
//    names of its contributors may be used to endorse or promote products
//    derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


static const __constant uint SHA2_256_K[64] =
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

static const __constant uint SHA2_256_IV[8] =
{
	0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
	0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
};

#define BSWAP32(x)			(as_uint(as_uchar4(x).s3210))
#define BSWAP64(x)			(as_ulong(as_uchar8(x).s76543210))
#define bitselect(a, b, c)	((a) ^ ((c) & ((b) ^ (a))))
#define rotate(x, y)		(((x) << (y)) | ((x) >> (32 - (y))))
#define CH(X, Y, Z)			bitselect(Z, Y, X)
#define MAJ(X, Y, Z)		CH((X ^ Z), Y, Z)

#define F0(x)				(rotate((x), 30U) ^ rotate((x), 19U) ^ rotate((x), 10U))
#define F1(x)				(rotate((x), 26U) ^ rotate((x), 21U) ^ rotate((x), 7U))
#define S0(x)				(rotate((x), 25U) ^ rotate((x), 14U) ^ ((x) >> 3))
#define S1(x)				(rotate((x), 15U) ^ rotate((x), 13U) ^ ((x) >> 10))

#define SHA2_256_STEP(A, B, C, D, E, F, G, H, idx0, idx1) { \
	uint tmp = H + F1(E) + CH(E, F, G) + SHA2_256_K[idx0] + W[idx1]; \
	D += tmp; \
	H = tmp + F0(A) + MAJ(A, B, C); \
}

void SHA2_256_Transform(uint *InState, uint *Input)
{
	uint W[32], State[8];

	#pragma unroll
	for(int i = 0; i < 8; ++i) State[i] = InState[i];

	#pragma unroll
	for(int i = 0; i < 16; ++i) W[i] = BSWAP32(Input[i]);

	for(int i = 0; i < 64; i += 16)
	{
		#pragma unroll
		for(int x = 0; x < 16; x += 8)
		{
			SHA2_256_STEP(State[0], State[1], State[2], State[3], State[4], State[5], State[6], State[7], i + x, x);
			SHA2_256_STEP(State[7], State[0], State[1], State[2], State[3], State[4], State[5], State[6], i + x + 1, x + 1);
			SHA2_256_STEP(State[6], State[7], State[0], State[1], State[2], State[3], State[4], State[5], i + x + 2, x + 2);
			SHA2_256_STEP(State[5], State[6], State[7], State[0], State[1], State[2], State[3], State[4], i + x + 3, x + 3);
			SHA2_256_STEP(State[4], State[5], State[6], State[7], State[0], State[1], State[2], State[3], i + x + 4, x + 4);
			SHA2_256_STEP(State[3], State[4], State[5], State[6], State[7], State[0], State[1], State[2], i + x + 5, x + 5);
			SHA2_256_STEP(State[2], State[3], State[4], State[5], State[6], State[7], State[0], State[1], i + x + 6, x + 6);
			SHA2_256_STEP(State[1], State[2], State[3], State[4], State[5], State[6], State[7], State[0], i + x + 7, x + 7);
		}

		#pragma unroll
		for(int x = 16; x < 32; ++x)
			W[x - 16] = S1(W[(x - 2) & 15]) + W[(x - 7) & 15] + S0(W[(x - 15) & 15]) + W[x - 16];
	}

	#pragma unroll
	for(int i = 0; i < 8; ++i) InState[i] += State[i];
}

void SHA2_256_36B(uint *Digest, const uint *InData)
{
	uint State[8], Data[16];

	#pragma unroll
	for(int i = 0; i < 8; ++i) State[i] = SHA2_256_IV[i];

	#pragma unroll
	for(int i = 0; i < 9; ++i) Data[i] = InData[i];

	// Pad this shit, Merkle–Damgård style, except...
	// Do NOT endian-swap the padding! The transform
	// is expecting all little-endian input!
	Data[9] = 0x80UL;

	#pragma unroll
	for(int i = 10; i < 16; ++i) Data[i] = 0UL;

	((ulong *)Data)[7] = BSWAP64(36UL << 3);

	SHA2_256_Transform(State, Data);

	// Endian-swap the result
	#pragma unroll
	for(int i = 0; i < 8; ++i) Digest[i] = BSWAP32(State[i]);
}

void SHA2_256_124B(uint *Digest, const uint *InData)
{
	uint State[8], Data[16];

	#pragma unroll
	for(int i = 0; i < 8; ++i) State[i] = SHA2_256_IV[i];

	#pragma unroll
	for(int i = 0; i < 16; ++i) Data[i] = InData[i];

	SHA2_256_Transform(State, Data);

	#pragma unroll
	for(int i = 0; i < 15; ++i) Data[i] = InData[16 + i];

	Data[15] = 0x80UL;

	SHA2_256_Transform(State, Data);

	#pragma unroll
	for(int i = 0; i < 14; ++i) Data[i] = 0UL;

	((ulong *)Data)[7] = BSWAP64(124UL << 3);

	SHA2_256_Transform(State, Data);

	// Endian-swap the result
	#pragma unroll
	for(int i = 0; i < 8; ++i) Digest[i] = BSWAP32(State[i]);
}

void SHA2_256_1056B_1060B(uint *Digest, const uint *InData, bool Is1060)
{
	uint State[8], Data[16];

	#pragma unroll
	for(int i = 0; i < 8; ++i) State[i] = SHA2_256_IV[i];

	for(int i = 0; i < 16; ++i)
	{
		#pragma unroll
		for(int x = 0; x < 16; ++x) Data[x] = InData[(i << 4) + x];

		SHA2_256_Transform(State, Data);
	}

	#pragma unroll
	for(int i = 0; i < 8; ++i) Data[i] = InData[256 + i];

	// Merkle–Damgård style padding here, except...
	// Do NOT endian-swap the padding! The transform
	// is expecting all little-endian input!

	// Handle the case of 1060 byte input
	Data[8] = (Is1060) ? InData[264] : 0x80U;
	Data[9] = (Is1060) ? 0x80U : 0x00U;

	for(int i = 10; i < 14; ++i) Data[i] = 0UL;

	((ulong *)Data)[7] = (Is1060) ? 0x2021000000000000UL : 0x0021000000000000UL;

	SHA2_256_Transform(State, Data);

	// Endian-swap the result
	#pragma unroll
	for(int i = 0; i < 8; ++i) Digest[i] = BSWAP32(State[i]);
}
