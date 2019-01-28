/* wots.cpp WOTS Keypair Generation and Validations 
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#include "winminer.h"

void ull_to_bytes(byte *out, unsigned int outlen,
	unsigned long in)
{
	int i;

	for (i = outlen - 1; i >= 0; i--) {
		out[i] = in & 0xff;
		in = in >> 8;
	}
}

void set_key_and_mask(word32 addr[8], word32 key_and_mask)
{
	addr[7] = key_and_mask;
}

void set_chain_addr(word32 addr[8], word32 chain)
{
	addr[5] = chain;
}

void set_hash_addr(word32 addr[8], word32 hash)
{
	addr[6] = hash;
}

void addr_to_bytes(byte *bytes, const word32 addr[8])
{
	int i;
	for (i = 0; i < 8; i++) {
		ull_to_bytes(bytes + i * 4, 4, addr[i]);
	}
}

int prf(byte *out, const byte in[32],
	const byte *key)
{
	byte buf[2 * PARAMSN + 32];

	ull_to_bytes(buf, PARAMSN, XMSS_HASH_PADDING_PRF);
	memcpy(buf + PARAMSN, key, PARAMSN);
	memcpy(buf + (2 * PARAMSN), in, 32);
	core_hash(out, buf, (2 * PARAMSN) + 32);
	return 0;
}


int thash_f(byte *out, const byte *in,
	const byte *pub_seed, word32 addr[8])
{
	byte buf[3 * PARAMSN];
	byte bitmask[PARAMSN];
	byte addr_as_bytes[32];
	unsigned int i;

	ull_to_bytes(buf, PARAMSN, XMSS_HASH_PADDING_F);

	set_key_and_mask(addr, 0);
	addr_to_bytes(addr_as_bytes, addr);
	prf(buf + PARAMSN, addr_as_bytes, pub_seed);

	set_key_and_mask(addr, 1);
	addr_to_bytes(addr_as_bytes, addr);
	prf(bitmask, addr_as_bytes, pub_seed);

	for (i = 0; i < PARAMSN; i++) {
		buf[2 * PARAMSN + i] = in[i] ^ bitmask[i];
	}
	core_hash(out, buf, 3 * PARAMSN);
	return 0;
}

static void expand_seed(byte *outseeds, const byte *inseed)
{
	word32 i;
	byte ctr[32];

	for (i = 0; i < WOTSLEN; i++) {
		ull_to_bytes(ctr, 32, i);
		prf(outseeds + i * PARAMSN, ctr, inseed);
	}
}

static void gen_chain(byte *out, const byte *in,
	unsigned int start, unsigned int steps,
	const byte *pub_seed, word32 addr[8])
{
	word32 i;

	memcpy(out, in, PARAMSN);

	for (i = start; i < (start + steps) && i < WOTSW; i++) {
		set_hash_addr(addr, i);
		thash_f(out, out, pub_seed, addr);
	}
}

static void base_w(int *output, const int out_len, const byte *input)
{
	int in = 0;
	int out = 0;
	byte total;
	int bits = 0;
	int consumed;

	for (consumed = 0; consumed < out_len; consumed++) {
		if (bits == 0) {
			total = input[in];
			in++;
			bits += 8;
		}
		bits -= WOTSLOGW;
		output[out] = (total >> bits) & (WOTSW - 1);
		out++;
	}
}

static void wots_checksum(int *csum_base_w, const int *msg_base_w)
{
	int csum = 0;
	byte csum_bytes[(WOTSLEN2 * WOTSLOGW + 7) / 8];
	unsigned int i;

	for (i = 0; i < WOTSLEN1; i++) {
		csum += WOTSW - 1 - msg_base_w[i];
	}

	csum = csum << (8 - ((WOTSLEN2 * WOTSLOGW) % 8));
	ull_to_bytes(csum_bytes, sizeof(csum_bytes), csum);
	base_w(csum_base_w, WOTSLEN2, csum_bytes);
}

static void chain_lengths(int *lengths, const byte *msg)
{
	base_w(lengths, WOTSLEN1, msg);
	wots_checksum(lengths + WOTSLEN1, lengths);
}

void wots_pkgen(byte *pk, const byte *seed,
	const byte *pub_seed, word32 addr[8])
{
	word32 i;

	expand_seed(pk, seed);

	for (i = 0; i < WOTSLEN; i++) {
		set_chain_addr(addr, i);
		gen_chain(pk + i * PARAMSN, pk + i * PARAMSN,
			0, WOTSW - 1, pub_seed, addr);
	}
}

void wots_sign(byte *sig, const byte *msg,
	const byte *seed, const byte *pub_seed,
	word32 addr[8])
{
	int lengths[WOTSLEN];
	word32 i;

	chain_lengths(lengths, msg);

	expand_seed(sig, seed);

	for (i = 0; i < WOTSLEN; i++) {
		set_chain_addr(addr, i);
		gen_chain(sig + i * PARAMSN, sig + i * PARAMSN,
			0, lengths[i], pub_seed, addr);
	}
}

void wots_pk_from_sig(byte *pk,
	const byte *sig, const byte *msg,
	const byte *pub_seed, word32 addr[8])
{
	int lengths[WOTSLEN];
	word32 i;

	chain_lengths(lengths, msg);

	for (i = 0; i < WOTSLEN; i++) {
		set_chain_addr(addr, i);
		gen_chain(pk + i * PARAMSN, sig + i * PARAMSN,
			lengths[i], WOTSW - 1 - lengths[i], pub_seed, addr);
	}
}

void rndbytes(byte *out, word32 outlen, byte *seed)
{
	static byte state;
	static byte rnd[RNDSEEDLEN];
	byte hash[32];
	int n;

	if (state == 0) {
		memcpy(rnd, seed, RNDSEEDLEN);
		state = 1;
	}
	for (; outlen; ) {
		for (n = 0; n < RNDSEEDLEN; n++) {
			if (++seed[n] != 0) break;
		}
		for (n = 0; n < RNDSEEDLEN; n++) {
			if (++rnd[n] != 0) break;
		}
		sha256(rnd, RNDSEEDLEN, hash);
		if (outlen < 32) n = outlen; else n = 32;
		memcpy(out, hash, n);
		out += n;
		outlen -= n;
	}
}

void create_addr(byte *addr, byte *secret, byte *seed)
{
	byte rnd2[32];

	rndbytes(secret, 32, seed);

	rndbytes(addr, TXADDRLEN, seed);

	memcpy(rnd2, &addr[TXSIGLEN + 32], 32);

	wots_pkgen(addr, secret, &addr[TXSIGLEN], (word32 *) rnd2);

	memcpy(&addr[TXSIGLEN + 32], rnd2, 32);
}

char *tgets(char *buff, int len)
{
	char *cp, fluff[16];

	*buff = '\0';
	fgets(buff, len, stdin);
	cp = strchr(buff, '\n');
	if (cp) *cp = '\0';
	else {
		for (;;) {
			if (fgets(fluff, 16, stdin) == NULL) break;
			if (strchr(fluff, '\n') != NULL) break;
		}
	}
	return buff;
}

FILE *fopen2(char *fname, char *mode, int fatalflag)
{
	FILE *fp;

	fp = fopen(fname, mode);
	if (!fp && fatalflag) fatal("Cannot open %s", fname);
	return fp;
}

void init_seed(void *rndseed, unsigned len)
{
	FILE *fp;
	byte b;
	char *seed;

	if (len < 5) fatal("init_seed()");
	seed = (char *)rndseed;

	((word16 *)seed)[0] = rand16();
	((word16 *)seed)[1] = rand16();

	len -= 4;
	seed += 4;
	printf("IMPORTANT!!  Enter a random bunch of keystrokes up to %d characters:\n"
		"(You DO NOT need to remember this.  Mash the keys.  This needs to be random.)\n"
		"[<------------THIS IS HOW WIDE 60 CHARACTERS IS----------->]\n", len);
	tgets(seed, len);
	fp = fopen("/dev/random", "rb");
	if (fp) {
		for (; len; len--) {
			if (fread(&b, 1, 1, fp) != 1) break;
			*seed++ ^= b;
		}
		fclose(fp);
	}
}

int mkwots()
{
	static byte addr[TXADDRLEN], secret[32], rndseed[RNDSEEDLEN];
	static FILE *addrfp;
	static byte zeros[8] = { 0 };

	init_seed(rndseed, RNDSEEDLEN);

	create_addr(addr, secret, rndseed);

	addrfp = fopen(Addrfile, "wb");
	if (!addrfp) return VERROR;
	if (fwrite(addr, 1, TXADDRLEN, addrfp) != TXADDRLEN) return VERROR;
	if (fwrite(zeros, 1, 8, addrfp) != 8) return VERROR;
	if (fwrite(secret, 1, 32, addrfp) != 32) return VERROR;
	printf("\nNew WOTS Key-Pair Generated as %s\n", Addrfile);
	fclose(addrfp);;
	return VEOK;
}