/* util.cpp Miscellaneous Utilities
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 26 January 2019
 *
*/


#include "winminer.h"

word16 get16(void *buff)
{
	return *((word16 *)buff);
}

void put16(void *buff, word16 val)
{
	*((word16 *)buff) = val;
}

word32 get32(void *buff)
{
	return *((word32 *)buff);
}

void put32(void *buff, word32 val)
{
	*((word32 *)buff) = val;
}

void put64(void *buff, void *val)
{
	((word32 *)buff)[0] = ((word32 *)val)[0];
	((word32 *)buff)[1] = ((word32 *)val)[1];
}

int cmp64(void *a, void *b)
{
	word32 *pa, *pb;

	pa = (word32 *)a;
	pb = (word32 *)b;
	if (pa[1] > pb[1]) return 1;
	if (pa[1] < pb[1]) return -1;
	if (pa[0] > pb[0]) return 1;
	if (pa[0] < pb[0]) return -1;
	return 0;
}

void shuffle32(word32 *list, word32 len)
{
	word32 *ptr, *p2, temp;

	if (len < 2) return;
	for (ptr = &list[len - 1]; len > 1; len--, ptr--) {
		p2 = &list[rand16() % len];
		temp = *ptr;
		*ptr = *p2;
		*p2 = temp;
	}
}

void ctrlc(int sig)
{
	signal(SIGINT, ctrlc);
	Sigint = 1;
	Running = 0;
}


/* Display terminal error message
 * and exit.
 */
void fatal(char *fmt, ...)
{
	va_list argp;

	fprintf(stdout, "miner3: ");
	va_start(argp, fmt);
	vfprintf(stdout, fmt, argp);
	va_end(argp);
	printf("\n");
#ifdef _WINSOCKAPI_
	if (Needcleanup)
		WSACleanup();
#endif
	exit(2);
}

char *ntoa(byte *a)
{
	static char s[24];

	sprintf(s, "%d.%d.%d.%d", a[0], a[1], a[2], a[3]);
	return s;
}

int exists(char *fname)
{
	FILE *fp;

	fp = fopen(fname, "rb");
	if (!fp) return 0;
	fclose(fp);
	return 1;
}

char *bnum2hex(byte *bnum)
{
	static char buff[20];

	sprintf(buff, "%02x%02x%02x%02x%02x%02x%02x%02x",
		bnum[7], bnum[6], bnum[5], bnum[4],
		bnum[3], bnum[2], bnum[1], bnum[0]);
	return buff;
}

int readtrailer(BTRAILER *trailer, char *fname)
{
	FILE *fp;

	fp = fopen(fname, "rb");
	if (fp == NULL) return VERROR;
	if (fseek(fp, -(sizeof(BTRAILER)), SEEK_END) != 0) {
	bad:
		fclose(fp);
		return VERROR;
	}
	if (fread(trailer, 1, sizeof(BTRAILER), fp) != sizeof(BTRAILER)) goto bad;
	fclose(fp);
	return VEOK;
}

int read_coreipl(char *fname)
{
	FILE *fp;
	char buff[128];
	int j;
	char *addrstr;
	word32 ip;

	if (fname == NULL || *fname == '\0') return -1;
	fp = fopen(fname, "rb");
	if (fp == NULL) return -1;

	for (j = 0; j < CORELISTLEN; ) {
		if (fgets(buff, 128, fp) == NULL) break;
		if (*buff == '#') continue;
		addrstr = strtok(buff, " \r\n\t");
		if (addrstr == NULL) break;
		ip = str2ip(addrstr);
		if (!ip) continue;
		Coreplist[j++] = ip;
		printf("\nAdded %s to Polling List\n", ntoa((byte *)&ip));
	}
	fclose(fp);
	return j;
}

int patch_addr(char *cblock, char *addrfile)
{
	FILE *fp, *fpout;
	byte buff[TXADDRLEN];
	int ecode = 0;

	fp = fopen(addrfile, "rb");
	if (fp == NULL) {
		printf("\nTrace: Could not open addrfile.");
	}
	fpout = fopen(cblock, "r+b");
	if (fpout == NULL) {
		fclose(fp);
		printf("\nTrace: Unable to write updated candidate block.");
		return VERROR;
	}
	if (fread(buff, 1, TXADDRLEN, fp) != TXADDRLEN) ecode++;
	if (fseek(fpout, 4, SEEK_SET)) ecode++;
	if (fwrite(buff, 1, TXADDRLEN, fpout) != TXADDRLEN) ecode++;
	fclose(fpout);
	fclose(fp);
	return ecode;
}