
static const __constant ulong blake2b_IV[8] =
{
	0x6A09E667F3BCC908UL, 0xBB67AE8584CAA73BUL,
	0x3C6EF372FE94F82BUL, 0xA54FF53A5F1D36F1UL,
	0x510E527FADE682D1UL, 0x9B05688C2B3E6C1FUL,
	0x1F83D9ABFB41BD6BUL, 0x5BE0CD19137E2179UL
};

static const __constant uchar blake2b_sigma[12][16] =
{
	{	0,	1,	2,	3,	4,	5,	6,	7,	8,	9, 10, 11, 12, 13, 14, 15 } ,
	{ 14, 10,	4,	8,	9, 15, 13,	6,	1, 12,	0,	2, 11,	7,	5,	3 } ,
	{ 11,	8, 12,	0,	5,	2, 15, 13, 10, 14,	3,	6,	7,	1,	9,	4 } ,
	{	7,	9,	3,	1, 13, 12, 11, 14,	2,	6,	5, 10,	4,	0, 15,	8 } ,
	{	9,	0,	5,	7,	2,	4, 10, 15, 14,	1, 11, 12,	6,	8,	3, 13 } ,
	{	2, 12,	6, 10,	0, 11,	8,	3,	4, 13,	7,	5, 15, 14,	1,	9 } ,
	{ 12,	5,	1, 15, 14, 13,	4, 10,	0,	7,	6,	3,	9,	2,	8, 11 } ,
	{ 13, 11,	7, 14, 12,	1,	3,	9,	5,	0, 15,	4,	8,	6,	2, 10 } ,
	{	6, 15, 14,	9, 11,	3,	0,	8, 12,	2, 13,	7,	1,	4, 10,	5 } ,
	{ 10,	2,	8,	4,	7,	6,	1,	5, 15, 11,	9, 14,	3, 12, 13 , 0 } ,
	{	0,	1,	2,	3,	4,	5,	6,	7,	8,	9, 10, 11, 12, 13, 14, 15 } ,
	{ 14, 10,	4,	8,	9, 15, 13,	6,	1, 12,	0,	2, 11,	7,	5,	3 }
};

#if 1

inline ulong FAST_ROTL64_LO(const ulong x, const uint y)
{
    return(rotate(x, (ulong)y));
}

inline ulong FAST_ROTL64_HI(const ulong x, const uint y)
{
    return(rotate(x, (ulong)y));
}

#else

inline ulong FAST_ROTL64_LO(const ulong x, const uint y)
{
	return(as_ulong(amd_bitalign(as_uint2(x), as_uint2(x).s10, 32 - y)));
}
inline ulong FAST_ROTL64_HI(const ulong x, const uint y)
{
	return(as_ulong(amd_bitalign(as_uint2(x).s10, as_uint2(x), 32 - (y - 32))));
}

#endif

#define G(r,i,a,b,c,d) do { \
	a += b + m[blake2b_sigma[r][i]]; \
	d = as_ulong(as_uint2(d ^ a).s10); \
	c += d; \
	b = FAST_ROTL64_HI(b ^ c, 40UL); \
	a += b + m[blake2b_sigma[r][i + 1]]; \
	d = FAST_ROTL64_HI(d ^ a, 48UL); \
	c += d; \
	b = FAST_ROTL64_LO(b ^ c, 1UL); \
} while(0)

#define ROUND(r) do { \
	G(r, 0, v[ 0], v[ 4], v[ 8], v[12]); \
	G(r, 2, v[ 1], v[ 5], v[ 9], v[13]); \
	G(r, 4, v[ 2], v[ 6], v[10], v[14]); \
	G(r, 6, v[ 3], v[ 7], v[11], v[15]); \
	G(r, 8, v[ 0], v[ 5], v[10], v[15]); \
	G(r, 10, v[ 1], v[ 6], v[11], v[12]); \
	G(r, 12, v[ 2], v[ 7], v[ 8], v[13]); \
	G(r, 14, v[ 3], v[ 4], v[ 9], v[14]); \
} while(0)


inline void cl_blake2b_compress(ulong *st, uchar *in, ulong t0, ulong f0)
{
    ulong v[16], m[16];
    
	#pragma unroll
    for(int i = 0; i < 8; ++i) v[i] = st[i];

	#pragma unroll
    for(int i = 0; i < 8; ++i) v[i + 8] = blake2b_IV[i];

    v[12] ^= t0;
    v[14] ^= f0;

	#pragma unroll
    for(int i = 0; i < 16; ++i) m[i] = ((ulong *)in)[i];

	#pragma unroll
    for(int r = 0; r < 12; ++r)
    {
        ROUND(r);
    }

	#pragma unroll
    for(int i = 0; i < 8; ++i)
        st[i] = st[i] ^ v[i] ^ v[i + 8];
}

