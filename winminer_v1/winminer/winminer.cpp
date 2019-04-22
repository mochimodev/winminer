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
#include <winhttp.h>
#include "util.cpp"
#include "rand.cpp"
#include "comms.cpp"
#include "crypto.cpp"
#include "miner.cpp"
#include "wots.cpp"
#include "trigg.cpp"

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "Ws2_32.lib")

char *Addrfile = "maddr.dat";
char *Corefname = "fullnodes.lst";
char *WebAddress = "https://www.mochimap.net/";

#define USER_AGENT L"Mochimo Winminer/1.4"

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
		"           -wURL Pull core ip list file from URL (default: https://www.mochimap.net/)\n"
		"           -cFILENAME.LST read core ip list from file (default: fullnodes.lst)\n"
		"           -tN set Trace to N\n"
		"           -h  this message\n"
	);
	exit(1);
}

void start_update_monitor_if_not_running() {
	static STARTUPINFO si = {sizeof(si)};
	static PROCESS_INFORMATION pi;
	static bool init = 0;
	if (init) {
		DWORD dwExitCode = WaitForSingleObject(pi.hProcess, 0);
		if (dwExitCode == WAIT_TIMEOUT) {
			// Process is running;
			return;
		} else if (dwExitCode == WAIT_FAILED
				|| dwExitCode == WAIT_OBJECT_0
				|| dwExitCode == WAIT_ABANDONED) {
			printf("update-monitor is not running\n");
			CloseHandle(pi.hThread);
			CloseHandle(pi.hProcess);
		}
	}

	if (CreateProcess(NULL, "update-monitor.exe", NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
		printf("update-monitor started\n");
		init = 1;
	} else {
		printf("Failed to start update-monitor.exe\n");
	}
}

void download_file(char *url) {
	printf("Downloading file from %s\n", url);
	const int max_size = 8192;
	char local_url[8192];
	strcpy(local_url, url);
	url = local_url;

	bool secure = 0;
	int port = 80;
	if (memcmp(url, "https://", 8) == 0) {
		secure = 1;
		port = 443;
		url = url + 8;
	}
	else if (memcmp(url, "http://", 7) == 0) {
		secure = 0;
		url = url + 7;
	}
	else {
		printf("Unsupported URL protocol! Assuming http://\n");
	}

	char *domainstr = url;
	wchar_t domain[8192];
	char *portstr = strstr(url, ":");
	char *filestr = strstr(url, "/");
	wchar_t file[8192];
	if (filestr != NULL) {
		mbstowcs(file, filestr, 8192);
		*filestr++ = 0;
	}
	if (portstr != NULL) {
		*portstr++ = 0;
		port = atoi(portstr);
		printf("Custom port: %d\n", port);
	}
	mbstowcs(domain, domainstr, 8192);
	wprintf(L"Domain: %s, Port: %d, Secure: %d, File: %s\n", domain, port, secure, file);

	HINTERNET hSession = WinHttpOpen(USER_AGENT, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (!hSession) {
		printf("WinHttpOpen failed\n");
		return;
	}
	HINTERNET hConnect = WinHttpConnect(hSession, domain, port, 0);
	if (!hConnect) { 
		printf("WinHttpConnect failed: Error %u\n", GetLastError());
		return;
	}
	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", file, NULL, WINHTTP_NO_REFERER, NULL, WINHTTP_FLAG_SECURE);
	if (!hRequest) {
		printf("WinHttpOpenRequest failed: Error: %u\n", GetLastError());
		return;
	}
	BOOL res = WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
	if (!res) {
		printf("WinHttpSendRequest failed: Error: %u\n", GetLastError());
		return;
	}
	res = WinHttpReceiveResponse(hRequest, NULL);
	if (!res) {
		printf("WinHttpReceiveResponse failed: Error %u\n", GetLastError());
		return;
	}

	HANDLE hFile = CreateFile(Corefname, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	DWORD downloaded = 0;
	void *outbuf = malloc(max_size);
	if (outbuf == NULL) {
		printf("Unable to allocate memory\n");
		return;
	}
	for (;;) {
		DWORD n = 0;
		if (!WinHttpQueryDataAvailable(hRequest, &n)) {
			printf("WinHttpQueryDataAvailable failed: Error %u\n", GetLastError());
		}
		if (n == 0) {
			// No more data
			break;
		}
		else if (n > max_size) {
			n = max_size;
		}
		printf("Fetching %u bytes of data\n", n);

		memset(outbuf, 0, max_size);
		if (!WinHttpReadData(hRequest, (LPVOID)outbuf, n, &downloaded))
		{
			printf("WinHttpReadData failed: Error %u\n", GetLastError());
		}
		else
		{
			DWORD wmWritten;
			bool fr = WriteFile(hFile, outbuf, n, &wmWritten, NULL);
			//printf("wmWritten: %u\n", wmWritten);
			int n = GetLastError();
			//printf("lasterror = %u\n", n);
		}
		//printf("n= %u\n", n);
	}
	free(outbuf);
	CloseHandle(hFile);
	printf("Downloaded: %u bytes\n", downloaded);

	if (hRequest) WinHttpCloseHandle(hRequest);
	if (hConnect) WinHttpCloseHandle(hConnect);
	if (hSession) WinHttpCloseHandle(hSession);
}

int main(int argc, char **argv)
{
	int j, status;
	time_t stime;
	FILE *restartlock;
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
		case 'w': WebAddress = &argv[j][2];
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

	printf("\nMochimo Windows Headless Miner version 1.4.2\n"
		"Mochimo Main Net v2.3 Original Release Date: 04/07/2019\n"
		"Copyright (c) 2019 by Adequate Systems, LLC."
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

	char urlbuf[8192];
	strcpy_s(urlbuf, 8192, WebAddress);
	strcat_s(urlbuf, 8192, Corefname);
	download_file(urlbuf);
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
		start_update_monitor_if_not_running();
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
