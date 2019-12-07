// Keccak-derived hash implementations Copyright (c) 2019 Wolf9466 (AKA Wolf0/OhGodAPet)

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

static const __constant ulong KeccakF1600RndConsts[24] =
{
    0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808AUL,
    0x8000000080008000UL, 0x000000000000808BUL, 0x0000000080000001UL,
    0x8000000080008081UL, 0x8000000000008009UL, 0x000000000000008AUL,
    0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000AUL,
    0x000000008000808BUL, 0x800000000000008BUL, 0x8000000000008089UL,
    0x8000000000008003UL, 0x8000000000008002UL, 0x8000000000000080UL,
    0x000000000000800AUL, 0x800000008000000AUL, 0x8000000080008081UL,
    0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL
};

void KeccakF1600(ulong *st)
{
	for(int i = 0; i < 24; ++i)
	{
		ulong bc[5], tmp1, tmp2;
		bc[0] = st[0] ^ st[5] ^ st[10] ^ st[15] ^ st[20] ^ rotate(st[2] ^ st[7] ^ st[12] ^ st[17] ^ st[22], 1UL);
		bc[1] = st[1] ^ st[6] ^ st[11] ^ st[16] ^ st[21] ^ rotate(st[3] ^ st[8] ^ st[13] ^ st[18] ^ st[23], 1UL);
		bc[2] = st[2] ^ st[7] ^ st[12] ^ st[17] ^ st[22] ^ rotate(st[4] ^ st[9] ^ st[14] ^ st[19] ^ st[24], 1UL);
		bc[3] = st[3] ^ st[8] ^ st[13] ^ st[18] ^ st[23] ^ rotate(st[0] ^ st[5] ^ st[10] ^ st[15] ^ st[20], 1UL);
		bc[4] = st[4] ^ st[9] ^ st[14] ^ st[19] ^ st[24] ^ rotate(st[1] ^ st[6] ^ st[11] ^ st[16] ^ st[21], 1UL);
		tmp1 = st[1] ^ bc[0];

		st[0] ^= bc[4];
		st[1] = rotate(st[6] ^ bc[0], 44UL);
		st[6] = rotate(st[9] ^ bc[3], 20UL);
		st[9] = rotate(st[22] ^ bc[1], 61UL);
		st[22] = rotate(st[14] ^ bc[3], 39UL);
		st[14] = rotate(st[20] ^ bc[4], 18UL);
		st[20] = rotate(st[2] ^ bc[1], 62UL);
		st[2] = rotate(st[12] ^ bc[1], 43UL);
		st[12] = rotate(st[13] ^ bc[2], 25UL);
		st[13] = rotate(st[19] ^ bc[3],  8UL);
		st[19] = rotate(st[23] ^ bc[2], 56UL);
		st[23] = rotate(st[15] ^ bc[4], 41UL);
		st[15] = rotate(st[4] ^ bc[3], 27UL);
		st[4] = rotate(st[24] ^ bc[3], 14UL);
		st[24] = rotate(st[21] ^ bc[0],  2UL);
		st[21] = rotate(st[8] ^ bc[2], 55UL);
		st[8] = rotate(st[16] ^ bc[0], 45UL);
		st[16] = rotate(st[5] ^ bc[4], 36UL);
		st[5] = rotate(st[3] ^ bc[2], 28UL);
		st[3] = rotate(st[18] ^ bc[2], 21UL);
		st[18] = rotate(st[17] ^ bc[1], 15UL);
		st[17] = rotate(st[11] ^ bc[0], 10UL);
		st[11] = rotate(st[7] ^ bc[1],  6UL);
		st[7] = rotate(st[10] ^ bc[4],  3UL);
		st[10] = rotate(tmp1, 1UL);

		tmp1 = st[0]; tmp2 = st[1]; st[0] = bitselect(st[0] ^ st[2], st[0], st[1]); st[1] = bitselect(st[1] ^ st[3], st[1], st[2]); st[2] = bitselect(st[2] ^ st[4], st[2], st[3]); st[3] = bitselect(st[3] ^ tmp1, st[3], st[4]); st[4] = bitselect(st[4] ^ tmp2, st[4], tmp1);
		tmp1 = st[5]; tmp2 = st[6]; st[5] = bitselect(st[5] ^ st[7], st[5], st[6]); st[6] = bitselect(st[6] ^ st[8], st[6], st[7]); st[7] = bitselect(st[7] ^ st[9], st[7], st[8]); st[8] = bitselect(st[8] ^ tmp1, st[8], st[9]); st[9] = bitselect(st[9] ^ tmp2, st[9], tmp1);
		tmp1 = st[10]; tmp2 = st[11]; st[10] = bitselect(st[10] ^ st[12], st[10], st[11]); st[11] = bitselect(st[11] ^ st[13], st[11], st[12]); st[12] = bitselect(st[12] ^ st[14], st[12], st[13]); st[13] = bitselect(st[13] ^ tmp1, st[13], st[14]); st[14] = bitselect(st[14] ^ tmp2, st[14], tmp1);
		tmp1 = st[15]; tmp2 = st[16]; st[15] = bitselect(st[15] ^ st[17], st[15], st[16]); st[16] = bitselect(st[16] ^ st[18], st[16], st[17]); st[17] = bitselect(st[17] ^ st[19], st[17], st[18]); st[18] = bitselect(st[18] ^ tmp1, st[18], st[19]); st[19] = bitselect(st[19] ^ tmp2, st[19], tmp1);
		tmp1 = st[20]; tmp2 = st[21]; st[20] = bitselect(st[20] ^ st[22], st[20], st[21]); st[21] = bitselect(st[21] ^ st[23], st[21], st[22]); st[22] = bitselect(st[22] ^ st[24], st[22], st[23]); st[23] = bitselect(st[23] ^ tmp1, st[23], st[24]); st[24] = bitselect(st[24] ^ tmp2, st[24], tmp1);
		st[0] ^= KeccakF1600RndConsts[i];
	}
}

