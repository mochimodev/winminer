/* mochimo-winminer  Headless Mochimo Miner for Win32
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

/* This software contains source code provided by NVIDIA Corporation.
 * Specifically we incorporate helper_cuda.h and helper_string.h per
 * the NVIDIA TOOLKIT SDK, and subject to the EULA found here:
 * https://docs.nvidia.com/cuda/eula/index.html
 */

#include "winminer.h"

char *Addrfile = "maddr.dat";
char *Corefname = "fullnodes.lst";

word32 Coreplist[CORELISTLEN];
byte Needcleanup;
word32 Port = 2095;
unsigned Nextcore;
byte Cblocknum[8];
byte LastCblocknum[8];
byte Cbits;
byte Running = 1;
byte Trace;

int main(int argc, char **argv)
{
	int j, status;
	time_t stime;
	time_t now = time(NULL);
	char *Statusarg;
	word32 *ip;
	int firstupdate = 1;
	FILE *restartlock;

	static WORD wsaVerReq;
	static WSADATA wsaData;

	wsaVerReq = 0x0101;
	if (WSAStartup(wsaVerReq, &wsaData) == SOCKET_ERROR)
		fatal("WSAStartup()");
	Needcleanup = 1;
	read_coreipl(Corefname);
    for (j = 0 ; ; j++) {
		if (j >= CORELISTLEN) {
			j = 0;
		}
		ip = &Coreplist[j];
		if (*ip == 0) continue;
		set_bnum(Cblocknum, ip);
		if (cmp64(Cblocknum, LastCblocknum) > 0) {
			if (firstupdate != 0) {
				memcpy(LastCblocknum, Cblocknum, 8);
				firstupdate = 0;
				continue;
			}
			printf("\nBlock update detected.");
			memcpy(LastCblocknum, Cblocknum, 8);
			if (cmp64(Cblocknum, LastCblocknum) != 0) printf("\nmemcpy failed.");
			restartlock = fopen("restart.tmp", "w+b");
			if (restartlock == NULL) {
				printf("\nCouldn't open restart lock file.");
			} else {
				fwrite(LastCblocknum, 8, 1, restartlock);
			}
			fclose(restartlock);
			system("copy restart.tmp restart.lck");
			_unlink("restart.tmp");

			// Prepare for next run.
			Sleep(100);
			firstupdate = 1;
		}
	}
	if (Needcleanup) WSACleanup();
	return 0;
}
