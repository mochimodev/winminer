/* miner.cpp Download and Mine Candidate Blocks
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#include "winminer.h"
#include "miner.h"
#include "gui.h"
#include "algo/peach/cuda_peach.h"
#include "algo/peach/peach.h"
extern "C" {
#include "crypto/hash/cpu/keccak.h"
}

uint64_t haikurate = 0;
uint64_t current_block = 0;
uint32_t current_diff = 0;
uint64_t tx_count = 0;
uint32_t blocks_solved = 0;
uint32_t num_cuda = 0;
uint32_t num_opencl = 0;


int miner(char *blockin, char *blockout, char *addrfile, Compute_Type ct)
{
	BTRAILER bt;
	FILE *fp;
	SHA256_CTX bctx;
	char *haiku;
	byte v24haiku[256] = "";
	time_t htime;
	int etime;
	byte cbnum[8];
	uint64_t hcount, hps;
	int initGPU = 0;
	int loopcount = 0;

	printf("\nTrace: About to get block number from network.");
	if (set_bnum(cbnum) != VEOK) {
		printf("\nTrace: Failed to Collect Updated Bnum");
	}
	for (;; Sleep(10)) {
		if (Running != 1) {
			printf("\nTrace: Bailing due to Running !=1");
			break;
		}
		if (!exists(blockin)) {
			printf("\nTrace: No Block to mine.");
			break;
		}
		if (readtrailer(&bt, blockin) != VEOK) {
			printf("\nminer: read error");
			break;
		}
		if (cmp64(Cblocknum, bt.bnum) >= 0) {
			printf("\nminer:candidate block behind, trying again.");
			Nextcore++;
			break;
		}
		_unlink("m3.tmp");
		if (rename(blockin, "m3.tmp") != 0) {
			printf("\nminer: cannot rename %s", blockin);
			break;
		}
		patch_addr("m3.tmp", addrfile, &bt);
		printf("\nTrace: Patched in your mining address successfully.");

		printf("\nminer: beginning solve: %s block: 0x%s", blockin,
			bnum2hex(bt.bnum));

		// v2.4 and later
		if ((initGPU = init_cuda_peach(bt.difficulty[0], bt.phash, bt.bnum)) < 1) {
			printf("Failed to initialize GPU devices\n");
			break;
		}

		if (initGPU < 1 || initGPU > 64) {
			printf("\nTrace: unsupported number of GPUs detected -> %d", initGPU);
			break;
		}

		printf("\nDetected %d compatible GPUs", initGPU);
		for (htime = time(NULL), hcount = 0; ; ) {
			if (!Running) break;
			cuda_peach((byte*)&bt, (uint32_t*)&hps, &Running);
			
			// Block validation check
			if (peach(&bt, get32(bt.difficulty), NULL, 1)) {
				byte *bt_bytes = (byte*)&bt;
				char hex[124 * 4];
				for (int i = 0; i < 124; i++) {
					sprintf(hex + i * 4, "%03i", bt_bytes[i]);
				}

				printf("!!!!CUDA Peach solved block is not valid!!!!!\n");
				printf("CPU BT -> %s\n", hex);
				Sleep(5000);
				free_cuda_peach();
				break;
			}

			// Print Haiku
			char phaiku[256];
			trigg_expand2(bt.nonce, (byte*)phaiku);
			printf("\n%s\n\n", phaiku);
			//haiku = trigg_generate_gpu(bt.mroot, (uint32_t*)&hcount, ct);
			
			printf("\n\n\n\nBLOCK SOLVED!!!!!\n\n\n\n");

			etime = (time(NULL) - htime);
			if (etime >= 10) {
				hps = hcount / etime;
				hcount = 0;
				htime = time(NULL);
				loopcount++;
				printf("\n\nStatus (solving):  HPS: %luM/h Now Solving: 0x%s  Diff: %d  TX Count: %lu Blocks Solved: %d\n",
					(unsigned long)hps, bnum2hex(bt.bnum), bt.difficulty[0], (unsigned long)get32(bt.tcount), solvedblocks);
				set_status("solving");
				haikurate = hps;
				current_block = *((uint64_t*)bt.bnum);
				current_diff = bt.difficulty[0];
				tx_count = (uint64_t)get32(bt.tcount);
				blocks_solved = solvedblocks;
			}
			if (haiku != NULL) break;
			if (exists("restart.lck")) {
				printf("\nNetwork Block Update Detected, Downloading new block to mine.");
				set_status("updating block");
				//trigg_free_gpu(ct);
				free_cuda_peach();
				return VERROR;
			}
			if (enable_gui && check_gui_thread_alive() != 1) {
				printf("\nGUI no longer running, exiting.");
				Running = 0;
			}
			Sleep(1);

			break; // TODO: FIX THIS
		}
		//trigg_free_gpu(ct);
		free_cuda_peach();
		if (!Running) break;

		/*if (!trigg_check(bt.mroot, bt.difficulty[0], bt.bnum)) {
			printf("ERROR - Block is not valid!\n");
		}*/

		Sleep(2);
		put32(bt.stime, time(NULL));
		printf("\nTrace: About to hash block.");
		hashblock("m3.tmp", &bctx, (HASHLEN + 4 + HASHLEN));
		printf("\nTrace: Block hash completed.");
		sha256_update(&bctx, bt.nonce, HASHLEN + 4);
		sha256_final(&bctx, bt.bhash);
		fp = fopen("m3.tmp", "r+b");
		if (fp == NULL) {
			printf("\nminer: cannot re-open m3.tmp");
			break;
		}
		if (fseek(fp, -(sizeof(BTRAILER)), SEEK_END) != 0) {
			fclose(fp);
			printf("\nminer: cannot fseek(trailer) m3.tmp");
			break;
		}
		if (fwrite(&bt, 1, sizeof(bt), fp) != sizeof(bt)) {
			fclose(fp);
			printf("\nminer: cannot fwrite(trailer) m3.tmp");
			break;
		}
		fclose(fp);
		_unlink(blockout);
		if (rename("m3.tmp", blockout) != 0) {
			printf("\nminer: cannot rename m3.tmp");
			break;
		}
		printf("\nminer: You solved a block!!");
		printf("\nminer: Solved block 0x%s is now: %s",
			bnum2hex(bt.bnum), blockout);

		//printf("\n\n%s\n\n", haiku);
		return VEOK;
	}
	printf("Miner exiting...\n");
	return VERROR;
}