// Keccakf[1600] with rate = 1088, and capacity = 512.
void Keccak256Digest36B(ulong *Digest, const ulong *Input)
{
	ulong st[25];

	#pragma unroll
	for(int i = 0; i < 4; ++i) st[i] = Input[i];

	((uint *)st)[8] = ((uint *)Input)[8];
	((uint *)st)[9] = 1;

	#pragma unroll
	for(int i = 5; i < 25; ++i) st[i] = 0UL;

	st[16] = 0x8000000000000000UL;

	KeccakF1600(st);

	#pragma unroll
	for(int i = 0; i < 4; ++i) Digest[i] = st[i];
}

// Keccakf[1600] with rate = 1088, and capacity = 512.
void Keccak256Digest1060B(ulong *Digest, const ulong *Input)
{
	ulong st[25];

	// Zero state prior to loop (allows the loop to contain the first iter)
	#pragma unroll
	for(int i = 0; i < 25; ++i) st[i] = 0UL;

	// We can absorb r = 1088 bits (136 bytes, or 17 qwords) per iteration.
	// Iterates seven times.
	for(int blk = 0; blk < 119; blk += 17)
	{
		for(int i = 0; i < 17; ++i) st[i] ^= Input[blk + i];

		KeccakF1600(st);
	}

	// Final permutation
	#pragma unroll
	for(int i = 0; i < 13; ++i) st[i] ^= Input[119 + i];

	// Last four bytes, then the padding
	((uint *)st)[26] ^= ((uint *)Input)[264];
	((uint *)st)[27] ^= 1U;

	st[16] ^= 0x8000000000000000UL;

	KeccakF1600(st);

	#pragma unroll
	for(int i = 0; i < 4; ++i) Digest[i] = st[i];
}

void SHA3256Digest36B(ulong *Digest, const ulong *Input)
{
	ulong st[25];

	#pragma unroll
	for(int i = 0; i < 4; ++i) st[i] = Input[i];

	((uint *)st)[8] = ((uint *)Input)[8];
	((uint *)st)[9] = 0x06;

	#pragma unroll
	for(int i = 5; i < 25; ++i) st[i] = 0UL;

	st[16] = 0x8000000000000000UL;

	KeccakF1600(st);

	#pragma unroll
	for(int i = 0; i < 4; ++i) Digest[i] = st[i];
}

void SHA3Digest1060B(ulong *Digest, const ulong *Input)
{
	ulong st[25];

	// Zero state prior to loop (allows the loop to contain the first iter)
	#pragma unroll
	for(int i = 0; i < 25; ++i) st[i] = 0UL;

	// We can absorb r = 1088 bits (136 bytes, or 17 qwords) per iteration.
	// Iterates seven times.
	for(int blk = 0; blk < 119; blk += 17)
	{
		for(int i = 0; i < 17; ++i) st[i] ^= Input[blk + i];

		KeccakF1600(st);
	}

	// Final permutation
	#pragma unroll
	for(int i = 0; i < 13; ++i) st[i] ^= Input[119 + i];

	// Last four bytes, then the padding
	((uint *)st)[26] ^= ((uint *)Input)[264];
	((uint *)st)[27] ^= 0x06;

	st[16] ^= 0x8000000000000000UL;

	KeccakF1600(st);

	#pragma unroll
	for(int i = 0; i < 4; ++i) Digest[i] = st[i];
}
