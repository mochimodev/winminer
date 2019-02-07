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
char *Corefname = "startnodes.lst";
char *WebAddress = "https://www.mochimap.net:8443/";

byte Needcleanup;
word32 Port = 2095;
char *Peeraddr;
unsigned Nextcore;

byte Cblocknum[8];
byte ServerBnum[8];
byte tempCblocknum[8];
byte Cbits;

int solvedblocks = 0;
byte Running = 1;
byte Trace;

/* IP's of the Fallback Nodes (Original Core Network) */
/* Only used if no other server can be found.         */
word32 Coreplist[CORELISTLEN] = {
   0x0b2a9741,    /* 65.151.42.11 */
   0x0c2a9741,
   0x0d2a9741,
   0x0e2a9741,
   0x0f2a9741,
   0x102a9741,
   0x112a9741,
   0x122a9741,
};

void usage(void)
{
	printf("\nUsage: mochimo-winminer [-option -option2 . . .]\n"
		"All command-line switches are optional.  If left default this miner will pull a full node\n"
		"IP list from mochimap.net, and begin mining.  If you don't have a maddr.dat address file\n"
		"in this directory, it will create one for you called maddr.dat.\n"
		"Options:\n"
		"           -aXXX.XXX.XXX.XXX set IP address to pull block from, exammple: 65.151.42.11\n"
		"           -pN set TCP port to N (default: 2095)\n"
		"           -mFILENAME.ADDR mining address is in file (default: maddr.adr)\n"
		"           -wURL Pull core ip list file from URL (default: https://www.mochimap.net:8443/)\n"
		"           -cFILENAME.LST read core ip list from file (default: startnodes.lst)\n"
		"           -tN set Trace to N\n"
		"           -h  this message\n"
	);
	exit(1);
}

int main(int argc, char **argv)
{
	int j, status;
	time_t stime;
	FILE *pwrshellscript, *restartlock;
	time_t now = time(NULL);
	char *Statusarg;

#ifdef _WINSOCKAPI_
	static WORD wsaVerReq;
	static WSADATA wsaData;

	wsaVerReq = 0x0101;
	if (WSAStartup(wsaVerReq, &wsaData) == SOCKET_ERROR)
		fatal("WSAStartup()");
	Needcleanup = 1;
#endif

	for (j = 1; j < argc; j++) {
		if (argv[j][0] != '-') break;
		switch (argv[j][1]) {
		case 'p':  Port = atoi(&argv[j][2]);
			break;
		case 'a':  if (argv[j][2]) Peeraddr = &argv[j][2];
			break;
		case 'm':  Addrfile = &argv[j][2];
			break;
		case 'W': WebAddress = &argv[j][2];
			break;
		case 'c':  Corefname = &argv[j][2];
			break;
		case 't':  Trace = atoi(&argv[j][2]);
			break;
		case 'x':  if (strlen(argv[j]) != 8) break;
			Statusarg = argv[j];
			break;
		default:   usage();
		}
	}

	srand16(time(&stime));
	srand2(stime, 0, 0);

	printf("\nMochimo Windows Headless Miner version 1.1\n"
		"Mochimo Main Net v2.2 Original Release Date: 10/27/2018\n"
		"Copyright (c) 2018 by Adequate Systems, LLC."
		" All Rights Reserved.\n\n"
		"This software is subject to the terms and conditions of the Mochimo Cryptocurrency Engine\n"
		"license agreement, see LICENSE.PDF for terms and conditions at:\n"
		"https://github.com/mochimodev/mochimo/blob/master/LICENSE.PDF\n\n"
	    "You must read and accept the terms of this license before using this software.\n"
	    "Press CTRL+C to exit the program if you have not yet read and accepted the License agreement.\n");
	

	for (j = 0; j <= NSIG; j++) signal(j, SIG_IGN);
	signal(SIGINT, ctrlc);
	signal(SIGTERM, ctrlc);

restart:
	now = time(NULL);

	_unlink("candidate.tmp");
	_unlink("m3.tmp");
	_unlink("restart.tmp");
	_unlink("restart.lck");
	_unlink("pullnodelist.ps1");
	_unlink(Corefname);

	pwrshellscript = fopen("pullnodelist.ps1", "a");
	if (pwrshellscript != NULL) {
		fprintf(pwrshellscript, "wget %s%s -Outfile %s", WebAddress, Corefname, Corefname);
		fclose(pwrshellscript);
		system("type pullnodelist.ps1 | powershell.exe");
	}
	if (Corefname)
		printf("\ninit: read_coreipl() returned %d peer IPs\n", read_coreipl(Corefname));
	
	shuffle32(Coreplist, CORELISTLEN);
	
	if (Peeraddr) Coreplist[0] = str2ip(Peeraddr);
	
	if (!exists(Addrfile)) {
		printf("\nNOTICE! You did not specify a mining address to load."
			"\nYou can load a mining dress with the command line option -mFILENAME.addr"
			"\nAlternatively, you may place a file named maddr.dat into the directory"
			"\nwith your mochimo-winminer.exe file, and it will be loaded automatically."
			"\n\nYou will now be prompted to create a mining address.  Please ensure that"
			"\nyou enter sufficiently random characters when prompted.\n\n");
		mkwots();
	}
	for (; Running == 1;) {
		if ((time(NULL) - now) > 3600) goto restart;
		for (; Running == 1;) {
			if (exists("restart.lck")) {
				restartlock = fopen("restart.lck", "rb");
				if (restartlock != NULL) {
					fread(tempCblocknum, 8, 1, restartlock);
					fclose(restartlock);
				}
				printf("\nUpdate Discovered, Block: 0x%x%x%x", tempCblocknum[2], tempCblocknum[1], tempCblocknum[0]);
				_unlink("restart.lck");
			}
			if (cmp64(Cblocknum, tempCblocknum) < 0) {
				memcpy(Cblocknum, tempCblocknum, 8);
			}
			status = get_cblock(0, "candidate.tmp");
			if (status == VEOK) {
				printf("\nCandidate block downloaded successfully!");
				break;
			}
		}
		system("start /B update-monitor.exe");
		printf("\nTrace: About to Start Miner.");
		if (miner("candidate.tmp", "solved.tmp", Addrfile) == VEOK) {
			solvedblocks++;
			for (j = 0; j < CORELISTLEN && Running; j++, Nextcore++) {
				status = send_mblock("solved.tmp");
				if (status == VEOK) {
					printf("\nSolved block successfully uploaded to %d peers!", j + 1);
					if (j == (CORELISTLEN - 1)) printf("\nUpload complete!\n\n");
				}
			}
			Sleep(15);
			printf("\nTrace: Completed Main Loop");
		}
	}

#ifdef _WINSOCKAPI_
	if (Needcleanup) WSACleanup();
#endif

	return 0;
}
