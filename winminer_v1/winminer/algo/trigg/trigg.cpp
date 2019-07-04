/* trigg.cpp C Implementation of Trigg's Algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#include "../../winminer.h"


int Tdiff;
byte Tchain[32 + 256 + 16 + 8];


void trigg_solve(byte *link, int diff, byte *bnum)
{
	Tdiff = diff;
	memset(Tchain + 32, 0, (256 + 16));
	memcpy(Tchain, link, 32);
	memcpy(Tchain + 32 + 256 + 16, bnum, 8);
	put16(link + 32, rand16());
	put16(link + 34, rand16());
	put16(Tchain + (32 + 256), rand16());
	put16(Tchain + (32 + 258), rand16());
}

int trigg_eval(byte *h, byte d)
{
	byte *bp, n;

	n = d >> 3;
	for (bp = h; n; n--) {
		if (*bp++ != 0) return NIL;
	}
	if ((d & 7) == 0) return T;
	if ((*bp & (~(0xff >> (d & 7)))) != 0)
		return NIL;
	return T;
}

int trigg_step(byte *in, int n)
{
	byte *bp;

	for (bp = in; n; n--, bp++) {
		bp[0]++;
		if (bp[0] != 0) break;
	}
	return T;
}

char *trigg_expand(byte *in, int diff)
{
	int j;
	byte *bp, *w;

	bp = &Tchain[32];
	memset(bp, 0, 256);
	for (j = 0; j < 16; j++, in++) {
		if (*in == NIL) break;
		w = TPTR(*in);
		while (*w) *bp++ = *w++;
		if (bp[-1] != '\n') *bp++ = ' ';
	}
	return (char *)&Tchain[32];
}

void trigg_expand2(byte *in, byte *out) {
	int j;
	byte *w;

	memset(out, 0, 256);

	for (j = 0; j < 16; j++, in++) {
		if (*in == NIL) break;
		w = TPTR(*in);
		while (*w) *out++ = *w++;
		if (out[-1] != '\n') *out++ = ' ';
	}
}

byte *trigg_gen(byte *in)
{
	byte *hp;
	FE *fp;
	int j, widx;

	fp = FRAME();
	hp = in;
	for (j = 0; j < 16; j++, fp++) {
		if (*fp == NIL) {
			NCONC(hp, NIL);
			continue;
		}
		if (MEMQ(F_XLIT, *fp)) {
			widx = CDR(*fp);
		}
		else {
			for (;;) {
				widx = TOKEN();
				if (CAT(widx, *fp)) break;
			}
		}
		NCONC(hp, widx);
	}
	return in;
}

char *trigg_generate(byte *in, int diff)
{
	byte h[32];
	char *cp;

	trigg_gen(in + 32);
	trigg_gen(&Tchain[32 + 256]);
	cp = trigg_expand(in + 32, diff);
	sha256(Tchain, (32 + 256 + 16 + 8), h);
	if (trigg_eval(h, diff) == NIL) {
		trigg_step((Tchain + 32 + 256), 16);
		return NULL;
	}
	memcpy(in + (32 + 16), &Tchain[32 + 256], 16);
	return cp;
}

int trigg_syntax(byte *in)
{
	FE f[MAXH], *fp;
	int j;

	for (j = 0; j < MAXH; j++)
		f[j] = Dict[in[j]].fe;

	for (fp = &Frame[0][0]; fp < &Frame[NFRAMES][0]; fp += MAXH) {
		for (j = 0; j < MAXH; j++) {
			if (fp[j] == NIL) {
				if (f[j] == NIL) return T;
				break;
			}
			if (MEMQ(F_XLIT, fp[j])) {
				if (CDR(fp[j]) != in[j]) break;
				continue;
			}
			if (HFE(f[j], fp[j]) == NIL) break;
		}
		if (j >= MAXH) return T;
	}
	return NIL;
}

char *trigg_check(byte *in, byte d, byte *bnum)
{
	byte h[32];
	char *cp;

	cp = trigg_expand(in + 32, d);
	if (trigg_syntax(in + 32) == NIL) return NULL;
	if (trigg_syntax(in + (32 + 16)) == NIL) return NULL;
	memcpy(Tchain, in, 32);
	memcpy((Tchain + 32 + 256), in + (32 + 16), 16);
	memcpy((Tchain + 32 + 256 + 16), bnum, 8);
	sha256(Tchain, (32 + 256 + 16 + 8), h);
	if (trigg_eval(h, d) == NIL) return NULL;
	return cp;
}
