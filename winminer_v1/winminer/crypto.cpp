/* crypto.cpp Various Crypto Functions
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#include "winminer.h"

/*
 * sha256.c is based on public domain code by Brad Conte
 * (brad AT bradconte.com).
 * https://raw.githubusercontent.com/B-Con/crypto-algorithms/master/sha256.c
*/

void sha256_transform(SHA256_CTX *ctx, const byte data[])
{
	word32 a, b, c, d, e, f, g, h, t1, t2, m[64];
	int i, j;

	for (i = j = 0; i < 16; ++i, j += 4)
		m[i] = ((word32)data[j] << 24) | ((word32)data[j + 1] << 16)
		| ((word32)data[j + 2] << 8) | ((word32)data[j + 3]);
	for (; i < 64; ++i)
		m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];

	a = ctx->state[0];
	b = ctx->state[1];
	c = ctx->state[2];
	d = ctx->state[3];
	e = ctx->state[4];
	f = ctx->state[5];
	g = ctx->state[6];
	h = ctx->state[7];

	for (i = 0; i < 64; ++i) {
		t1 = h + EP1(e) + CH(e, f, g) + k[i] + m[i];
		t2 = EP0(a) + MAJ(a, b, c);
		h = g;
		g = f;
		f = e;
		e = d + t1;
		d = c;
		c = b;
		b = a;
		a = t1 + t2;
	}

	ctx->state[0] += a;
	ctx->state[1] += b;
	ctx->state[2] += c;
	ctx->state[3] += d;
	ctx->state[4] += e;
	ctx->state[5] += f;
	ctx->state[6] += g;
	ctx->state[7] += h;
}

void sha256_init(SHA256_CTX *ctx)
{
	ctx->datalen = 0;
#ifdef LONG64
	ctx->bitlen = 0;
#else
	ctx->bitlen = ctx->bitlen2 = 0;
#endif
	ctx->state[0] = 0x6a09e667L;
	ctx->state[1] = 0xbb67ae85L;
	ctx->state[2] = 0x3c6ef372L;
	ctx->state[3] = 0xa54ff53aL;
	ctx->state[4] = 0x510e527fL;
	ctx->state[5] = 0x9b05688cL;
	ctx->state[6] = 0x1f83d9abL;
	ctx->state[7] = 0x5be0cd19L;
}

void sha256_update(SHA256_CTX *ctx, const byte data[], unsigned len)
{
	unsigned i;
	word32 old;

	for (i = 0; i < len; ++i) {
		ctx->data[ctx->datalen] = data[i];
		ctx->datalen++;
		if (ctx->datalen == 64) {
			sha256_transform(ctx, ctx->data);
#ifdef LONG64
			ctx->bitlen += 512;
#else
			old = ctx->bitlen;
			ctx->bitlen += 512;
			if (ctx->bitlen < old) ctx->bitlen2++;
#endif
			ctx->datalen = 0;
		}
	}
}

void sha256_final(SHA256_CTX *ctx, byte hash[])
{
	unsigned i, j;
	word32 old;

	i = ctx->datalen;

	if (ctx->datalen < 56) {
		ctx->data[i++] = 0x80;
		while (i < 56)
			ctx->data[i++] = 0x00;
	}
	else {
		ctx->data[i++] = 0x80;
		while (i < 64)
			ctx->data[i++] = 0x00;
		sha256_transform(ctx, ctx->data);
		memset(ctx->data, 0, 56);
	}

#ifdef LONG64
	ctx->bitlen += ctx->datalen * 8;
#else
	old = ctx->bitlen;
	ctx->bitlen += ctx->datalen * 8;
	if (ctx->bitlen < old) ctx->bitlen2++;
#endif
	ctx->data[63] = ctx->bitlen;
	ctx->data[62] = ctx->bitlen >> 8;
	ctx->data[61] = ctx->bitlen >> 16;
	ctx->data[60] = ctx->bitlen >> 24;
#ifndef LONG64
	ctx->data[59] = ctx->bitlen2;
	ctx->data[58] = ctx->bitlen2 >> 8;
	ctx->data[57] = ctx->bitlen2 >> 16;
	ctx->data[56] = ctx->bitlen2 >> 24;
#else
	ctx->data[59] = ctx->bitlen >> 32;
	ctx->data[58] = ctx->bitlen >> 40;
	ctx->data[57] = ctx->bitlen >> 48;
	ctx->data[56] = ctx->bitlen >> 56;
#endif
	sha256_transform(ctx, ctx->data);

	/* Since this implementation uses little endian byte ordering and
	 * SHA uses big endian, reverse all the bytes when copying the final
	 * state to the output hash.
	 */
	for (i = j = 0; i < 4; ++i, j += 8) {
		hash[i] = (ctx->state[0] >> (24 - j));
		hash[i + 4] = (ctx->state[1] >> (24 - j));
		hash[i + 8] = (ctx->state[2] >> (24 - j));
		hash[i + 12] = (ctx->state[3] >> (24 - j));
		hash[i + 16] = (ctx->state[4] >> (24 - j));
		hash[i + 20] = (ctx->state[5] >> (24 - j));
		hash[i + 24] = (ctx->state[6] >> (24 - j));
		hash[i + 28] = (ctx->state[7] >> (24 - j));
	}
	memset(ctx, 0, sizeof(SHA256_CTX));
}

void sha256(const byte *in, int inlen, byte *hashout)
{
	SHA256_CTX ctx;

	sha256_init(&ctx);
	sha256_update(&ctx, in, inlen);
	sha256_final(&ctx, hashout);
}

word16 crc16(void *buff, int len)
{
	word16 crc = 0;
	byte *bp;

	for (bp = (byte *)buff; len; len--, bp++)
		crc = update_crc16(crc, *bp);

	return crc;
}

void crctx(TX *tx)
{
	put16(CRC_VAL_PTR(tx), crc16(CRC_BUFF(tx), CRC_COUNT));
}

void hashblock(char *fname, SHA256_CTX *bctx, int offset)
{
	FILE *fp;
	byte buff[16384];
	long len;
	int n, count;

	fp = fopen(fname, "rb");
	if (fp == NULL) return;
	fseek(fp, 0, SEEK_END);
	len = ftell(fp) - offset;
	if (len < 0) len = 0;
	fseek(fp, 0, SEEK_SET);
	sha256_init(bctx);
	for (n = 16384; len; len -= count) {
		if (len < 16384) n = len;
		count = fread(buff, 1, n, fp);
		if (count < 1) break;
		sha256_update(bctx, buff, count);
	}
	fclose(fp);
}