void Blake2B_K32_36B(uchar *out, uchar *in)
{
    ulong input[16], state[8];

    #pragma unroll
    for(int i = 0; i < 8; ++i) state[i] = blake2b_IV[i];

	//state[0] ^= (digestlen | (keylen << 8) | 0x1010000);
    state[0] ^= ((256 >> 3) | (32 << 8) | 0x1010000);

    // Key
    #pragma unroll
    for(int i = 0; i < 16; ++i) input[i] = 0x00UL;

    cl_blake2b_compress(state, (uchar*)input, 0x80UL, 0x00UL);

    #pragma unroll
    for(int i = 0; i < 4; ++i) input[i] = ((ulong *)in)[i];

    ((uint *)input)[8] = ((uint *)in)[8];
	((uint *)input)[9] = 0x00;

	#pragma unroll
	for(int i = 5; i < 16; ++i) input[i] = 0x00;

    cl_blake2b_compress(state, (uchar*)input, 0xA4UL, 0xFFFFFFFFFFFFFFFFUL);

	for(int i = 0; i < 8; ++i) ((ulong *)out)[i] = state[i];
}

void Blake2B_K32_1060B(uchar *out, uchar *in)
{
    ulong input[16], state[8];

    #pragma unroll
    for(int i = 0; i < 8; ++i) state[i] = blake2b_IV[i];

	//state[0] ^= (digestlen | (keylen << 8) | 0x1010000);
    state[0] ^= ((256 >> 3) | (32 << 8) | 0x1010000);

    // Key
    #pragma unroll
    for(int i = 0; i < 16; ++i) input[i] = 0x00UL;

    cl_blake2b_compress(state, (uchar*)input, 0x80UL, 0x00UL);

    for(int i = 0; i < 8; ++i)
    {
        cl_blake2b_compress(state, (uchar*)(in + (i * 128)), 0x100 + (0x80 * i), 0x00UL);
    }

	#pragma unroll
    for(int i = 0; i < 9; ++i) ((uint *)input)[i] = ((uint *)(in + 1024))[i];
	
    cl_blake2b_compress(state, (uchar*)input, 0x4A4UL, 0xFFFFFFFFFFFFFFFFUL);

	#pragma unroll
	for(int i = 0; i < 8; ++i) ((ulong *)out)[i] = state[i];
}

void Blake2B_K64_36B(uchar *out, uchar *in)
{
    ulong input[16], state[8];

    #pragma unroll
    for(int i = 0; i < 8; ++i) state[i] = blake2b_IV[i];

	//state[0] ^= (digestlen | (keylen << 8) | 0x1010000);
    state[0] ^= ((256 >> 3) | (64 << 8) | 0x1010000);

    // Key
    #pragma unroll
    for(int i = 0; i < 64; ++i) ((uchar *)input)[i] = 0x01UL;

    #pragma unroll
    for(int i = 64; i < 128; ++i) ((uchar *)input)[i] = 0x00UL;

    cl_blake2b_compress(state, (uchar*)input, 0x80UL, 0x00UL);

    #pragma unroll
    for(int i = 0; i < 4; ++i) input[i] = ((ulong *)in)[i];

    ((uint *)input)[8] = ((uint *)in)[8];
    
	#pragma unroll
    for(int i = 9; i < 32; ++i) ((uint *)input)[i] = 0x00UL;

    cl_blake2b_compress(state, (uchar*)input, 0xA4UL, 0xFFFFFFFFFFFFFFFFUL);

	#pragma unroll
	for(int i = 0; i < 8; ++i) ((ulong *)out)[i] = state[i];
}

void Blake2B_K64_1060B(uchar *out, uchar *in)
{
    ulong input[16], state[8];

    #pragma unroll
    for(int i = 0; i < 8; ++i) state[i] = blake2b_IV[i];

	//state[0] ^= (digestlen | (keylen << 8) | 0x1010000);
    state[0] ^= ((256 >> 3) | (64 << 8) | 0x1010000);

    // Key
    #pragma unroll
    for(int i = 0; i < 64; ++i) ((uchar *)input)[i] = 0x01UL;

	#pragma unroll
	//for(int i = 8; i < 16; ++i) input[i] = 0x00ULL;
	for(int i = 8; i < 16; ++i) input[i] = 0x00UL;

    cl_blake2b_compress(state, (uchar *)input, 0x80UL, 0x00UL);

    for(int i = 0; i < 8; ++i)
    {
        cl_blake2b_compress(state, in + (i * 128), 0x100 + (0x80 * i), 0x00UL);
    }

	#pragma unroll
    for(int i = 0; i < 9; ++i) ((uint *)input)[i] = ((uint *)(in + 1024))[i];

	#pragma unroll
    for(int i = 9; i < 32; ++i) ((uint *)input)[i] = 0x00;

    cl_blake2b_compress(state, (uchar*)input, 0x4A4UL, 0xFFFFFFFFFFFFFFFFUL);

	#pragma unroll
	for(int i = 0; i < 8; ++i) ((ulong *)out)[i] = state[i];
}

__kernel void test_blake2b(__global uchar *in, __global uchar *out) {
	uint thread = get_global_id(0);
	uint index = thread + 0x20;

    ulong input[16], state[8];

    #pragma unroll
    for(int i = 0; i < 4; ++i) input[i] = ((__global ulong *)in)[i];

    ((uint *)input)[8] = index;

	Blake2B_K32_36B((uchar*)state, (uchar*)input);	

	for (int i = 0; i < 32; i++) {
		out[32*thread + i] = ((uchar *)state)[i];
	}
}
