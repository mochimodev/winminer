#pragma once
#include <stdint.h>
#include "../../types.h"

extern "C" {
	int init_cuda_peach(byte difficulty, byte *prevhash, byte *blocknumber);
	void free_cuda_peach();
	void cuda_peach(byte *bt, uint32_t *hps, byte *runflag);
}