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

#pragma comment(lib, "Ws2_32.lib")

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
	time_t interval = 40;
	time_t update = now + interval;
	char *Statusarg;
	word32 *ip;
	int firstupdate = 1;
	int intervalmultiplier = 1;
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
		if (*ip == 0) {
			/* No more IPs in core list, wait 100ms before next check*/
			Sleep(100);
			continue;
		}
		set_bnum(Cblocknum, ip);
		now = time(NULL);
		if (cmp64(Cblocknum, LastCblocknum) > 0 || now >= update) {
			if (firstupdate != 0) {
				memcpy(LastCblocknum, Cblocknum, 8);
				firstupdate = 0;
				continue;
			}
			if(now >= update) {
				intervalmultiplier *= 2;
				printf("\nIntra-Block update.");
			} else {
				intervalmultiplier = 1;
				printf("\nBlock update detected.");
			}
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
			update = now + (interval * intervalmultiplier);
			Sleep(100);
		}
	}
	if (Needcleanup) WSACleanup();
	return 0;
}
