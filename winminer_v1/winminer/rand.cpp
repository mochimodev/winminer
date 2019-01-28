/* rand.cpp Random Number Generation Functions
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

/* Attribution: Some of the below random number generation schema is derivative of 
 * methods suggested on Usenet by Dr. Marsaglia. Adequate Systems retains full copyright
 * to the present implementation, but wished to acknowledge the contribution of Dr. M 
 * to our understanding of and development of these processes. */

#include "winminer.h"

static word32 Lseed = 1;
static word32 Lseed2 = 1;
static word32 Lseed3 = 362436069;
static word32 Lseed4 = 123456789;

word32 srand16(word32 x)
{
	word32 r;

	r = Lseed;
	Lseed = x;
	return r;
}

word32 rand16(void)
{
	Lseed = Lseed * 69069L + 262145L;
	return (Lseed >> 16);
}
void srand2(word32 x, word32 y, word32 z)
{
	Lseed2 = x;
	Lseed3 = y;
	Lseed4 = z;
}

void getrand2(word32 *x, word32 *y, word32 *z)
{
	*x = Lseed2;
	*y = Lseed3;
	*z = Lseed4;
}

/* Below based on Dr. Marsaglia's Usenet post */
word32 rand2(void)
{
	Lseed2 = Lseed2 * 69069L + 262145L;  /* LGC */
	if (Lseed3 == 0) Lseed3 = 362436069;
	Lseed3 = 36969 * (Lseed3 & 65535) + (Lseed3 >> 16);  /* MWC */
	if (Lseed4 == 0) Lseed4 = 123456789;
	Lseed4 ^= (Lseed4 << 17);
	Lseed4 ^= (Lseed4 >> 13);
	Lseed4 ^= (Lseed4 << 5);  /* LFSR */
	return (Lseed2 ^ (Lseed3 << 16) ^ Lseed4) >> 16;
}
