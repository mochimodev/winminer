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

int miner(char *blockin, char *blockout, char *addrfile)
{
	BTRAILER bt;
	FILE *fp;
	SHA256_CTX bctx;
	char *haiku;
	time_t htime;
	int etime;
	byte cbnum[8];
	uint32_t hcount, hps;
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
		patch_addr("m3.tmp", addrfile);
		printf("\nTrace: Patched in your mining address successfully.");

		printf("\nminer: beginning solve: %s block: 0x%s", blockin,
			bnum2hex(bt.bnum));

		trigg_solve(bt.mroot, bt.difficulty[0], bt.bnum);
		printf("\nTrace: Solution state space created.");

		initGPU = trigg_init_gpu(bt.difficulty[0], bt.bnum);
		if (initGPU < 1 || initGPU > 64) {
			printf("\nTrace: unsupported number of GPUs detected -> %d", initGPU);
			break;
		}

		printf("\nDetected %d compatible NVIDIA GPUs", initGPU);
		byte testtest[8];
		for (htime = time(NULL), hcount = 0; ; ) {
			if (!Running) break;
			haiku = trigg_generate_gpu(bt.mroot, &hcount);
			etime = (time(NULL) - htime);
			if (etime >= 10) {
				hps = hcount / etime;
				hcount = 0;
				htime = time(NULL);
				loopcount++;
				printf("\n\nStatus (solving):  HPS: %luM/h Now Solving: 0x%s  Diff: %d  TX Count: %lu Blocks Solved: %d\n",
					(unsigned long)hps, bnum2hex(bt.bnum), bt.difficulty[0], (unsigned long)get32(bt.tcount), solvedblocks);
			}
			if (haiku != NULL) break;
			if (exists("restart.lck")) {
				printf("\nNetwork Block Update Detected, Downloading new block to mine.");
				trigg_free_gpu();
				return VERROR;
			}
		}
		trigg_free_gpu();
		if (!Running) break;

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

		printf("\n\n%s\n\n", haiku);
		return VEOK;
	}
	printf("Miner exiting...\n");
	return VERROR;
}
