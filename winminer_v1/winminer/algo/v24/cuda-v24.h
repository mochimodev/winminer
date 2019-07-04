#pragma once

#include "../../winminer.h"

extern "C" {
	//int cuda_v24_mine(BTRAILER *pBtrailer, uint32_t difficulty, byte *pHaiku, uint32_t *pHashrate, unsigned char *pExitSignal);
	int cuda_v24_mine(uint8_t *pBtrailer, uint32_t difficulty, byte *pHaiku, uint64_t *pHashrate, unsigned char *pExitSignal);
	void cuda_v24_free();
	//int cuda_v24_init(BTRAILER *pBtrailer, uint32_t blocknum);
	int cuda_v24_init(uint8_t *pBtrailer, uint32_t blocknum);
}