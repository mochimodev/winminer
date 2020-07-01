#define SHA1_STEP0(a, b, c, d, e, i) do { \
    uint t = ROTL32(a, 5) + ((b & c) ^ (~b & d)) + e + 0x5A827999U + m[i]; \
    e = d; \
    d = c; \
    c = ROTL32(b, 30); \
    b = a; \
    a = t; \
} while(0)

#define SHA1_STEP1(a, b, c, d, e, i) do { \
    uint t = ROTL32(a, 5) + (b ^ c ^ d) + e + 0x6ED9EBA1U + m[i]; \
	e = d; \
	d = c; \
	c = ROTL32(b, 30); \
	b = a; \
	a = t; \
} while(0)

#define SHA1_STEP2(a, b, c, d, e, i) do { \
    uint t = ROTL32(a, 5) + ((b & c) ^ (b & d) ^ (c & d))  + e + 0x8F1BBCDCU + m[i]; \
	e = d; \
	d = c; \
	c = ROTL32(b, 30); \
	b = a; \
	a = t; \
} while(0)

#define SHA1_STEP3(a, b, c, d, e, i) do { \
    uint t = ROTL32(a, 5) + (b ^ c ^ d) + e + 0xCA62C1D6U + m[i]; \
    e = d; \
    d = c; \
    c = ROTL32(b, 30); \
    b = a; \
    a = t; \
} while(0)

#define SWAP4(x)    	as_uint(as_uchar4(x).s3210)
#define ROTL32(x, y)	rotate((x), (uint)(y))

static const __constant uint SHA1_INIT_CONSTS[5] =
{
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
};

void SHA1Transform(uint *state, const uint *data)
{
	uint m[80];
	
	#pragma unroll
	for(int i = 0; i < 16; ++i)
		m[i] = SWAP4(data[i]);
	
	for (int i = 16; i < 80; ++i)
	{
		m[i] = ROTL32(m[i - 3] ^ m[i - 8] ^ m[i - 14] ^ m[i - 16], 1U);
	}

	uint a = state[0];
	uint b = state[1];
	uint c = state[2];
	uint d = state[3];
	uint e = state[4];

	for(int i = 0; i < 20; ++i)
    {
        SHA1_STEP0(a, b, c, d, e, i);
	}
	for (int i = 20; i < 40; ++i)
    {
		SHA1_STEP1(a, b, c, d, e, i);
	}
	for (int i = 40; i < 60; ++i)
    {
		SHA1_STEP2(a, b, c, d, e, i);
	}
	for (int i = 60; i < 80; ++i)
    {
		SHA1_STEP3(a, b, c, d, e, i);
	}

	state[0] += a;
	state[1] += b;
	state[2] += c;
	state[3] += d;
	state[4] += e;
}

void SHA1Digest36B(uint *Digest, const uint *Input)
{
    uint st[5], m[16];

    #pragma unroll
    for(int i = 0; i < 5; ++i) st[i] = SHA1_INIT_CONSTS[i];

    #pragma unroll
    for(int i = 0; i < 9; ++i) m[i] = Input[i];
    
    #pragma unroll
    for(int i = 10; i < 15; ++i) m[i] = 0x00U;

    // Merkle–Damgård style padding here, except...
	// Do NOT endian-swap the padding! The transform
	// is expecting all little-endian input!
    m[9] = 0x80U;				// Terminator ('1' bit)
    m[15] = 0x20010000U;		// 0x120 bits in big-endian

    SHA1Transform(st, m);

    for(int i = 0; i < 5; ++i) Digest[i] = SWAP4(st[i]);
}

void SHA1Digest1060B(uint *Digest, const uint *Input)
{
    uint st[5], m[16];

    #pragma unroll
    for(int i = 0; i < 5; ++i) st[i] = SHA1_INIT_CONSTS[i];
	
	for(int i = 0; i < 16; ++i)
	{
		#pragma unroll
		for(int x = 0; x < 16; ++x) m[x] = Input[(i << 4) + x];
		
		SHA1Transform(st, m);
	}
	
	// Last block
    #pragma unroll
    for(int i = 0; i < 9; ++i) m[i] = Input[i + 256];
    
    #pragma unroll
    for(int i = 10; i < 15; ++i) m[i] = 0x00U;

    // Merkle–Damgård style padding here, except...
	// Do NOT endian-swap the padding! The transform
	// is expecting all little-endian input!
    m[9] = 0x80U;				// Terminator ('1' bit)
    m[15] = 0x20210000;			// 0x2120 bits in big-endian

    SHA1Transform(st, m);

    for(int i = 0; i < 5; ++i) Digest[i] = SWAP4(st[i]);
}
