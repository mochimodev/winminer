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
#include <nvml.h>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "Ws2_32.lib")

#include "gui.h"

char *Addrfile = "maddr.dat";
char *Corefname = "fullnodes.lst";
char *WebAddress = "https://www.mochimap.net/";

/* IP's of the Fallback Nodes (Original Core Network) */
/* Only used if no other server can be found.         */
word32 Coreplist[CORELISTLEN] = {
   0x332a9741,    /* 65.151.42.11 */
};

#define USER_AGENT L"Mochimo Winminer/" WINMINER_VERSION

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
bool enable_gui = true;

uint8_t enable_nvml = 0;
GPU_t gpus[64] = { 0 };
uint32_t num_gpus = 0;
#define NVML_DLL "C:\\Program Files\\NVIDIA Corporation\\NVSMI\\NVML.DLL"

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
		"           -f  disable GUI\n"
		"           -U  force CUDA mode\n"
		"           -O  force OpenCL mode\n"
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
	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", file, NULL, WINHTTP_NO_REFERER, NULL, secure ? WINHTTP_FLAG_SECURE : 0);
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
	bool force_cuda = false;
	bool force_opencl = false;

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
		case 'f':
			enable_gui = false;
			break;
		case 'x':  if (strlen(argv[j]) != 8) break;
			Statusarg = argv[j];
			break;
		case 'U':
			force_cuda = true;
			break;
		case 'O':
			force_opencl = true;
			break;
		default:   usage();
		}
	}

	int32_t num_cuda = 0;
	cudaError_t cr = cudaGetDeviceCount(&num_cuda);
	if (num_cuda > MAX_GPUS) num_cuda = MAX_GPUS;

	for (int i = 0; i < num_cuda; i++) {
		struct cudaDeviceProp p = { 0 };
		cudaError_t cr = cudaGetDeviceProperties(&p, i);
		printf("CUDA pciDomainID: %x, pciBusID: %x, pciDeviceID: %x\n", p.pciDomainID, p.pciBusID, p.pciDeviceID);
		gpus[i].pciDomainId = p.pciDomainID;
		gpus[i].pciBusId = p.pciBusID;
		gpus[i].pciDeviceId = p.pciDeviceID;
		gpus[i].cudaNum = i;
		num_gpus++;
	}

	if (LoadLibrary(NVML_DLL) == NULL) {
		printf("Failed to load NVML library.\n");
	}
	else {
		enable_nvml = 1;
	}

	if (enable_nvml) {
		nvmlReturn_t r = nvmlInit();
		if (r != NVML_SUCCESS) {
			printf("Failed to initialize NVML: %s\n", nvmlErrorString(r));
		}
		uint32_t nvml_device_count;
		r = nvmlDeviceGetCount(&nvml_device_count);
		if (r != NVML_SUCCESS) {
			printf("Failed to get NVML device count: %s\n", nvmlErrorString(r));
		}
		printf("NVML Devices: %d\n", nvml_device_count);
		for (int i = 0; i < nvml_device_count; i++) {
			nvmlDevice_t dev;
			r = nvmlDeviceGetHandleByIndex(i, &dev);
			if (r != NVML_SUCCESS) {
				printf("nvmlDeviceGetHandleByIndex failed: %s\n", nvmlErrorString(r));
				nvml_device_count = i;
				break;
			}
			nvmlPciInfo_t pci;
			r = nvmlDeviceGetPciInfo(dev, &pci);
			if (r != NVML_SUCCESS) {
				printf("nvmlDeviceGetPciInfo failed: %s\n", nvmlErrorString(r));
				continue;
			}
			printf("NVML PCI: pciDeviceId: %x, pciSubSystemId: %x, domain: %x, device: %x, bus: %x\n", pci.pciDeviceId, pci.pciSubSystemId, pci.domain, pci.device, pci.bus);

			for (int j = 0; j < num_cuda; j++) {
				if (gpus[j].pciDomainId == pci.domain && gpus[j].pciBusId == pci.bus && gpus[i].pciDeviceId == pci.device) {
					printf("NVML device is CUDA Device: %d\n", gpus[j].cudaNum);
					gpus[j].nvml_dev = dev;
					break;
				}
			}

			char device_name[128];
			r = nvmlDeviceGetName(dev, device_name, 128);
			if (r != NVML_SUCCESS) {
				printf("nvmlDeviceGetName failed: %s\n", nvmlErrorString(r));
			}
			else {
				printf("Device: %d, Name: %s\n", i, device_name);
			}
		}
	}

	if (enable_gui) {
		start_gui_thread();
	}

	srand16(time(&stime));
	srand2(stime, 0, 0);

	printf("\nMochimo Windows Headless Miner version " WINMINER_VERSION "\n"
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

	Compute_Type ct;
	if (force_cuda) {
		ct = CT_CUDA;
	}
	else if (force_opencl) {
		ct = CT_OPENCL;
	}
	else {
		ct = autoselect_compute_type();
	}

	for (; Running == 1;) {
		if ((time(NULL) - now) > 3600) goto restart;
		for (; Running == 1;) {
			if (enable_gui) {
				check_gui_thread_alive();
			}

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
		if (miner("candidate.tmp", "solved.tmp", Addrfile, ct) == VEOK) {
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
